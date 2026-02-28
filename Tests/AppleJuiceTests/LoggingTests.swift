import Testing
import Foundation
@testable import apple_juice

@Suite("Logging Tests")
struct LoggingTests {

    // MARK: - Log rotation

    @Test func rotateLogFileWhenUnderLimit() throws {
        let tempFile = NSTemporaryDirectory() + "apple-juice-logtest-\(UUID().uuidString).log"

        let smallContent = String(repeating: "line\n", count: 10)
        try smallContent.write(toFile: tempFile, atomically: true, encoding: .utf8)

        rotateLogFileIfNeeded(path: tempFile)

        let after = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(after == smallContent, "File under limit should not be rotated")

        try? FileManager.default.removeItem(atPath: tempFile)
    }

    @Test func rotateLogFileWhenOverLimit() throws {
        let tempFile = NSTemporaryDirectory() + "apple-juice-logtest-\(UUID().uuidString).log"

        // Create a file exceeding 5MB
        var lines: [String] = []
        let lineContent = String(repeating: "X", count: 100)
        for i in 0..<55000 {
            lines.append("line \(i): \(lineContent)")
        }
        let bigContent = lines.joined(separator: "\n")
        try bigContent.write(toFile: tempFile, atomically: true, encoding: .utf8)

        rotateLogFileIfNeeded(path: tempFile)

        let after = try String(contentsOfFile: tempFile, encoding: .utf8)
        let afterLines = after.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(afterLines.count <= 100, "Rotated file should have at most 100 lines")

        try? FileManager.default.removeItem(atPath: tempFile)
    }

    // MARK: - Timestamp format

    @Test func timestampFormat() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy-HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let date = formatter.date(from: "02/27/26-14:30:45")
        #expect(date != nil, "Formatter should parse MM/DD/YY-HH:MM:SS format")

        if let date {
            let output = formatter.string(from: date)
            #expect(output == "02/27/26-14:30:45")
        }
    }

    @Test func dateOnlyFormat() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let date = formatter.date(from: "2026/02/27")
        #expect(date != nil)

        if let date {
            let output = formatter.string(from: date)
            #expect(output == "2026/02/27")
        }
    }
}
