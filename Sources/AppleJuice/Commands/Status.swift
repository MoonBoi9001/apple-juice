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
        let battery = BatteryInfo()
        let state = getChargingState(using: smcClient)

        print("")
        log("Battery at \(battery.accuratePercentage)%, \(battery.voltage)V, \(battery.temperature)\u{00B0}C, \(state.description)")
        log("Battery health \(battery.healthPercentage)%, Cycle \(battery.cycleCountString)")

        if let cells = battery.cellVoltages, !cells.isEmpty {
            let voltages = cells.map { String($0) }.joined(separator: ", ")
            let imbalance = battery.cellImbalance ?? 0
            log("Cell voltages: \(voltages)mV (imbalance: \(imbalance)mV)")
        }

        // Maintain status
        if ProcessHelper.maintainIsRunning() {
            let config = ConfigStore()
            let maintainPercentage = config.maintainPercentage
            let maintainStatus = ProcessHelper.readPidFileStatus(Paths.pidFile)

            if maintainStatus == "active" {
                if config.longevityMode == "enabled" {
                    log("Longevity mode active (65% sailing to 60%)")
                } else if let mp = maintainPercentage {
                    let parts = mp.split(separator: " ")
                    if let upperStr = parts.first, let upper = Int(upperStr) {
                        var lower = upper - 5
                        if parts.count > 1, let l = Int(parts[1]), l >= 0, l <= 100 {
                            lower = l
                        }
                        log("Your battery is currently being maintained at \(upper)% with sailing to \(lower)%")
                    }
                }
            } else {
                if ProcessHelper.calibrateIsRunning() {
                    log("Calibration ongoing, maintain is suspended")
                } else {
                    log("Battery maintain is suspended")
                }
            }
        } else {
            log("Battery maintain is not running")
        }

        // Schedule status
        showSchedule()

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

/// Show schedule status matching bash `show_schedule()`.
func showSchedule() {
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
        log("You haven't scheduled calibration yet")
        return
    }

    if scheduleEnabled {
        // Trim " starting..." suffix if present
        var display = scheduleTxt
        if let range = display.range(of: " starting") {
            display = String(display[..<range.lowerBound])
        }
        log(display)

        // Show next calibration date
        if let nextTimestamp = config.calibrateNext, let ts = TimeInterval(nextTimestamp) {
            let date = Date(timeIntervalSince1970: ts)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            log("Next calibration date is \(formatter.string(from: date))")
        }
    } else {
        log("Your calibration schedule is disabled. Enable it by")
        log("apple-juice schedule enable")
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
