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
}
