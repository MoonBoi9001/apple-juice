import Testing
import Foundation
@testable import apple_juice

@Suite("ChargingController Tests")
struct ChargingControllerTests {

    // MARK: - Charging (CH0B/CH0C path)

    @Test func enableChargingAppleSilicon() {
        let mock = MockSMCClient()
        let caps = SMCCapabilities(
            hasCH0B: true, hasCH0C: true, hasCH0I: true,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)
        let controller = ChargingController(client: mock, caps: caps)

        controller.enableCharging()

        // Should write CH0B=00, CH0C=00 for enable
        let writes = mock.writeLog
        let ch0bWrite = writes.first { $0.0 == .CH0B }
        let ch0cWrite = writes.first { $0.0 == .CH0C }
        #expect(ch0bWrite?.1 == "00")
        #expect(ch0cWrite?.1 == "00")
    }

    @Test func disableChargingAppleSilicon() {
        let mock = MockSMCClient()
        let caps = SMCCapabilities(
            hasCH0B: true, hasCH0C: true, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)
        let controller = ChargingController(client: mock, caps: caps)

        controller.disableCharging()

        let writes = mock.writeLog
        let ch0bWrite = writes.first { $0.0 == .CH0B }
        let ch0cWrite = writes.first { $0.0 == .CH0C }
        #expect(ch0bWrite?.1 == "02")
        #expect(ch0cWrite?.1 == "02")
    }

    // MARK: - Charging (CHTE-only path)

    @Test func enableChargingCHTEOnly() {
        let mock = MockSMCClient()
        // CHTE-only: hasCHTE=true, hasCH0B=false
        let caps = SMCCapabilities(
            hasCH0B: false, hasCH0C: false, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: true, hasCHIE: false)
        let controller = ChargingController(client: mock, caps: caps)

        controller.enableCharging()

        let chteWrite = mock.writeLog.first { $0.0 == .CHTE }
        #expect(chteWrite?.1 == "00000000")
    }

    @Test func disableChargingCHTEOnly() {
        let mock = MockSMCClient()
        let caps = SMCCapabilities(
            hasCH0B: false, hasCH0C: false, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: true, hasCHIE: false)
        let controller = ChargingController(client: mock, caps: caps)

        controller.disableCharging()

        let chteWrite = mock.writeLog.first { $0.0 == .CHTE }
        #expect(chteWrite?.1 == "01000000")
    }

    // MARK: - Discharging

    @Test func enableDischargingCH0I() {
        let mock = MockSMCClient()
        let caps = SMCCapabilities(
            hasCH0B: true, hasCH0C: true, hasCH0I: true,
            hasCH0J: false, hasCH0K: false, hasACLC: true,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)
        let controller = ChargingController(client: mock, caps: caps)

        controller.enableDischarging()

        let ch0iWrite = mock.writeLog.first { $0.0 == .CH0I }
        #expect(ch0iWrite?.1 == "01")
    }

    @Test func enableDischargingCH0J_CHIE() {
        let mock = MockSMCClient()
        // No CH0I, has CH0J and CHIE
        let caps = SMCCapabilities(
            hasCH0B: true, hasCH0C: true, hasCH0I: false,
            hasCH0J: true, hasCH0K: false, hasACLC: true,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: true)
        let controller = ChargingController(client: mock, caps: caps)

        controller.enableDischarging()

        let ch0jWrite = mock.writeLog.first { $0.0 == .CH0J }
        let chieWrite = mock.writeLog.first { $0.0 == .CHIE }
        #expect(ch0jWrite?.1 == "01")
        #expect(chieWrite?.1 == "08")
    }

    // MARK: - LED

    @Test func ledNoCapabilitiesDoesNothing() {
        let mock = MockSMCClient()
        let caps = SMCCapabilities(
            hasCH0B: false, hasCH0C: false, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)
        let controller = ChargingController(client: mock, caps: caps)

        controller.changeMagSafeLED(.green)
        #expect(mock.writeLog.isEmpty)
    }
}
