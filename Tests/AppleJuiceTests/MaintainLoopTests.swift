import Testing
import Foundation
@testable import apple_juice

@Suite("MaintainLoop Tests")
struct MaintainLoopTests {

    // MARK: - ChargingDecision tests

    @Test func disableChargingWhenAboveUpperLimit() {
        let action = ChargingDecision.evaluate(
            percentage: 85, chargingEnabled: true,
            upperLimit: 80, lowerLimit: 50)
        #expect(action == .disableCharging)
    }

    @Test func enableChargingWhenBelowLowerLimit() {
        let action = ChargingDecision.evaluate(
            percentage: 48, chargingEnabled: false,
            upperLimit: 80, lowerLimit: 50)
        #expect(action == .enableCharging)
    }

    @Test func noActionBetweenLimits() {
        let action = ChargingDecision.evaluate(
            percentage: 70, chargingEnabled: false,
            upperLimit: 80, lowerLimit: 50)
        #expect(action == .noAction)
    }

    @Test func disableChargingExactlyAtUpperLimit() {
        let action = ChargingDecision.evaluate(
            percentage: 80, chargingEnabled: true,
            upperLimit: 80, lowerLimit: 50)
        #expect(action == .disableCharging)
    }

    @Test func noActionExactlyAtLowerLimitWithChargingDisabled() {
        let action = ChargingDecision.evaluate(
            percentage: 50, chargingEnabled: false,
            upperLimit: 80, lowerLimit: 50)
        #expect(action == .noAction)
    }

    @Test func noActionAboveUpperWithChargingAlreadyDisabled() {
        let action = ChargingDecision.evaluate(
            percentage: 85, chargingEnabled: false,
            upperLimit: 80, lowerLimit: 50)
        #expect(action == .noAction)
    }

    @Test func noActionBelowLowerWithChargingAlreadyEnabled() {
        let action = ChargingDecision.evaluate(
            percentage: 48, chargingEnabled: true,
            upperLimit: 80, lowerLimit: 50)
        #expect(action == .noAction)
    }

    @Test func consecutiveFailureDetection() {
        let mock = MockSMCClient()
        #expect(mock.readDecimal(.BRSC) == nil)
        #expect(getBatteryPercentage(using: mock) == 0)
    }

    // MARK: - SMC control failure detection

    @Test func controlFailureWhenWriteDoesNotTakeEffect() {
        let mock = MockSMCClient()
        mock.keys[.CH0C] = "00"
        mock.keys[.CH0B] = "00"

        let caps = SMCCapabilities(
            hasCH0B: true, hasCH0C: true, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)

        let controller = ChargingController(client: mock, caps: caps)
        controller.disableCharging()

        let stillEnabled = getSMCChargingStatus(using: mock, caps: caps) == "enabled"
        #expect(stillEnabled)
    }

    // MARK: - PID file parsing

    @Test func processHelperPidFileReading() throws {
        let tmpDir = NSTemporaryDirectory() + "apple-juice-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let pidFile = (tmpDir as NSString).appendingPathComponent("test.pid")
        try "12345 active".write(toFile: pidFile, atomically: true, encoding: .utf8)

        #expect(ProcessHelper.readPidFileStatus(pidFile) == "active")
        #expect(ProcessHelper.readPid(pidFile) == 12345)
    }

    @Test func processHelperSuspendedStatus() throws {
        let tmpDir = NSTemporaryDirectory() + "apple-juice-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let pidFile = (tmpDir as NSString).appendingPathComponent("test.pid")
        try "99999 suspended".write(toFile: pidFile, atomically: true, encoding: .utf8)

        #expect(ProcessHelper.readPidFileStatus(pidFile) == "suspended")
        #expect(ProcessHelper.readPid(pidFile) == 99999)
    }
}
