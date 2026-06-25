import Foundation

/// Reads Claude Code transcripts incrementally and emits deduplicated usage records.
///
/// Files are append-only within a session, so we track a per-file byte cursor and only
/// parse newly appended bytes. We never advance past the last newline, so a line still
/// being written mid-scan is re-read (whole) on the next pass.
struct TranscriptScanner {
    let rootDirectory: URL

    init(rootDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)) {
        self.rootDirectory = rootDirectory
    }

    struct Result: Sendable {
        var records: [UsageRecord]
        var state: ScanState
        var existingPaths: Set<String>
    }

    /// Scan all transcripts, mutating `state` cursors/seen-ids and returning new records.
    func scan(state inputState: ScanState) -> Result {
        var state = inputState
        var records: [UsageRecord] = []

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return Result(records: [], state: state, existingPaths: [])
        }

        var existingPaths = Set<String>()

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let path = url.path
            existingPaths.insert(path)

            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            let fileSize = UInt64(size)
            var cursor = state.cursors[path] ?? 0

            // File truncated/rotated -> re-read from start.
            if fileSize < cursor { cursor = 0 }
            if fileSize == cursor { continue }

            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            do { try handle.seek(toOffset: cursor) } catch { continue }
            let data = handle.readDataToEndOfFile()
            guard !data.isEmpty else { continue }

            // Only consume up to the last newline so partial trailing lines are re-read later.
            guard let lastNL = data.lastIndex(of: 0x0A) else { continue }
            let consumable = data[data.startIndex...lastNL]
            let newCursor = cursor + UInt64(consumable.count)

            for lineData in consumable.split(separator: 0x0A, omittingEmptySubsequences: true) {
                if let rec = Self.parseLine(Data(lineData), state: &state) {
                    records.append(rec)
                }
            }
            state.cursors[path] = newCursor
        }

        return Result(records: records, state: state, existingPaths: existingPaths)
    }

    /// Parse one JSONL line; returns a record only for new (unseen) assistant usage messages.
    static func parseLine(_ data: Data, state: inout ScanState) -> UsageRecord? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let usageDict = message["usage"] as? [String: Any],
              let id = message["id"] as? String
        else { return nil }

        // Global dedup: a message.id is counted exactly once (first occurrence wins).
        guard state.seenIDs[id] == nil else { return nil }

        guard let ts = obj["timestamp"] as? String,
              let day = DayBucket.localDay(fromISO: ts)
        else { return nil }

        let rawModel = (message["model"] as? String) ?? "unknown"
        let family = ModelNormalizer.family(for: rawModel)

        let usage = parseUsage(usageDict)
        state.seenIDs[id] = day
        return UsageRecord(id: id, day: day, model: family, rawModel: rawModel, usage: usage)
    }

    static func parseUsage(_ u: [String: Any]) -> TokenUsage {
        func intVal(_ key: String, in dict: [String: Any]) -> Int {
            if let n = dict[key] as? Int { return n }
            if let n = dict[key] as? Double { return Int(n) }
            if let n = dict[key] as? NSNumber { return n.intValue }
            return 0
        }

        let input = intVal("input_tokens", in: u)
        let output = intVal("output_tokens", in: u)
        let cacheRead = intVal("cache_read_input_tokens", in: u)
        let cacheCreationTotal = intVal("cache_creation_input_tokens", in: u)

        var write5m = cacheCreationTotal
        var write1h = 0
        if let breakdown = u["cache_creation"] as? [String: Any] {
            let b5 = intVal("ephemeral_5m_input_tokens", in: breakdown)
            let b1 = intVal("ephemeral_1h_input_tokens", in: breakdown)
            if b5 + b1 > 0 {
                write5m = b5
                write1h = b1
            }
        }

        return TokenUsage(
            input: input,
            output: output,
            cacheRead: cacheRead,
            cacheWrite5m: write5m,
            cacheWrite1h: write1h
        )
    }
}
