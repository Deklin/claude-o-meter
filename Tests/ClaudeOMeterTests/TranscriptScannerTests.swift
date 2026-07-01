import XCTest
@testable import ClaudeOMeter

final class TranscriptScannerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Resolve /var → /private/var so pathComponent arithmetic matches enumerator URLs.
        tempDir = base.resolvingSymlinksInPath()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func writeLines(_ lines: [String], to url: URL) {
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
        try! data.write(to: url)
    }

    /// Builds a valid JSONL usage line with the given timestamp (ISO-8601).
    private func usageLine(timestamp: String) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"message\":{\"id\":\"msg-\(timestamp)\",\"usage\":{\"input_tokens\":100}}}"
    }

    /// Returns today's date in "YYYY-MM-DD" format (as expected by scanConcurrency).
    private var todayDay: String { DayBucket.localDay(from: Date()) }

    /// Returns "YYYY-MM-DDT" prefix for today, ready to append "HH:MM:SS.000Z".
    private var todayPrefix: String { todayDay + "T" }

    // MARK: - Empty directory

    func testEmptyDirectoryReturnsZeroConcurrency() {
        let stats = TranscriptScanner.scanConcurrency(for: todayDay, rootDirectory: tempDir)
        XCTAssertEqual(stats.peakUserSessions, 0)
        XCTAssertEqual(stats.peakSubagents, 0)
        XCTAssertTrue(stats.peakProjectNames.isEmpty)
    }

    // MARK: - Concurrent user sessions

    func testTwoSessionsInSameWindowCountAsPeakTwo() {
        // Both sessions have usage events at 14:00 → same 5-minute bucket → peak = 2
        let ts1 = todayPrefix + "14:00:00.000Z"
        let ts2 = todayPrefix + "14:02:00.000Z"
        let proj = tempDir.appendingPathComponent("proj-alpha", isDirectory: true)
        writeLines([usageLine(timestamp: ts1)], to: proj.appendingPathComponent("session-a.jsonl"))
        writeLines([usageLine(timestamp: ts2)], to: proj.appendingPathComponent("session-b.jsonl"))

        let stats = TranscriptScanner.scanConcurrency(for: todayDay, rootDirectory: tempDir)
        XCTAssertEqual(stats.peakUserSessions, 2)
    }

    func testNonOverlappingSessionsCountAsPeakOne() {
        // Session A at 14:00, session B at 14:30 → different 5-minute buckets → peak = 1
        let ts1 = todayPrefix + "14:00:00.000Z"
        let ts2 = todayPrefix + "14:30:00.000Z"
        let proj = tempDir.appendingPathComponent("proj-beta", isDirectory: true)
        writeLines([usageLine(timestamp: ts1)], to: proj.appendingPathComponent("session-a.jsonl"))
        writeLines([usageLine(timestamp: ts2)], to: proj.appendingPathComponent("session-b.jsonl"))

        let stats = TranscriptScanner.scanConcurrency(for: todayDay, rootDirectory: tempDir)
        XCTAssertEqual(stats.peakUserSessions, 1)
    }

    // MARK: - Subagents counted separately

    func testSubagentsCountedSeparatelyFromUserSessions() {
        let ts = todayPrefix + "14:00:00.000Z"
        let proj = tempDir.appendingPathComponent("proj-gamma", isDirectory: true)
        // One user session
        writeLines([usageLine(timestamp: ts)], to: proj.appendingPathComponent("session-u.jsonl"))
        // One subagent session
        let subagentDir = proj.appendingPathComponent("subagents", isDirectory: true)
        writeLines([usageLine(timestamp: ts)], to: subagentDir.appendingPathComponent("session-s.jsonl"))

        let stats = TranscriptScanner.scanConcurrency(for: todayDay, rootDirectory: tempDir)
        XCTAssertEqual(stats.peakUserSessions, 1, "User session should count once")
        XCTAssertEqual(stats.peakSubagents, 1, "Subagent session should count separately")
    }

    // MARK: - Other-day lines ignored

    func testYesterdayLinesAreNotCounted() {
        let yesterday = DayBucket.day(daysAgo: 1)
        let ts = yesterday + "T14:00:00.000Z"
        let proj = tempDir.appendingPathComponent("proj-delta", isDirectory: true)
        writeLines([usageLine(timestamp: ts)], to: proj.appendingPathComponent("old-session.jsonl"))

        let stats = TranscriptScanner.scanConcurrency(for: todayDay, rootDirectory: tempDir)
        XCTAssertEqual(stats.peakUserSessions, 0, "Lines from a previous day must not be counted")
    }

    // MARK: - Malformed timestamp (C1 regression)

    func testMalformedTimestampDoesNotCrash() {
        // A timestamp shorter than 16 characters must be ignored without crashing.
        let badLine = "{\"timestamp\":\"2026-07\",\"message\":{\"id\":\"msg-short\",\"usage\":{\"input_tokens\":1}}}"
        let normalLine = usageLine(timestamp: todayPrefix + "14:00:00.000Z")
        let proj = tempDir.appendingPathComponent("proj-epsilon", isDirectory: true)
        writeLines([badLine, normalLine], to: proj.appendingPathComponent("session-crash.jsonl"))

        // Must not crash; the malformed line is silently skipped, the valid one is counted.
        let stats = TranscriptScanner.scanConcurrency(for: todayDay, rootDirectory: tempDir)
        XCTAssertEqual(stats.peakUserSessions, 1, "Valid line should still be counted after malformed one")
    }

    // MARK: - Peak project names

    func testPeakProjectNamesAreCapturedForConcurrentSessions() {
        let ts = todayPrefix + "14:00:00.000Z"
        // Two projects, each with one session at the same time → concurrent
        let projA = tempDir.appendingPathComponent("-Users-me-git-alpha", isDirectory: true)
        let projB = tempDir.appendingPathComponent("-Users-me-git-beta", isDirectory: true)
        writeLines([usageLine(timestamp: ts)], to: projA.appendingPathComponent("s1.jsonl"))
        writeLines([usageLine(timestamp: ts)], to: projB.appendingPathComponent("s2.jsonl"))

        let stats = TranscriptScanner.scanConcurrency(for: todayDay, rootDirectory: tempDir)
        XCTAssertEqual(stats.peakUserSessions, 2)
        XCTAssertFalse(stats.peakProjectNames.isEmpty, "At least one project name should be captured")
    }
}
