//
//  AppLogger.swift
//  MeetingRecorder
//
//  Centralized logging with file output for debugging
//  Logs are stored at ~/Library/Logs/MeetingRecorder/
//

import Foundation
import os.log

/// Log levels for filtering
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    var prefix: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Centralized logger with console and file output
final class AppLogger {
    static let shared = AppLogger()

    private let logQueue = DispatchQueue(label: "com.ambient.logger", qos: .utility)
    private var logFileHandle: FileHandle?
    private let logDirectory: URL
    private let maxLogFileSize: Int64 = 10 * 1024 * 1024  // 10MB
    private let maxLogFiles = 5

    /// Minimum log level to output (can be changed at runtime)
    var minimumLevel: LogLevel = .debug

    /// Whether to also print to console (Xcode output)
    var consoleOutput: Bool = true

    /// Whether file logging is enabled
    var fileLoggingEnabled: Bool = true

    private init() {
        // Create log directory at ~/Library/Logs/MeetingRecorder/
        let logsPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        logDirectory = logsPath.appendingPathComponent("Logs/MeetingRecorder", isDirectory: true)

        setupLogFile()
    }

    deinit {
        logFileHandle?.closeFile()
    }

    // MARK: - Public Logging Methods

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }

    /// Log with a specific category/subsystem
    func log(_ category: String, _ message: String, level: LogLevel = .info) {
        guard level >= minimumLevel else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] [\(level.prefix)] [\(category)] \(message)"

        logQueue.async { [weak self] in
            self?.writeToFile(logLine)
        }

        if consoleOutput {
            print(logLine)
        }
    }

    // MARK: - Private Methods

    private func log(level: LogLevel, message: String, file: String, function: String, line: Int) {
        guard level >= minimumLevel else { return }

        let fileName = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] [\(level.prefix)] [\(fileName):\(line)] \(message)"

        logQueue.async { [weak self] in
            self?.writeToFile(logLine)
        }

        if consoleOutput {
            print(logLine)
        }
    }

    private func setupLogFile() {
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

            let logFileName = "ambient.log"
            let logFilePath = logDirectory.appendingPathComponent(logFileName)

            // Rotate if needed
            rotateLogFilesIfNeeded(currentFile: logFilePath)

            // Create file if it doesn't exist
            if !FileManager.default.fileExists(atPath: logFilePath.path) {
                FileManager.default.createFile(atPath: logFilePath.path, contents: nil)
            }

            logFileHandle = try FileHandle(forWritingTo: logFilePath)
            logFileHandle?.seekToEndOfFile()

            // Write startup marker
            let startupMessage = "\n\n========== Ambient Started at \(Date()) ==========\n"
            if let data = startupMessage.data(using: .utf8) {
                logFileHandle?.write(data)
            }

            print("[AppLogger] Logging to: \(logFilePath.path)")
        } catch {
            print("[AppLogger] Failed to setup log file: \(error)")
        }
    }

    private func writeToFile(_ message: String) {
        guard fileLoggingEnabled, let handle = logFileHandle else { return }

        let line = message + "\n"
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
    }

    private func rotateLogFilesIfNeeded(currentFile: URL) {
        guard FileManager.default.fileExists(atPath: currentFile.path) else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: currentFile.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            if fileSize > maxLogFileSize {
                // Close current handle
                logFileHandle?.closeFile()
                logFileHandle = nil

                // Rotate existing files
                for i in (1..<maxLogFiles).reversed() {
                    let oldPath = logDirectory.appendingPathComponent("ambient.\(i).log")
                    let newPath = logDirectory.appendingPathComponent("ambient.\(i + 1).log")
                    if FileManager.default.fileExists(atPath: oldPath.path) {
                        if i + 1 >= maxLogFiles {
                            try? FileManager.default.removeItem(at: oldPath)
                        } else {
                            try? FileManager.default.moveItem(at: oldPath, to: newPath)
                        }
                    }
                }

                // Move current to .1
                let rotatedPath = logDirectory.appendingPathComponent("ambient.1.log")
                try FileManager.default.moveItem(at: currentFile, to: rotatedPath)

                print("[AppLogger] Rotated log file")
            }
        } catch {
            print("[AppLogger] Log rotation error: \(error)")
        }
    }

    // MARK: - Utility

    /// Get the path to the current log file
    var currentLogPath: URL {
        return logDirectory.appendingPathComponent("ambient.log")
    }

    /// Get all log file paths
    var allLogPaths: [URL] {
        var paths = [currentLogPath]
        for i in 1..<maxLogFiles {
            let path = logDirectory.appendingPathComponent("ambient.\(i).log")
            if FileManager.default.fileExists(atPath: path.path) {
                paths.append(path)
            }
        }
        return paths
    }

    /// Read recent log lines (for displaying in UI)
    func readRecentLogs(lines: Int = 100) -> String {
        guard let data = try? Data(contentsOf: currentLogPath),
              let content = String(data: data, encoding: .utf8) else {
            return "No logs available"
        }

        let allLines = content.components(separatedBy: .newlines)
        let recentLines = allLines.suffix(lines)
        return recentLines.joined(separator: "\n")
    }
}

// MARK: - Convenience Global Functions

/// Quick logging functions for common use
func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    AppLogger.shared.debug(message, file: file, function: function, line: line)
}

func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    AppLogger.shared.info(message, file: file, function: function, line: line)
}

func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    AppLogger.shared.warning(message, file: file, function: function, line: line)
}

func logError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    AppLogger.shared.error(message, file: file, function: function, line: line)
}
