import OSLog
import Foundation
import AppKit

/// Unified logger for the app. Wraps Swift's Logger (unified logging) and maintains
/// an in-memory ring buffer so users can copy diagnostics for bug reports.
final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let category: String
        let message: String

        enum Level: String, Sendable {
            case info    = "INFO"
            case warning = "WARN"
            case error   = "ERROR"
        }
    }

    private let subsystem = "com.claudeometer.app"
    private let maxEntries = 200
    private var entries: [Entry] = []
    private let lock = NSLock()

    // One Logger per category for Console.app filtering
    private lazy var loggers: [String: Logger] = {
        ["scan", "pricing", "persistence", "alerts", "updates", "app"]
            .reduce(into: [:]) { $0[$1] = Logger(subsystem: subsystem, category: $1) }
    }()

    private init() {}

    func info(_ message: String, category: String = "app") {
        emit(message, level: .info, category: category)
    }

    func warning(_ message: String, category: String = "app") {
        emit(message, level: .warning, category: category)
    }

    func error(_ message: String, category: String = "app") {
        emit(message, level: .error, category: category)
    }

    private func emit(_ message: String, level: Entry.Level, category: String) {
        let logger = loggers[category] ?? loggers["app"]!
        switch level {
        case .info:    logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error:   logger.error("\(message, privacy: .public)")
        }

        let entry = Entry(timestamp: Date(), level: level, category: category, message: message)
        lock.withLock {
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
        }
    }

    /// Formatted log report for clipboard / GitHub issue. Includes app version and OS.
    func copyToPasteboard() {
        let version  = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let osVer    = ProcessInfo.processInfo.operatingSystemVersionString
        let captured = ISO8601DateFormatter().string(from: Date())

        let header = """
        Claude-o-Meter v\(version)
        macOS \(osVer)
        Captured: \(captured)
        ────────────────────────────────────────────
        """

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"

        let lines: String = lock.withLock {
            entries.isEmpty
                ? "(no log entries)"
                : entries.map { "[\(fmt.string(from: $0.timestamp))] [\($0.level.rawValue)] [\($0.category)] \($0.message)" }
                         .joined(separator: "\n")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(header + "\n" + lines, forType: .string)
    }
}
