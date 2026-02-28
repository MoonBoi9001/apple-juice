import Foundation

enum ChargingAction: Equatable {
    case disableCharging, enableCharging, noAction
}

struct ChargingDecision {
    static func evaluate(percentage: Int, chargingEnabled: Bool,
                         upperLimit: Int, lowerLimit: Int) -> ChargingAction {
        if percentage >= upperLimit && chargingEnabled { return .disableCharging }
        if percentage < lowerLimit && !chargingEnabled { return .enableCharging }
        return .noAction
    }
}

/// Internal subcommand for the maintain daemon loop (invoked by LaunchAgent).
/// This is the port of `maintain_synchronous` from the bash script.
final class MaintainDaemon {
    enum Status: String {
        case active
        case suspended
    }

    private let smcClient: SMCClientProtocol
    private let caps: SMCCapabilities
    private let controller: ChargingController
    private let config: ConfigStore
    private let signalHandler: SignalHandler
    private var sleepWakeListener: SleepWakeListener?

    // All mutable state below is accessed from multiple threads (main loop,
    // sleep/wake callback, signal handler) and MUST be read/written under smcQueue.
    private var status: Status = .active
    private var upperLimit: Int
    private var lowerLimit: Int
    private var consecutiveFailures = 0
    private var dailyLogTimeout: TimeInterval
    private var updateCheckTimeout: TimeInterval
    private var updateBackoff: TimeInterval = 3600
    private var cellBalanceCheckTimeout: TimeInterval
    private var cellVoltageWarningShown = false
    private var informedVersion: String
    private var preACConnection: Bool = false
    private var sleepDuration: UInt32 = 60
    private var consecutiveControlFailures = 0
    /// Serial queue protecting SMC access and shared mutable state from concurrent threads.
    private let smcQueue = DispatchQueue(label: "com.apple-juice.smc")

    init(upperLimit: Int, lowerLimit: Int) {
        self.smcClient = IOKitSMCClient()
        self.caps = SMCCapabilities.probe(using: smcClient)
        self.controller = ChargingController(client: smcClient, caps: caps)
        self.config = ConfigStore()
        self.signalHandler = SignalHandler()
        self.upperLimit = upperLimit
        self.lowerLimit = lowerLimit

        let now = Date().timeIntervalSince1970
        self.dailyLogTimeout = now + 86400
        self.updateCheckTimeout = now + (3 * 86400)
        self.cellBalanceCheckTimeout = now + 3600
        self.informedVersion = config.informedVersion ?? "v\(appVersion)"
    }

    func run() {
        // Reset CHWA
        if caps.hasCHWA {
            smcClient.write(.CHWA, value: SMCWriteValue.CHWA_disable)
        }

        log("Starting maintenance at \(upperLimit)% with sailing to \(lowerLimit)%")
        log("Charging to and maintaining at \(upperLimit)% from \(getBatteryPercentage(using: smcClient))%")

        // Write PID file
        writePidFile()

        // Initialize daily log header if needed
        initDailyLog()

        // Initialize calibrate_next if unset
        if config.calibrateNext == nil {
            // Will be set by schedule system
        }

        controller.changeMagSafeLED(.auto)

        // Setup sleep/wake listener for charging control during sleep
        sleepWakeListener = SleepWakeListener { [weak self] event in
            guard let self = self else { return }
            let acPower = BatteryInfo.isACPower
            self.smcQueue.sync {
                switch event {
                case .willSleep:
                    let pct = getBatteryPercentage(using: self.smcClient)
                    self.smcClient.write(.CH0I, value: SMCWriteValue.CH0I_disable)
                    if pct >= self.upperLimit {
                        // At or above target: disable charging during sleep
                        self.smcClient.write(.CH0C, value: SMCWriteValue.CH0C_disable)
                        log("Sleep: at \(pct)% (>= \(self.upperLimit)%), charging disabled")
                    } else if self.status == .active && acPower {
                        // Below target with AC: leave charging enabled, schedule wake to cut off at target
                        self.smcClient.write(.CH0C, value: SMCWriteValue.CH0C_enable)
                        if let seconds = WakeScheduler.estimateTimeToTarget(
                            currentPercent: pct, targetPercent: self.upperLimit) {
                            WakeScheduler.scheduleWake(at: Date().addingTimeInterval(seconds))
                        }
                        log("Sleep: at \(pct)% (< \(self.upperLimit)%), charging enabled with scheduled wake")
                    } else {
                        // Below target but suspended or no AC: disable charging
                        self.smcClient.write(.CH0C, value: SMCWriteValue.CH0C_disable)
                        log("Sleep: at \(pct)%, charging disabled (suspended or no AC)")
                    }
                    // CHWA 80% ceiling as firmware safety net (may not work on macOS 15+)
                    if self.caps.hasCHWA {
                        self.smcClient.write(.CHWA, value: SMCWriteValue.CHWA_enable)
                    }
                case .didWake:
                    WakeScheduler.cancelWake()
                    if self.caps.hasCHWA {
                        self.smcClient.write(.CHWA, value: SMCWriteValue.CHWA_disable)
                    }
                    log("Wake: resumed daemon control")
                }
            }
        }
        sleepWakeListener?.start()

        // Setup signal handlers (dispatch through smcQueue since they trigger SMC writes)
        signalHandler.onCommand = { [weak self] command in
            self?.smcQueue.sync {
                self?.handleSignalCommand(command)
            }
        }
        signalHandler.onTerminate = { [weak self] in
            self?.smcQueue.sync {
                self?.cleanup()
            }
        }
        signalHandler.startListening()

        // Main loop
        while true {
            writePidFile()

            let now = Date().timeIntervalSince1970

            // Read status under queue to avoid racing with signal handler
            let currentStatus: Status = smcQueue.sync { status }

            if currentStatus == .active {
                smcQueue.sync {
                    // Auto LED management
                    controller.changeMagSafeLED(.auto)

                    // Core charging control
                    let pct = getBatteryPercentage(using: smcClient)
                    let chargingEnabled = getSMCChargingStatus(using: smcClient, caps: caps) == "enabled"

                    let action = ChargingDecision.evaluate(
                        percentage: pct, chargingEnabled: chargingEnabled,
                        upperLimit: upperLimit, lowerLimit: lowerLimit)

                    switch action {
                    case .disableCharging:
                        log("Stop charge above \(upperLimit)")
                        controller.disableCharging()
                        let stillEnabled = getSMCChargingStatus(using: smcClient, caps: caps) == "enabled"
                        if stillEnabled {
                            consecutiveControlFailures += 1
                            log("Warning: SMC write to disable charging did not take effect (\(consecutiveControlFailures) consecutive)")
                        } else {
                            consecutiveControlFailures = 0
                        }
                        sleepDuration = 60
                    case .enableCharging:
                        log("Charge below \(lowerLimit)")
                        controller.enableCharging()
                        let stillDisabled = getSMCChargingStatus(using: smcClient, caps: caps) == "disabled"
                        if stillDisabled {
                            consecutiveControlFailures += 1
                            log("Warning: SMC write to enable charging did not take effect (\(consecutiveControlFailures) consecutive)")
                        } else {
                            consecutiveControlFailures = 0
                        }
                        sleepDuration = 5
                    case .noAction:
                        break
                    }

                    if consecutiveControlFailures >= 5 {
                        log("Error: SMC charging control failed 5 consecutive times, exiting for launchd restart")
                        fatalExit()
                    }
                }

                let currentSleep: UInt32 = smcQueue.sync { sleepDuration }
                Thread.sleep(forTimeInterval: TimeInterval(currentSleep))
            } else {
                // Suspended
                Thread.sleep(forTimeInterval: 60)

                // Check for AC reconnection to auto-recover (under queue)
                let acConnected = BatteryInfo.isACPower
                smcQueue.sync {
                    if !ProcessHelper.calibrateIsRunning() {
                        if acConnected && !preACConnection {
                            status = .active
                            log("Battery maintain is recovered because AC adapter is reconnected")
                            Notifications.displayNotification(
                                message: "Battery maintain is recovered",
                                title: "apple-juice")
                        }
                    }
                    preACConnection = acConnected
                }
            }

            // Daily log check
            if now > dailyLogTimeout {
                recordDailyLog()
                dailyLogTimeout = Date().timeIntervalSince1970 + 86400
            }

            // Cell balance check (longevity mode)
            if now > cellBalanceCheckTimeout {
                checkCellBalance()
                cellBalanceCheckTimeout = Date().timeIntervalSince1970 + 3600
            }

            // Update check
            if now > updateCheckTimeout {
                checkForUpdates()
            }

            // AlDente conflict check
            checkAlDente()

            // Read battery, track failures (under queue for SMC + consecutiveFailures)
            smcQueue.sync {
                let pct = getBatteryPercentage(using: smcClient)
                if pct <= 0 {
                    consecutiveFailures += 1
                    if consecutiveFailures > 10 {
                        log("Error: Too many consecutive failures reading battery percentage, exiting maintain loop")
                        fatalExit()
                    }
                } else {
                    consecutiveFailures = 0
                }
            }
            let currentFailures: Int = smcQueue.sync { consecutiveFailures }
            if currentFailures > 0 {
                Thread.sleep(forTimeInterval: 60)
                continue
            }
        }
    }

    // MARK: - PID file

    private var pidFileFailureLogged = false

    private func writePidFile() {
        let currentStatus: Status = smcQueue.sync { status }
        let content = "\(getpid()) \(currentStatus.rawValue)"
        do {
            try content.write(toFile: Paths.pidFile, atomically: true, encoding: .utf8)
            pidFileFailureLogged = false
        } catch {
            if !pidFileFailureLogged {
                // Log to stderr (captured by launchd) since file logging may also be broken
                fputs("apple-juice: failed to write PID file: \(error.localizedDescription)\n", stderr)
                log("Error: failed to write PID file: \(error.localizedDescription)")
                pidFileFailureLogged = true
            }
        }
    }

    // MARK: - Signal handling

    private func handleSignalCommand(_ command: SignalCommand) {
        switch command {
        case .suspend:
            status = .suspended
            controller.enableCharging()
        case .suspendNoCharging:
            status = .suspended
        case .recover:
            status = .active
        }
    }

    /// Clean shutdown: re-enable charging, clean up resources, exit 0.
    /// Called from signal handler under smcQueue.
    private func cleanup() {
        log("Maintain daemon terminated, re-enabling charging")
        sleepWakeListener?.stop()
        WakeScheduler.cancelWake()
        controller.enableCharging()
        try? FileManager.default.removeItem(atPath: Paths.pidFile)
        // Exit 0 so KeepAlive (SuccessfulExit: false) does NOT restart.
        // User-initiated stops (SIGTERM/SIGINT) should stay stopped.
        // Crashes (SIGKILL, segfault) produce non-zero exits, triggering restart.
        exit(0)
    }

    /// Fatal exit: re-enable charging, clean up, exit 1 for launchd restart.
    private func fatalExit() {
        sleepWakeListener?.stop()
        WakeScheduler.cancelWake()
        controller.enableCharging()
        try? FileManager.default.removeItem(atPath: Paths.pidFile)
        exit(1)
    }

    // MARK: - Daily logging

    private func initDailyLog() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Paths.dailyLogFile) {
            let header = [
                pad("Time", 10, left: true),
                pad("Capacity", 9),
                pad("Voltage", 9),
                pad("Temperature", 12),
                pad("Health", 9),
                pad("Cycle", 9),
            ].joined(separator: ", ")
            try? (header + "\n").write(toFile: Paths.dailyLogFile, atomically: true, encoding: .utf8)
        }
    }

    private func recordDailyLog() {
        let nowDate = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: Date())
        }()

        guard nowDate != config.dailyLast else { return }

        let battery = BatteryInfo()
        let dateStr: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy/MM/dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: Date())
        }()
        let entry = [
            pad(dateStr, 10, left: true),
            pad("\(battery.accuratePercentage)%", 9),
            pad("\(battery.voltage)V", 9),
            pad("\(battery.temperature)\u{00B0}C", 13),
            pad("\(battery.healthPercentage)%", 9),
            pad(battery.cycleCountString, 9),
        ].joined(separator: ", ")

        if let handle = FileHandle(forWritingAtPath: Paths.dailyLogFile) {
            handle.seekToEndOfFile()
            handle.write((entry + "\n").data(using: .utf8) ?? Data())
            handle.closeFile()
        }

        // Rotate daily.log: keep last 365 entries (~1 year)
        rotateDailyLog()

        // Notification
        Notifications.displayNotification(
            message: "Battery \(battery.accuratePercentage)%, \(battery.voltage)V, \(battery.temperature)\u{00B0}C\nHealth \(battery.healthPercentage)%, Cycle \(battery.cycleCountString)",
            title: "apple-juice")

        try? config.write("daily_last", value: nowDate)
    }

    private func rotateDailyLog() {
        guard let contents = try? String(contentsOfFile: Paths.dailyLogFile, encoding: .utf8) else { return }
        let lines = contents.components(separatedBy: "\n")
        // Keep header + last 365 data lines
        if lines.count > 366 {
            let header = lines.first ?? ""
            let kept = [header] + lines.suffix(365)
            try? kept.joined(separator: "\n").write(toFile: Paths.dailyLogFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Cell balance monitoring

    private func checkCellBalance() {
        guard config.longevityMode == "enabled" else { return }
        guard !ProcessHelper.calibrateIsRunning() else { return }

        let battery = BatteryInfo()
        guard let imbalance = battery.cellImbalance else {
            if !cellVoltageWarningShown {
                log("Warning: Cell voltage data unavailable - imbalance monitoring disabled")
                cellVoltageWarningShown = true
            }
            return
        }

        if imbalance > 200 {
            let voltages = battery.cellVoltages?.map(String.init).joined(separator: ", ") ?? "?"
            log("Cell imbalance detected: \(imbalance)mV (cells: \(voltages)mV). Triggering balance for BMS cell balancing.")
            let binaryPath = CommandLine.arguments[0]
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["balance"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }

    // MARK: - Update check

    private func checkForUpdates() {
        let result = ProcessRunner.shell(
            "curl -sS --max-time 10 'https://api.github.com/repos/MoonBoi9001/apple-juice/releases/latest' 2>/dev/null",
            timeout: 15)

        if result.succeeded {
            // Extract tag_name from JSON
            let json = result.stdout
            if let range = json.range(of: #""tag_name"\s*:\s*"([^"]+)""#, options: .regularExpression) {
                let match = json[range]
                if let valueStart = match.range(of: #":\s*""#, options: .regularExpression)?.upperBound,
                   let valueEnd = match[valueStart...].firstIndex(of: "\"") {
                    let newVersion = String(match[valueStart..<valueEnd])

                    if !newVersion.isEmpty && newVersion != informedVersion {
                        Notifications.displayNotification(
                            message: "New version \(newVersion) available\nUpdate with command \"apple-juice update\"",
                            title: "apple-juice")
                        informedVersion = newVersion
                        try? config.write("informed_version", value: informedVersion)
                    }
                }
            }
            updateCheckTimeout = Date().timeIntervalSince1970 + 86400
            updateBackoff = 3600
        } else {
            updateCheckTimeout = Date().timeIntervalSince1970 + updateBackoff
            updateBackoff = min(updateBackoff * 2, 86400)
        }
    }

    // MARK: - AlDente check

    private func checkAlDente() {
        let result = ProcessRunner.shell("pgrep -f aldente")
        if result.succeeded && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log("AlDente is running. Turn it off")
            ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", "quit app \"aldente\""])
        }
    }

    private func pad(_ s: String, _ width: Int, left: Bool = false) -> String {
        left ? s.padding(toLength: width, withPad: " ", startingAt: 0)
             : String(repeating: " ", count: max(0, width - s.count)) + s
    }
}
