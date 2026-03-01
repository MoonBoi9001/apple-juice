import Testing
import Foundation
@testable import apple_juice

// MARK: - Mock SMC Client

final class MockSMCClient: SMCClientProtocol {
    var keys: [SMCKey: String] = [:]
    var writeLog: [(SMCKey, String)] = []

    func readHex(_ key: SMCKey) -> String? {
        keys[key]
    }

    @discardableResult
    func write(_ key: SMCKey, value: String) -> Bool {
        writeLog.append((key, value))
        return true
    }
}

@Suite("SMC Client Tests")
struct SMCClientTests {

    // MARK: - Hex parsing

    @Test func parseBytesFromSMCOutput() {
        let client = SMCBinaryClient()

        // Standard format: "  CH0B  [ui8 ]  (bytes 02)"
        #expect(client.parseHexFromSMCOutput("  CH0B  [ui8 ]  (bytes 02)") == "02")
        #expect(client.parseHexFromSMCOutput("  CH0C  [ui8 ]  (bytes 00)") == "00")
        #expect(client.parseHexFromSMCOutput("  CHTE  [ui32]  (bytes 01000000)") == "01000000")
    }

    @Test func parseNoDataReturnsNil() {
        let client = SMCBinaryClient()
        #expect(client.parseHexFromSMCOutput("  CH0B  [    ]  no data") == nil)
    }

    @Test func parseErrorReturnsNil() {
        let client = SMCBinaryClient()
        #expect(client.parseHexFromSMCOutput("Error: key not found") == nil)
    }

    @Test func parseEmptyReturnsNil() {
        let client = SMCBinaryClient()
        #expect(client.parseHexFromSMCOutput("") == nil)
    }

    // MARK: - Key availability

    @Test func keyAvailableWhenDataPresent() {
        let mock = MockSMCClient()
        mock.keys[.CH0B] = "02"
        #expect(mock.keyAvailable(.CH0B) == true)
    }

    @Test func keyUnavailableWhenMissing() {
        let mock = MockSMCClient()
        #expect(mock.keyAvailable(.CH0B) == false)
    }

    // MARK: - Decimal reading

    @Test func readDecimalConvertsHex() {
        let mock = MockSMCClient()
        mock.keys[.CH0B] = "02"
        #expect(mock.readDecimal(.CH0B) == 2)

        mock.keys[.BRSC] = "32"
        #expect(mock.readDecimal(.BRSC) == 50)
    }

    @Test func readDecimalReturnsNilForMissingKey() {
        let mock = MockSMCClient()
        #expect(mock.readDecimal(.BRSC) == nil)
    }

    // MARK: - Capabilities

    @Test func capabilitiesDetectsAppleSilicon() {
        let mock = MockSMCClient()
        mock.keys[.CH0B] = "00"
        mock.keys[.CH0C] = "00"
        let caps = SMCCapabilities.probe(using: mock)
        #expect(caps.hasCH0B == true)
        #expect(caps.hasCH0C == true)
    }

    @Test func capabilitiesDetectsCHTEAppleSilicon() {
        let mock = MockSMCClient()
        mock.keys[.CHTE] = "00000000"
        let caps = SMCCapabilities.probe(using: mock)
        #expect(caps.hasCHTE == true)
    }
}

@Suite("Charging Status Tests")
struct ChargingStatusTests {

    @Test func chargingStateFromSMC() {
        let mock = MockSMCClient()

        // Not charging: CHBI=0, B0AC=0
        mock.keys[.CHBI] = "00"
        mock.keys[.B0AC] = "00"
        #expect(getChargingState(using: mock) == .notCharging)

        // Charging: CHBI>0
        mock.keys[.CHBI] = "0a"
        mock.keys[.B0AC] = "00"
        #expect(getChargingState(using: mock) == .charging)

        // Discharging: CHBI=0, B0AC>0
        mock.keys[.CHBI] = "00"
        mock.keys[.B0AC] = "05"
        #expect(getChargingState(using: mock) == .discharging)
    }

    @Test func smcChargingStatusAppleSilicon() {
        let mock = MockSMCClient()
        mock.keys[.CH0C] = "00"
        let caps = SMCCapabilities(
            hasCH0B: true, hasCH0C: true, hasCH0I: false,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)
        #expect(getSMCChargingStatus(using: mock, caps: caps) == "enabled")

        mock.keys[.CH0C] = "02"
        #expect(getSMCChargingStatus(using: mock, caps: caps) == "disabled")
    }

    @Test func smcDischargingStatusAppleSilicon() {
        let mock = MockSMCClient()
        mock.keys[.CH0I] = "00"
        let caps = SMCCapabilities(
            hasCH0B: true, hasCH0C: true, hasCH0I: true,
            hasCH0J: false, hasCH0K: false, hasACLC: false,
            hasCHWA: false, hasACFP: false, hasCHTE: false, hasCHIE: false)
        #expect(getSMCDischargingStatus(using: mock, caps: caps) == "not discharging")

        mock.keys[.CH0I] = "01"
        #expect(getSMCDischargingStatus(using: mock, caps: caps) == "discharging")
    }
}
