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

            guard let handle = (try? FileHandle(forReadingFrom: url)) else {
                AppLog.shared.warning("cannot open \(path)", category: "scan")
                continue
            }
            defer { try? handle.close() }
            do { try handle.seek(toOffset: cursor) } catch { continue }
            let data = handle.readDataToEndOfFile()
            guard !data.isEmpty else { continue }

            // Only consume up to the last newline so partial trailing lines are re-read later.
            guard let lastNL = data.lastIndex(of: 0x0A) else { continue }
            let consumable = data[data.startIndex...lastNL]
            let newCursor = cursor + UInt64(consumable.count)

            // Accumulate candidates keyed by message.id — last occurrence wins within this
            // batch of new bytes, so a streamed response's final (most complete) entry is kept.
            var batchByID: [String: UsageRecord] = [:]
            for lineData in consumable.split(separator: 0x0A, omittingEmptySubsequences: true) {
                if let rec = Self.parseCandidate(Data(lineData)) {
                    batchByID[rec.id] = rec
                }
            }

            // Emit only records not yet seen globally; mark them seen.
            for rec in batchByID.values {
                guard state.seenIDs[rec.id] == nil else { continue }
                state.seenIDs[rec.id] = rec.day
                records.append(rec)
            }

            state.cursors[path] = newCursor
        }

        return Result(records: records, state: state, existingPaths: existingPaths)
    }

    /// Parse one JSONL line into a candidate record without mutating scan state.
    /// Returns nil for non-usage lines (human turns, tool results, etc.).
    static func parseCandidate(_ data: Data) -> UsageRecord? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let usageDict = message["usage"] as? [String: Any],
              let id = message["id"] as? String,
              let ts = obj["timestamp"] as? String,
              let day = DayBucket.localDay(fromISO: ts)
        else { return nil }

        let rawModel = (message["model"] as? String) ?? "unknown"
        let family = ModelNormalizer.family(for: rawModel)
        let usage = parseUsage(usageDict)
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
