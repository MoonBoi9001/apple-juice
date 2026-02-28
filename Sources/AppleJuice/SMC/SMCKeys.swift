import Foundation

/// All SMC keys used by apple-juice, with availability flags.
/// Apple Silicon only -- Intel Macs are not supported.
enum SMCKey: String, CaseIterable {
    case CH0B  // Charge inhibit
    case CH0C  // Charge inhibit secondary
    case CH0I  // Discharge force
    case CH0J  // Discharge force secondary
    case CH0K  // Discharge force tertiary
    case ACLC  // MagSafe LED control
    case CHWA  // Charge wake
    case ACFP  // AC adapter force present
    case CHTE  // Charge termination enable (newer Apple Silicon)
    case CHIE  // Charge/discharge inhibit enable (newer Apple Silicon)

    // Read-only monitoring keys
    case BRSC  // Battery relative state of charge
    case CHBI  // Charge current (battery input)
    case B0AC  // Discharge current (battery output)
}

/// SMC key write values used by charging/discharging operations.
enum SMCWriteValue {
    // Charging enable
    static let CH0B_enable = "00"
    static let CH0B_disable = "02"
    static let CH0C_enable = "00"
    static let CH0C_disable = "02"
    static let CHTE_enable = "00000000"
    static let CHTE_disable = "01000000"

    // Discharging enable
    static let CH0I_enable = "01"
    static let CH0I_disable = "00"
    static let CH0J_enable = "01"
    static let CH0J_disable = "00"
    static let CH0K_enable = "01"
    static let CH0K_disable = "00"
    static let CHIE_enable = "08"
    static let CHIE_disable = "00"
    static let ACLC_discharge = "01"

    // MagSafe LED (ACLC)
    static let ACLC_green = "03"
    static let ACLC_orange = "04"
    static let ACLC_none = "01"
    static let ACLC_off = "00"

    // CHWA (charge wake)
    static let CHWA_enable = "01"
    static let CHWA_disable = "00"
}

/// Detected SMC key availability on this machine.
/// Probed at startup by reading each key and checking for "no data" response.
struct SMCCapabilities {
    let hasCH0B: Bool
    let hasCH0C: Bool
    let hasCH0I: Bool
    let hasCH0J: Bool
    let hasCH0K: Bool
    let hasACLC: Bool
    let hasCHWA: Bool
    let hasACFP: Bool
    let hasCHTE: Bool
    let hasCHIE: Bool

    /// Probe all keys by reading via the smc binary.
    static func probe(using client: SMCClientProtocol) -> SMCCapabilities {
        SMCCapabilities(
            hasCH0B: client.keyAvailable(.CH0B),
            hasCH0C: client.keyAvailable(.CH0C),
            hasCH0I: client.keyAvailable(.CH0I),
            hasCH0J: client.keyAvailable(.CH0J),
            hasCH0K: client.keyAvailable(.CH0K),
            hasACLC: client.keyAvailable(.ACLC),
            hasCHWA: client.keyAvailable(.CHWA),
            hasACFP: client.keyAvailable(.ACFP),
            hasCHTE: client.keyAvailable(.CHTE),
            hasCHIE: client.keyAvailable(.CHIE)
        )
    }
}
