import Foundation
import IOKit

/// Reads battery information from IOKit's AppleSmartBattery service.
/// Replaces all `ioreg | grep | awk` chains with a single API call.
struct BatteryInfo {
    /// All properties from the AppleSmartBattery IOKit service.
    private let properties: NSDictionary?

    init() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        defer {
            if service != IO_OBJECT_NULL {
                IOObjectRelease(service)
            }
        }

        guard service != IO_OBJECT_NULL else {
            self.properties = nil
            return
        }

        var props: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
        if result == kIOReturnSuccess {
            self.properties = props?.takeRetainedValue() as NSDictionary?
        } else {
            self.properties = nil
        }
    }

    // MARK: - Raw properties

    private func intProperty(_ key: String) -> Int? {
        properties?[key] as? Int
    }

    private func arrayProperty(_ key: String) -> [Int]? {
        properties?[key] as? [Int]
    }

    // MARK: - Capacity

    var rawMaxCapacity: Int? { intProperty("AppleRawMaxCapacity") }
    var rawCurrentCapacity: Int? { intProperty("AppleRawCurrentCapacity") }
    var designCapacity: Int? { intProperty("DesignCapacity") }

    /// macOS-reported capacity (smoothed/adjusted by the battery controller).
    var currentCapacity: Int? { intProperty("CurrentCapacity") }
    var maxCapacity: Int? { intProperty("MaxCapacity") }

    /// macOS battery percentage (what the menu bar shows).
    var macOSPercentage: Int? {
        guard let max = maxCapacity, let current = currentCapacity, max > 0 else {
            return nil
        }
        return current * 100 / max
    }

    /// Raw battery percentage: AppleRawCurrentCapacity / AppleRawMaxCapacity * 100.
    var accuratePercentage: String {
        guard let max = rawMaxCapacity, let current = rawCurrentCapacity, max > 0 else {
            return "0"
        }
        let pct = Double(current) * 100.0 / Double(max)
        return String(format: "%.1f", pct)
    }

    // MARK: - Voltage

    /// Battery voltage in millivolts.
    var voltageMillivolts: Int? { intProperty("Voltage") }

    /// Battery voltage in volts (e.g., "12.345").
    /// Matches bash `get_voltage()` which does $3/1000.
    var voltage: String {
        guard let mv = voltageMillivolts else { return "0" }
        return String(format: "%.3f", Double(mv) / 1000.0)
    }

    // MARK: - Temperature

    /// Virtual temperature in hundredths of a degree.
    var virtualTemperature: Int? { intProperty("VirtualTemperature") }

    /// Battery temperature in Celsius, one decimal place.
    /// Matches bash: `scale=1; ($temperature+5)/100`
    var temperature: String {
        guard let vt = virtualTemperature else { return "0" }
        let temp = Double(vt + 5) / 100.0
        return String(format: "%.1f", temp)
    }

    // MARK: - Charge estimation

    /// Average time to full charge in minutes. Returns nil if not charging (65535 sentinel).
    var avgTimeToFull: Int? {
        guard let val = intProperty("AvgTimeToFull"), val != 65535 else { return nil }
        return val
    }

    /// Average time to empty in minutes. Returns nil if not discharging (65535 sentinel).
    var avgTimeToEmpty: Int? {
        guard let val = intProperty("AvgTimeToEmpty"), val != 65535 else { return nil }
        return val
    }

    /// Instantaneous current in mA (signed: positive = charging, negative = discharging).
    var instantAmperage: Int? { intProperty("InstantAmperage") }

    /// Whether the battery is fully charged.
    var fullyCharged: Bool { (properties?["FullyCharged"] as? Bool) == true }

    /// Whether the battery is currently charging (IOKit perspective).
    var isCharging: Bool { (properties?["IsCharging"] as? Bool) == true }

    // MARK: - Adapter details

    /// Adapter details dictionary from IOKit.
    private var adapterDetails: NSDictionary? {
        properties?["AdapterDetails"] as? NSDictionary
    }

    /// Adapter wattage (e.g. 100W).
    var adapterWatts: Int? { adapterDetails?["Watts"] as? Int }

    /// Adapter input voltage in mV (e.g. 20000 = 20V).
    var adapterVoltage: Int? { adapterDetails?["AdapterVoltage"] as? Int }

    /// Adapter current in mA (e.g. 4990 = ~5A).
    var adapterCurrent: Int? { adapterDetails?["Current"] as? Int }

    /// Adapter description string (e.g. "pd charger").
    var adapterDescription: String? { adapterDetails?["Description"] as? String }

    // MARK: - Cycle count

    var cycleCount: Int? { intProperty("CycleCount") }

    var cycleCountString: String {
        guard let c = cycleCount else { return "0" }
        return String(c)
    }

    // MARK: - Cell voltages

    /// The BatteryData sub-dictionary containing cell-level information.
    private var batteryData: NSDictionary? {
        properties?["BatteryData"] as? NSDictionary
    }

    /// Individual cell voltages in mV (nested inside BatteryData).
    var cellVoltages: [Int]? { batteryData?["CellVoltage"] as? [Int] }

    /// Cell voltage imbalance (max - min) in mV.
    var cellImbalance: Int? {
        guard let cells = cellVoltages, !cells.isEmpty else { return nil }
        guard let min = cells.min(), let max = cells.max() else { return nil }
        return max - min
    }

    // MARK: - Clamshell

    /// Whether the MacBook lid is closed. Queries IOPMrootDomain (not AppleSmartBattery)
    /// because AppleClamshellState lives on the root power domain.
    static var isLidClosed: Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as NSDictionary? else { return false }
        return (dict["AppleClamshellState"] as? Bool) == true
    }

    // MARK: - Battery health

    /// Battery health percentage: MaxCapacity / DesignCapacity * 100.
    var healthPercentage: String {
        guard let max = rawMaxCapacity, let design = designCapacity, design > 0 else {
            return "0"
        }
        let health = Double(max) * 100.0 / Double(design)
        return String(format: "%.1f", health)
    }

    // MARK: - pmset-based queries

    /// Remaining time from `pmset -g batt`.
    static var remainingTime: String {
        let result = ProcessRunner.shell("pmset -g batt | tail -n1 | awk '{print $5}'")
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether AC power is connected (from pmset).
    static var isACPower: Bool {
        let result = ProcessRunner.shell("pmset -g batt | head -n1")
        return result.stdout.contains("AC Power")
    }

    /// Whether the charger reports AC attached (from pmset second line).
    static var isChargerAttached: Bool {
        let result = ProcessRunner.shell("pmset -g batt | tail -n1")
        return result.stdout.contains("AC attached")
    }
}

// MARK: - Charging status (uses SMC)

/// Charging status derived from SMC current readings.
enum ChargingState: Int {
    case notCharging = 0
    case charging = 1
    case discharging = 2

    var description: String {
        switch self {
        case .notCharging: return "no charging"
        case .charging: return "charging"
        case .discharging: return "discharging"
        }
    }
}

/// Get current charging state from SMC (CHBI for charge current, B0AC for discharge current).
func getChargingState(using client: SMCClientProtocol) -> ChargingState {
    let chargeCurrent = client.readDecimal(.CHBI) ?? 0
    let dischargeCurrent = client.readDecimal(.B0AC) ?? 0

    if chargeCurrent != 0 {
        return .charging
    } else if dischargeCurrent != 0 {
        return .discharging
    } else {
        return .notCharging
    }
}

/// Get SMC charging status string ("enabled" or "disabled").
func getSMCChargingStatus(using client: SMCClientProtocol, caps: SMCCapabilities) -> String {
    if caps.hasCH0C {
        let hex = client.readHex(.CH0C) ?? ""
        return hex == "00" ? "enabled" : "disabled"
    } else if caps.hasCHTE {
        let hex = client.readHex(.CHTE) ?? ""
        return hex == "00000000" ? "enabled" : "disabled"
    }
    return "enabled"
}

/// Get SMC discharging status string ("discharging" or "not discharging").
func getSMCDischargingStatus(using client: SMCClientProtocol, caps: SMCCapabilities) -> String {
    if caps.hasCH0I {
        return (client.readHex(.CH0I) ?? "00") == "00" ? "not discharging" : "discharging"
    } else if caps.hasCH0J {
        return (client.readHex(.CH0J) ?? "00") == "00" ? "not discharging" : "discharging"
    } else if caps.hasCHIE {
        return (client.readHex(.CHIE) ?? "00") == "00" ? "not discharging" : "discharging"
    }
    return "not discharging"
}
