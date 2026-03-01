import Testing
import Foundation
@testable import apple_juice

@Suite("BatteryInfo Tests")
struct BatteryInfoTests {

    // MARK: - getBatteryPercentage (SMC-based)

    @Test func batteryPercentageNormalValue() {
        let mock = MockSMCClient()
        mock.keys[.BRSC] = "32"  // 0x32 = 50 decimal
        #expect(getBatteryPercentage(using: mock) == 50)
    }

    @Test func batteryPercentageHighByteEncoding() {
        // Some SMC firmware returns percentage * 256 in BRSC
        let mock = MockSMCClient()
        mock.keys[.BRSC] = "5000"  // 0x5000 = 20480, /256 = 80
        #expect(getBatteryPercentage(using: mock) == 80)
    }

    @Test func batteryPercentageReturnsZeroOnMissingKey() {
        let mock = MockSMCClient()
        #expect(getBatteryPercentage(using: mock) == 0)
    }

    @Test func batteryPercentageExactly100() {
        let mock = MockSMCClient()
        mock.keys[.BRSC] = "64"  // 0x64 = 100
        #expect(getBatteryPercentage(using: mock) == 100)
    }

    // MARK: - getSMCChargingStatus paths

    @Test func chargingStatusViaCH0C() {
        let mock = MockSMCClient()
        let caps = SMCCapabilities(
            hasCH0B: true, hasCH0C: true, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)

        mock.keys[.CH0C] = "00"
        #expect(getSMCChargingStatus(using: mock, caps: caps) == "enabled")

        mock.keys[.CH0C] = "02"
        #expect(getSMCChargingStatus(using: mock, caps: caps) == "disabled")
    }

    @Test func chargingStatusViaCHTE() {
        let mock = MockSMCClient()
        let caps = SMCCapabilities(
            hasCH0B: false, hasCH0C: false, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: true, hasCHIE: false)

        mock.keys[.CHTE] = "00000000"
        #expect(getSMCChargingStatus(using: mock, caps: caps) == "enabled")

        mock.keys[.CHTE] = "01000000"
        #expect(getSMCChargingStatus(using: mock, caps: caps) == "disabled")
    }

    @Test func chargingStatusFallbackWhenNoKeys() {
        let mock = MockSMCClient()
        let caps = SMCCapabilities(
            hasCH0B: false, hasCH0C: false, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)
        #expect(getSMCChargingStatus(using: mock, caps: caps) == "enabled")
    }

    // MARK: - getSMCDischargingStatus paths

    @Test func dischargingStatusViaCH0J() {
        let mock = MockSMCClient()
        let caps = SMCCapabilities(
            hasCH0B: false, hasCH0C: false, hasCH0I: false,
            hasCH0J: true, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)

        mock.keys[.CH0J] = "00"
        #expect(getSMCDischargingStatus(using: mock, caps: caps) == "not discharging")

        mock.keys[.CH0J] = "01"
        #expect(getSMCDischargingStatus(using: mock, caps: caps) == "discharging")
    }

    @Test func dischargingStatusViaCHIE() {
        let mock = MockSMCClient()
        let caps = SMCCapabilities(
            hasCH0B: false, hasCH0C: false, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: true)

        mock.keys[.CHIE] = "00"
        #expect(getSMCDischargingStatus(using: mock, caps: caps) == "not discharging")

        mock.keys[.CHIE] = "08"
        #expect(getSMCDischargingStatus(using: mock, caps: caps) == "discharging")
    }

    @Test func dischargingStatusFallbackWhenNoKeys() {
        let mock = MockSMCClient()
        let caps = SMCCapabilities(
            hasCH0B: false, hasCH0C: false, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)
        #expect(getSMCDischargingStatus(using: mock, caps: caps) == "not discharging")
    }

    // MARK: - ChargingState enum

    @Test func chargingStateDescription() {
        #expect(ChargingState.notCharging.description == "no charging")
        #expect(ChargingState.charging.description == "charging")
        #expect(ChargingState.discharging.description == "discharging")
    }
}
