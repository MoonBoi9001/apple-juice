import Testing
import Foundation
@testable import apple_juice

@Suite("Schedule Tests")
struct ScheduleTests {

    // MARK: - getMaintainUpperLimit (config parsing)

    @Test func maintainUpperLimitSingleValue() throws {
        let tmpDir = NSTemporaryDirectory() + "apple-juice-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let config = ConfigStore(folder: tmpDir)
        try config.write("maintain_percentage", value: "80")

        let mp = config.maintainPercentage
        #expect(mp == "80")

        // Verify parsing logic matches getMaintainUpperLimit
        let parts = mp!.split(separator: " ")
        let upper = Int(parts.first ?? "")
        #expect(upper == 80)
    }

    @Test func maintainUpperLimitWithSailingTarget() throws {
        let tmpDir = NSTemporaryDirectory() + "apple-juice-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let config = ConfigStore(folder: tmpDir)
        try config.write("maintain_percentage", value: "65 60")

        let mp = config.maintainPercentage!
        let parts = mp.split(separator: " ")
        let upper = Int(parts.first ?? "")
        let lower = Int(parts[1])
        #expect(upper == 65)
        #expect(lower == 60)
    }

    @Test func maintainUpperLimitMissingConfig() throws {
        let tmpDir = NSTemporaryDirectory() + "apple-juice-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let config = ConfigStore(folder: tmpDir)
        #expect(config.maintainPercentage == nil)
    }

}
