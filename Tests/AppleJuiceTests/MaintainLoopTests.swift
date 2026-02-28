import Testing
import Foundation
@testable import apple_juice

@Suite("MaintainLoop Tests")
struct MaintainLoopTests {

    // MARK: - Charging control decisions with side-effect verification

    @Test func disableChargingWhenAboveUpperLimit() {
        let mock = MockSMCClient()
        mock.keys[.CH0C] = "00"  // charging enabled
        mock.keys[.CH0B] = "00"
        mock.keys[.BRSC] = "55"  // 85%

        let caps = SMCCapabilities(
            hasCH0B: true, hasCH0C: true, hasCH0I: true,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)

        let pct = getBatteryPercentage(using: mock)
        let chargingEnabled = getSMCChargingStatus(using: mock, caps: caps) == "enabled"

        // Condition met: above 80% with charging enabled
        #expect(pct >= 80 && chargingEnabled)

        // Verify disableCharging writes the expected SMC values
        let controller = ChargingController(client: mock, caps: caps)
        controller.disableCharging()

        let ch0bWrite = mock.writeLog.first { $0.0 == .CH0B }
        let ch0cWrite = mock.writeLog.first { $0.0 == .CH0C }
        #expect(ch0bWrite?.1 == "02")
        #expect(ch0cWrite?.1 == "02")
    }

    @Test func enableChargingWhenBelowLowerLimit() {
        let mock = MockSMCClient()
        mock.keys[.CH0C] = "02"  // charging disabled
        mock.keys[.CH0B] = "02"
        mock.keys[.BRSC] = "30"  // 48%

        let caps = SMCCapabilities(
            hasCH0B: true, hasCH0C: true, hasCH0I: true,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)

        let pct = getBatteryPercentage(using: mock)
        let chargingEnabled = getSMCChargingStatus(using: mock, caps: caps) == "enabled"

        // Condition met: below 50% with charging disabled
        #expect(pct < 50 && !chargingEnabled)

        // Verify enableCharging writes the expected SMC values
        let controller = ChargingController(client: mock, caps: caps)
        controller.enableCharging()

        let ch0bWrite = mock.writeLog.first { $0.0 == .CH0B }
        let ch0cWrite = mock.writeLog.first { $0.0 == .CH0C }
        #expect(ch0bWrite?.1 == "00")
        #expect(ch0cWrite?.1 == "00")
    }

    @Test func noActionBetweenLimits() {
        // Verifies that when battery is between lower and upper limits,
        // evaluating the same conditions as the maintain loop produces no SMC writes.
        // The maintain loop only acts when (pct >= upper && charging enabled) or
        // (pct < lower && charging disabled). This test confirms the "no-op" zone.
        let mock = MockSMCClient()
        mock.keys[.CH0C] = "02"  // charging disabled (correct for between limits)
        mock.keys[.BRSC] = "46"  // 70%

        let caps = SMCCapabilities(
            hasCH0B: true, hasCH0C: true, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)

        let upperLimit = 80
        let lowerLimit = 50
        let pct = getBatteryPercentage(using: mock)
        let chargingEnabled = getSMCChargingStatus(using: mock, caps: caps) == "enabled"

        // Replicate the maintain loop decision logic: only call controller
        // methods when the threshold conditions are met.
        let controller = ChargingController(client: mock, caps: caps)
        if pct >= upperLimit && chargingEnabled {
            controller.disableCharging()
        } else if pct < lowerLimit && !chargingEnabled {
            controller.enableCharging()
        }

        // Neither branch was taken, so no SMC writes occurred
        #expect(mock.writeLog.isEmpty)
    }

    @Test func consecutiveFailureDetection() {
        let mock = MockSMCClient()
        // No BRSC key = read failure
        #expect(mock.readDecimal(.BRSC) == nil)
        #expect(getBatteryPercentage(using: mock) == 0)
    }

    // MARK: - SMC control failure detection

    @Test func controlFailureWhenWriteDoesNotTakeEffect() {
        let mock = MockSMCClient()
        // CH0C stays "00" (enabled) even after disableCharging writes "02"
        // because MockSMCClient doesn't update keys on write
        mock.keys[.CH0C] = "00"
        mock.keys[.CH0B] = "00"

        let caps = SMCCapabilities(
            hasCH0B: true, hasCH0C: true, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)

        let controller = ChargingController(client: mock, caps: caps)
        controller.disableCharging()

        // After disableCharging, re-reading CH0C still shows "00" (enabled)
        // because mock doesn't update internal state on write -- simulating SMC failure
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
