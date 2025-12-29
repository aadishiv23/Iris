//
//  LoggingService.swift
//  Iris
//
//  Created by Claude on 12/28/25.
//

import Foundation
import Observation

/// Centralized logging service with persistent storage and per-conversation logs
@Observable
@MainActor
final class LoggingService {

    // MARK: - Singleton

    static let shared = LoggingService()

    // MARK: - Types

    enum LogLevel: String, Codable, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case fatal = "FATAL"

        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            case .fatal: return "💀"
            }
        }
    }

    struct LogEntry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let level: LogLevel
        let category: String
        let message: String
        let file: String
        let function: String
        let line: Int
        let conversationID: UUID?
        let metadata: [String: String]?

        init(
            level: LogLevel,
            category: String,
            message: String,
            file: String,
            function: String,
            line: Int,
            conversationID: UUID? = nil,
            metadata: [String: String]? = nil
        ) {
            self.id = UUID()
            self.timestamp = Date()
            self.level = level
            self.category = category
            self.message = message
            self.file = file
            self.function = function
            self.line = line
            self.conversationID = conversationID
            self.metadata = metadata
        }

        var formattedTimestamp: String {
            Self.dateFormatter.string(from: timestamp)
        }

        var shortFile: String {
            (file as NSString).lastPathComponent
        }

        var formatted: String {
            var result = "[\(formattedTimestamp)] \(level.emoji) [\(level.rawValue)] [\(category)] \(message)"
            result += "\n    at \(shortFile):\(line) in \(function)"
            if let metadata, !metadata.isEmpty {
                result += "\n    metadata: \(metadata)"
            }
            return result
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()
    }

    // MARK: - Properties

    /// All logs in current session (ring buffer, max 1000 entries)
    private(set) var globalLogs: [LogEntry] = []

    /// Per-conversation logs (keyed by conversation ID)
    private(set) var conversationLogs: [UUID: [LogEntry]] = [:]

    /// Maximum number of global logs to keep in memory
    private let maxGlobalLogs = 1000

    /// Maximum logs per conversation
    private let maxConversationLogs = 500

    /// Directory for persistent logs
    private let logsDirectory: URL?

    /// Current active conversation for automatic association
    var activeConversationID: UUID?

    // MARK: - Init

    private init() {
        // Setup logs directory
        if let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            logsDirectory = documentsDir.appendingPathComponent("Logs", isDirectory: true)
            try? FileManager.default.createDirectory(at: logsDirectory!, withIntermediateDirectories: true)
        } else {
            logsDirectory = nil
        }

        // Load persisted logs from last session
        loadPersistedLogs()

        // Log startup
        log(.info, category: "LoggingService", message: "Logging service initialized")
    }

    // MARK: - Logging Methods

    /// Main logging function
    func log(
        _ level: LogLevel,
        category: String,
        message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        conversationID: UUID? = nil,
        metadata: [String: String]? = nil
    ) {
        let effectiveConversationID = conversationID ?? activeConversationID

        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line,
            conversationID: effectiveConversationID,
            metadata: metadata
        )

        // Add to global logs (ring buffer)
        globalLogs.append(entry)
        if globalLogs.count > maxGlobalLogs {
            globalLogs.removeFirst(globalLogs.count - maxGlobalLogs)
        }

        // Add to conversation logs if applicable
        if let convID = effectiveConversationID {
            if conversationLogs[convID] == nil {
                conversationLogs[convID] = []
            }
            conversationLogs[convID]?.append(entry)

            // Trim conversation logs
            if let count = conversationLogs[convID]?.count, count > maxConversationLogs {
                conversationLogs[convID]?.removeFirst(count - maxConversationLogs)
            }
        }

        // Also print to console for Xcode debugging
        print(entry.formatted)

        // Persist ALL logs (not just errors) so we can debug crashes
        persistLog(entry)
    }

    // MARK: - Convenience Methods

    func debug(_ message: String, category: String = "App", file: String = #file, function: String = #function, line: Int = #line, metadata: [String: String]? = nil) {
        log(.debug, category: category, message: message, file: file, function: function, line: line, metadata: metadata)
    }

    func info(_ message: String, category: String = "App", file: String = #file, function: String = #function, line: Int = #line, metadata: [String: String]? = nil) {
        log(.info, category: category, message: message, file: file, function: function, line: line, metadata: metadata)
    }

    func warning(_ message: String, category: String = "App", file: String = #file, function: String = #function, line: Int = #line, metadata: [String: String]? = nil) {
        log(.warning, category: category, message: message, file: file, function: function, line: line, metadata: metadata)
    }

    func error(_ message: String, category: String = "App", file: String = #file, function: String = #function, line: Int = #line, metadata: [String: String]? = nil) {
        log(.error, category: category, message: message, file: file, function: function, line: line, metadata: metadata)
    }

    func fatal(_ message: String, category: String = "App", file: String = #file, function: String = #function, line: Int = #line, metadata: [String: String]? = nil) {
        log(.fatal, category: category, message: message, file: file, function: function, line: line, metadata: metadata)
    }

    // MARK: - Query Methods

    /// Get logs for a specific conversation
    func logs(for conversationID: UUID) -> [LogEntry] {
        conversationLogs[conversationID] ?? []
    }

    /// Get recent logs filtered by level
    func recentLogs(minLevel: LogLevel = .debug, limit: Int = 100) -> [LogEntry] {
        let levels: [LogLevel] = {
            switch minLevel {
            case .debug: return LogLevel.allCases
            case .info: return [.info, .warning, .error, .fatal]
            case .warning: return [.warning, .error, .fatal]
            case .error: return [.error, .fatal]
            case .fatal: return [.fatal]
            }
        }()

        return globalLogs
            .filter { levels.contains($0.level) }
            .suffix(limit)
            .reversed()
            .map { $0 }
    }

    /// Get all logs as exportable text
    func exportLogs() -> String {
        var output = "=== Iris Debug Logs ===\n"
        output += "Exported: \(Date())\n"
        output += "Total entries: \(globalLogs.count)\n"
        output += "========================\n\n"

        for entry in globalLogs {
            output += entry.formatted + "\n\n"
        }

        return output
    }

    /// Get logs for a conversation as exportable text
    func exportLogs(for conversationID: UUID) -> String {
        let logs = logs(for: conversationID)

        var output = "=== Iris Conversation Logs ===\n"
        output += "Conversation: \(conversationID)\n"
        output += "Exported: \(Date())\n"
        output += "Total entries: \(logs.count)\n"
        output += "==============================\n\n"

        for entry in logs {
            output += entry.formatted + "\n\n"
        }

        return output
    }

    /// Clear all logs
    func clearLogs() {
        globalLogs.removeAll()
        conversationLogs.removeAll()
        clearPersistedLogs()
        log(.info, category: "LoggingService", message: "Logs cleared")
    }

    // MARK: - Persistence

    private func persistLog(_ entry: LogEntry) {
        guard let logsDirectory else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let filename = "iris-\(dateFormatter.string(from: entry.timestamp)).log"
        let fileURL = logsDirectory.appendingPathComponent(filename)

        let logLine = entry.formatted + "\n---\n"

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                defer {
                    try? fileHandle.synchronize() // Force flush to disk
                    try? fileHandle.close()
                }
                try fileHandle.seekToEnd()
                if let data = logLine.data(using: .utf8) {
                    try fileHandle.write(contentsOf: data)
                }
            } else {
                try logLine.write(to: fileURL, atomically: false, encoding: .utf8) // Non-atomic for speed
            }
        } catch {
            // Can't log this error (would cause recursion), just print
            print("[LoggingService] Failed to persist log: \(error)")
        }
    }

    private func loadPersistedLogs() {
        guard let logsDirectory else { return }

        // Load logs from today and yesterday
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let today = dateFormatter.string(from: Date())
        let yesterday = dateFormatter.string(from: Date().addingTimeInterval(-86400))

        for dateStr in [yesterday, today] {
            let filename = "iris-\(dateStr).log"
            let fileURL = logsDirectory.appendingPathComponent(filename)

            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                // Just note that we have persisted logs (don't parse them back into memory)
                print("[LoggingService] Found persisted logs: \(filename) (\(content.count) bytes)")
            }
        }
    }

    private func clearPersistedLogs() {
        guard let logsDirectory else { return }

        if let files = try? FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "log" {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Get list of persisted log files
    func persistedLogFiles() -> [(name: String, url: URL, size: Int64)] {
        guard let logsDirectory else { return [] }

        var files: [(name: String, url: URL, size: Int64)] = []

        if let contents = try? FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in contents where file.pathExtension == "log" {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                files.append((file.lastPathComponent, file, Int64(size)))
            }
        }

        return files.sorted { $0.name > $1.name }
    }
}

// MARK: - Global Convenience

/// Global logger instance for easy access
let Logger = LoggingService.shared

// MARK: - Memory Utilities

extension LoggingService {
    /// Logs current memory usage (useful for debugging memory issues)
    func logMemoryUsage(context: String) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / (1024 * 1024)
            log(.info, category: "Memory", message: "\(context): \(String(format: "%.1f", usedMB)) MB used")
        }
    }
}
