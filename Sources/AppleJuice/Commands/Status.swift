import ArgumentParser
import Foundation

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show battery status, health, and maintain state"
    )

    @Flag(name: .long, help: "Output in CSV format")
    var csv = false

    func run() throws {
        if csv {
            runCSV()
        } else {
            runNormal()
        }
    }

    private func runNormal() {
        let smcClient = SMCBinaryClient()
        let caps = SMCCapabilities.probe(using: smcClient)
        let battery = BatteryInfo()
        let state = getChargingState(using: smcClient)

        // Battery percentage
        let pctDisplay: String
        if let macos = battery.macOSPercentage {
            pctDisplay = "\(battery.accuratePercentage)% (macOS: \(macos)%)"
        } else {
            pctDisplay = "\(battery.accuratePercentage)%"
        }

        // Power source and charging state.
        // acPower: adapter detected by pmset.
        // state: derived from actual SMC currents (CHBI charge, B0AC discharge).
        //   .notCharging = zero current both ways = battery idle, system on adapter.
        //   .discharging = battery discharging (unplugged, or adapter can't keep up).
        //   .charging = current flowing into battery.
        let acPower = BatteryInfo.isACPower
        let chargingStatus = getSMCChargingStatus(using: smcClient, caps: caps)
        let powerDescription: String
        switch (acPower, state) {
        case (true, .charging):
            powerDescription = "charging from wall power"
        case (true, .discharging):
            powerDescription = "adapter connected, drawing from battery"
        case (true, .notCharging):
            powerDescription = "wall power, battery idle"
        case (false, .discharging):
            powerDescription = "running on battery"
        case (false, _):
            powerDescription = "on battery, not discharging"
        }

        // Single timestamp header, then clean data lines
        let statusTimestamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: Date())
        }()
        print("")
        print("  \(statusTimestamp)")
        print("")
        print("  Battery   \(pctDisplay), \(battery.temperature)\u{00B0}C")
        print("  Health    \(battery.healthPercentage)%, \(battery.cycleCountString) cycles")

        if let cells = battery.cellVoltages, !cells.isEmpty {
            let voltages = cells.map { String($0) }.joined(separator: ", ")
            let imbalance = battery.cellImbalance ?? 0
            print("  Cells     \(voltages) mV (\(imbalance)mV imbalance)")
        }

        print("  Power     \(powerDescription)")

        // Maintain status
        let modeDescription: String
        if ProcessHelper.maintainIsRunning() {
            let config = ConfigStore()
            let maintainPercentage = config.maintainPercentage
            let maintainStatus = ProcessHelper.readPidFileStatus(Paths.pidFile)

            if maintainStatus == "active" {
                if config.longevityMode == "enabled" {
                    modeDescription = "longevity, maintaining 60-65%"
                } else if let mp = maintainPercentage {
                    let parts = mp.split(separator: " ")
                    if let upperStr = parts.first, let upper = Int(upperStr) {
                        var lower = upper - 5
                        if parts.count > 1, let l = Int(parts[1]), l >= 0, l <= 100 {
                            lower = l
                        }
                        modeDescription = "maintaining \(lower)-\(upper)%"
                    } else {
                        modeDescription = "active"
                    }
                } else {
                    modeDescription = "active"
                }
            } else {
                if ProcessHelper.calibrateIsRunning() {
                    modeDescription = "calibration in progress, maintain paused"
                } else {
                    modeDescription = "maintain paused"
                }
            }
        } else {
            modeDescription = "not active"
        }
        print("  Mode      \(modeDescription)")

        // Schedule status
        showSchedule(styled: true)

        print("")
    }

    private func runCSV() {
        let smcClient = SMCBinaryClient()
        let caps = SMCCapabilities.probe(using: smcClient)
        let config = ConfigStore()

        // Battery percentage (integer from BRSC)
        let pct = smcClient.readDecimal(.BRSC).map { val in
            val > 100 ? val / 256 : val
        } ?? 0

        let remaining = BatteryInfo.remainingTime
        let chargingStatus = getSMCChargingStatus(using: smcClient, caps: caps)
        let dischargingStatus = getSMCDischargingStatus(using: smcClient, caps: caps)

        // get_maintain_percentage extracts just the first word (upper limit)
        let maintainPct = config.maintainPercentage?.split(separator: " ").first.map(String.init) ?? ""

        print("\(pct),\(remaining),\(chargingStatus),\(dischargingStatus),\(maintainPct)")
    }
}

// MARK: - Schedule display

/// Show schedule status. When `styled` is true, uses print with indent (for status output).
func showSchedule(styled: Bool = false) {
    let output: (String) -> Void = styled ? { print("  \($0)") } : { log($0) }

    let config = ConfigStore()

    // Check if schedule LaunchAgent is enabled
    let uid = ProcessRunner.shell("id -u").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let launchctlOutput = ProcessRunner.shell("launchctl print gui/\(uid)").stdout

    var scheduleEnabled = false
    if launchctlOutput.contains("=> enabled") {
        // New launchctl format
        scheduleEnabled = launchctlOutput.contains("com.apple-juice_schedule.app")
            && launchctlOutput.split(separator: "\n").contains {
                $0.contains("enabled") && $0.contains("com.apple-juice_schedule.app")
            }
    } else {
        // Old format: "=> false" means enabled (inverted logic matches bash)
        let line = launchctlOutput.split(separator: "\n").first {
            $0.contains("=> false") && $0.contains("com.apple-juice_schedule.app")
        }
        scheduleEnabled = line != nil
    }

    guard let scheduleTxt = config.calibrateSchedule else {
        return
    }

    if scheduleEnabled {
        // Trim " starting..." suffix if present
        var display = scheduleTxt
        if let range = display.range(of: " starting") {
            display = String(display[..<range.lowerBound])
        }

        // Show next calibration date
        if let nextTimestamp = config.calibrateNext, let ts = TimeInterval(nextTimestamp) {
            let date = Date(timeIntervalSince1970: ts)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            output("Schedule  \(display), next: \(formatter.string(from: date))")
        } else {
            output("Schedule  \(display)")
        }
    } else {
        output("Schedule  disabled")
    }
}

// MARK: - Process helpers

enum ProcessHelper {
    /// Check if the maintain daemon is running.
    /// Matches bash `maintain_is_running()`.
    static func maintainIsRunning() -> Bool {
        isProcessRunning(pidFile: Paths.pidFile)
    }

    /// Check if calibration is running.
    static func calibrateIsRunning() -> Bool {
        isProcessRunning(pidFile: Paths.calibratePidFile)
    }

    /// Read the status field from a PID file (format: "PID STATUS").
    static func readPidFileStatus(_ path: String) -> String? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let parts = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
        return parts.count > 1 ? String(parts[1]) : nil
    }

    /// Read the PID from a PID file.
    static func readPid(_ path: String) -> pid_t? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let pidStr = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").first.map(String.init) ?? ""
        return pid_t(pidStr)
    }

    /// Check if a process from a PID file is running and is an apple-juice process.
    private static func isProcessRunning(pidFile: String) -> Bool {
        guard let pid = readPid(pidFile) else { return false }

        // kill -0 checks process existence
        guard kill(pid, 0) == 0 else { return false }

        // Verify it's actually an apple-juice process
        let result = ProcessRunner.shell("ps -p \(pid) -o args= 2>/dev/null")
        return result.stdout.contains("apple-juice")
    }
}
