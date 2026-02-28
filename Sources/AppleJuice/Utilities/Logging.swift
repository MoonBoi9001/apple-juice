import Foundation
import os.log

private let osLogger = Logger(subsystem: "com.apple-juice.app", category: "general")

/// Maximum log file size in bytes before rotation (5 MB).
private let maxLogSizeBytes: UInt64 = 5_000_000

/// Number of lines to keep after rotation.
private let rotationKeepLines = 100

// MARK: - Date formatters

/// Format: MM/DD/YY-HH:MM:SS (matches bash `date +%D-%T`)
private let timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MM/dd/yy-HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

/// Format: YYYY/MM/DD (matches bash `date +%Y/%m/%d`)
private let dateOnlyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy/MM/dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

/// Serial queue protecting DateFormatter access and log file writes.
private let logQueue = DispatchQueue(label: "com.apple-juice.logging")

// MARK: - Public logging functions

/// Log with timestamp and newline. Matches bash `log()`.
/// Output: "MM/DD/YY-HH:MM:SS - message\n"
func log(_ message: String) {
    logQueue.sync {
        let line = "\(timestampFormatter.string(from: Date())) - \(message)"
        print(line)
        osLogger.info("\(message)")
        appendToLogFile(line + "\n")
    }
}

/// Log with leading newline + timestamp. Matches bash `logLF()`.
/// Output: "\nMM/DD/YY-HH:MM:SS - message\n"
func logLF(_ message: String) {
    logQueue.sync {
        let line = "\(timestampFormatter.string(from: Date())) - \(message)"
        print("\n\(line)")
        osLogger.info("\(message)")
        appendToLogFile("\n" + line + "\n")
    }
}

/// Log with timestamp, no trailing newline. Matches bash `logn()`.
/// Output: "MM/DD/YY-HH:MM:SS - message" (no newline)
func logn(_ message: String) {
    logQueue.sync {
        let line = "\(timestampFormatter.string(from: Date())) - \(message)"
        print(line, terminator: "")
        osLogger.info("\(message)")
        appendToLogFile(line)
    }
}

/// Log with date only. Matches bash `logd()`.
/// Output: "YYYY/MM/DD message\n"
func logd(_ message: String) {
    logQueue.sync {
        let line = "\(dateOnlyFormatter.string(from: Date())) \(message)"
        print(line)
        osLogger.info("\(message)")
        appendToLogFile(line + "\n")
    }
}

// MARK: - File logging

/// Append a string to the log file, rotating if necessary.
func appendToLogFile(_ text: String) {
    let path = Paths.logFile
    let fm = FileManager.default

    // Create the file if it doesn't exist
    if !fm.fileExists(atPath: path) {
        try? fm.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        fm.createFile(atPath: path, contents: nil)
    }

    // Rotate if too large
    rotateLogFileIfNeeded(path: path)

    // Append
    guard let handle = FileHandle(forWritingAtPath: path) else { return }
    defer { handle.closeFile() }
    handle.seekToEndOfFile()
    if let data = text.data(using: .utf8) {
        handle.write(data)
    }
}

/// Rotate the log file: keep the last N lines if size exceeds threshold.
func rotateLogFileIfNeeded(path: String) {
    let fm = FileManager.default
    guard let attrs = try? fm.attributesOfItem(atPath: path),
          let size = attrs[.size] as? UInt64,
          size > maxLogSizeBytes
    else { return }

    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }
    let lines = contents.components(separatedBy: "\n")
    let kept = lines.suffix(rotationKeepLines).joined(separator: "\n")
    try? kept.write(toFile: path, atomically: true, encoding: .utf8)
}
