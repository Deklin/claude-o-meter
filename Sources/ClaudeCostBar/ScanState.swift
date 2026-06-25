import Foundation

/// Persisted state that makes scanning incremental and dedup global.
struct ScanState: Codable, Sendable {
    /// Absolute file path -> byte offset already consumed (up to the last complete line).
    var cursors: [String: UInt64] = [:]
    /// message.id -> local day first seen. Used to dedup across resumed/compacted sessions.
    var seenIDs: [String: String] = [:]

    /// Drop cursors for files that no longer exist and seen-ids older than the cutoff,
    /// so state does not grow without bound.
    mutating func prune(existingPaths: Set<String>, retainSeenIDsOnOrAfter cutoffDay: String) {
        cursors = cursors.filter { existingPaths.contains($0.key) }
        seenIDs = seenIDs.filter { $0.value >= cutoffDay }
    }
}
