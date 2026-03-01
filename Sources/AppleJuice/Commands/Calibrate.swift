import ArgumentParser
import Foundation

struct Calibrate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calibrate",
        abstract: "Calibrate the battery"
    )

    @Argument(help: "Optional: 'stop' or 'force'")
    var action: String?

    func run() throws {
        let binaryPath = CommandLine.arguments[0]
        let config = ConfigStore()

        // Check if this is a scheduled (non-terminal) invocation
        let isTerminal = isatty(STDIN_FILENO) != 0
        if !isTerminal && action != "force" {
            let now = Date().timeIntervalSince1970
            if let nextStr = config.calibrateNext, let next = TimeInterval(nextStr) {
                let diff = now - next
                if diff < -30 || diff > 30 {
                    log("Skip this calibration")
                    return
                }
            }
        }

        // Kill old calibration process
        if let pid = ProcessHelper.readPid(Paths.calibratePidFile), kill(pid, 0) == 0 {
            kill(pid, SIGTERM)
        }

        if action == "stop" {
            try? FileManager.default.removeItem(atPath: Paths.calibratePidFile)
            ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
            return
        }

        // Update next calibration date
        // (Schedule system will compute this)

        // Ensure maintain is running
        if !ProcessHelper.maintainIsRunning() {
            if !FileManager.default.fileExists(atPath: Paths.daemonPath) {
                DaemonManager.createDaemon()
            }
            let uid = ProcessRunner.shell("id -u").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            ProcessRunner.shell("launchctl enable gui/\(uid)/com.apple-juice.app")
            ProcessRunner.shell("launchctl unload '\(Paths.daemonPath)' 2>/dev/null")
            ProcessRunner.shell("launchctl load '\(Paths.daemonPath)' 2>/dev/null")
        }

        // Wait for maintain to start
        for _ in 0..<10 {
            if ProcessHelper.maintainIsRunning() { break }
            Thread.sleep(forTimeInterval: 1)
        }

        // Initialize calibrate log
        let fm = FileManager.default
        if !fm.fileExists(atPath: Paths.calibrateLogFile) {
            let header = [
                pad("Time", 16, left: true),
                pad("Completed", 9),
                pad("Health_before", 13),
                pad("Health_after", 12),
                "Duration/Error",
            ].joined(separator: ", ")
            try? (header + "\n").write(toFile: Paths.calibrateLogFile, atomically: true, encoding: .utf8)
        }

        let calibrateTime: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy/MM/dd HH:mm"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: Date())
        }()

        let battery = BatteryInfo()
        let healthBefore = "\(battery.healthPercentage)%"

        // Abort if maintain not running
        guard ProcessHelper.maintainIsRunning() else {
            Notifications.displayNotification(
                message: "Battery maintain needs to run before calibration",
                title: "Battery Calibration Error")
            log("Calibration Error: Battery maintain needs to run before calibration")
            writeCalibrateLog(time: calibrateTime, completed: "No",
                            healthBefore: healthBefore, healthAfter: "%",
                            error: "Battery maintain needs to run before calibration")
            throw ExitCode.failure
        }

        // Store calibration PID early so `calibrate stop` works during the wait
        try? "\(getpid())".write(toFile: Paths.calibratePidFile, atomically: true, encoding: .utf8)

        // Check lid and AC
        if BatteryInfo.isLidClosed || !BatteryInfo.isACPower {
            Webhook.send(stage: "open_lid_remind")
            Notifications.displayNotification(
                message: "Battery calibration will start immediately after you open macbook lid and connect AC power",
                title: "Battery Calibration")
            log("Calibration: Please open macbook lid and connect AC to start calibration")

            // Wait up to 24h
            let timeout = Date().timeIntervalSince1970 + 86400
            while Date().timeIntervalSince1970 < timeout {
                if !BatteryInfo.isLidClosed && BatteryInfo.isACPower { break }
                Thread.sleep(forTimeInterval: 5)
            }
        }

        // Re-check
        if BatteryInfo.isLidClosed || !BatteryInfo.isACPower {
            var errors: [String] = []
            if BatteryInfo.isLidClosed { errors.append("Macbook lid is not open") }
            if !BatteryInfo.isACPower { errors.append("No AC power") }
            let errorMsg = errors.joined(separator: " and ")

            Webhook.send(stage: "err_lid_closed")
            Notifications.displayNotification(message: "\(errorMsg)!", title: "Battery Calibration Error")
            log("Calibration Error: \(errorMsg)!")
            writeCalibrateLog(time: calibrateTime, completed: "No",
                            healthBefore: healthBefore, healthAfter: "%", error: errorMsg)
            throw ExitCode.failure
        }

        let startTime = Date()

        // Get maintain percentage
        let maintainPct = getMaintainUpperLimit()

        // Select method
        let methodStr = config.calibrateMethod ?? "1"
        let method = (methodStr == "2") ? 2 : 1

        if method == 1 {
            try runMethod1(binaryPath: binaryPath, maintainPct: maintainPct,
                          calibrateTime: calibrateTime, healthBefore: healthBefore, startTime: startTime)
        } else {
            try runMethod2(binaryPath: binaryPath, maintainPct: maintainPct,
                          calibrateTime: calibrateTime, healthBefore: healthBefore, startTime: startTime)
        }
    }

    // MARK: - Method 1: Discharge 15% -> Charge 100% -> Wait 1h -> Discharge to maintain%

    private func runMethod1(binaryPath: String, maintainPct: Int,
                           calibrateTime: String, healthBefore: String, startTime: Date) throws {
        let battery = BatteryInfo()
        Webhook.send(stage: "start", battery: battery.accuratePercentage,
                    voltage: battery.voltage, health: battery.healthPercentage)
        Notifications.displayNotification(
            message: "Calibration has started!\nStart discharging to 15%",
            title: "Battery Calibration")
        log("Calibration: Calibration has started! Start discharging to 15%")

        ProcessRunner.run(binaryPath, arguments: ["maintain", "suspend"])

        // Discharge to 15%
        Webhook.send(stage: "discharge15_start", battery: BatteryInfo().accuratePercentage)
        let dischargeResult = ProcessRunner.run(binaryPath, arguments: ["discharge", "15"])
        if !dischargeResult.succeeded {
            handleCalibrationError(stage: "err_discharge15", message: "Discharge to 15% fail",
                                  calibrateTime: calibrateTime, healthBefore: healthBefore, binaryPath: binaryPath)
            throw ExitCode.failure
        }

        Webhook.send(stage: "discharge15_end", battery: BatteryInfo().accuratePercentage)
        Notifications.displayNotification(
            message: "Calibration has discharged to 15%\nStart charging to 100%",
            title: "Battery Calibration")
        log("Calibration: Calibration has discharged to 15%. Start charging to 100%")

        // Charge to 100%
        Webhook.send(stage: "charge100_start", battery: BatteryInfo().accuratePercentage)
        let chargeResult = ProcessRunner.run(binaryPath, arguments: ["charge", "100"])
        if !chargeResult.succeeded {
            handleCalibrationError(stage: "err_charge100", message: "Charge to 100% fail",
                                  calibrateTime: calibrateTime, healthBefore: healthBefore, binaryPath: binaryPath)
            throw ExitCode.failure
        }

        Webhook.send(stage: "charge100_end", battery: BatteryInfo().accuratePercentage)
        Notifications.displayNotification(
            message: "Calibration has charged to 100%\nWaiting for one hour",
            title: "Battery Calibration")
        log("Calibration: Calibration has charged to 100%. Waiting for one hour")

        // Wait 1 hour
        Thread.sleep(forTimeInterval: 3600)

        Webhook.send(stage: "wait_1hr_done", battery: BatteryInfo().accuratePercentage)
        Notifications.displayNotification(
            message: "Battery has been maintained at 100% for one hour\nStart discharging to \(maintainPct)%",
            title: "Battery Calibration")
        log("Calibration: Start discharging to maintain percentage")

        // Discharge to maintain%
        let finalDischarge = ProcessRunner.run(binaryPath, arguments: ["discharge", String(maintainPct)])
        if !finalDischarge.succeeded {
            handleCalibrationError(stage: "err_discharge_maintain", message: "Discharge to \(maintainPct)% fail",
                                  calibrateTime: calibrateTime, healthBefore: healthBefore, binaryPath: binaryPath)
            throw ExitCode.failure
        }

        finishCalibration(calibrateTime: calibrateTime, healthBefore: healthBefore,
                         startTime: startTime, binaryPath: binaryPath)
    }

    // MARK: - Method 2: Charge 100% -> Wait 1h -> Discharge 15% -> Charge to maintain%

    private func runMethod2(binaryPath: String, maintainPct: Int,
                           calibrateTime: String, healthBefore: String, startTime: Date) throws {
        let battery = BatteryInfo()
        Webhook.send(stage: "start", battery: battery.accuratePercentage,
                    voltage: battery.voltage, health: battery.healthPercentage)
        Notifications.displayNotification(
            message: "Calibration has started!\nStart charging to 100%",
            title: "Battery Calibration")
        log("Calibration: Calibration has started! Start charging to 100%")

        ProcessRunner.run(binaryPath, arguments: ["maintain", "suspend"])

        // Charge to 100%
        Webhook.send(stage: "charge100_start", battery: BatteryInfo().accuratePercentage)
        let chargeResult = ProcessRunner.run(binaryPath, arguments: ["charge", "100"])
        if !chargeResult.succeeded {
            handleCalibrationError(stage: "err_charge100", message: "Charge to 100% fail",
                                  calibrateTime: calibrateTime, healthBefore: healthBefore, binaryPath: binaryPath)
            throw ExitCode.failure
        }

        Webhook.send(stage: "charge100_end", battery: BatteryInfo().accuratePercentage)
        Notifications.displayNotification(
            message: "Calibration has charged to 100%\nWaiting for one hour",
            title: "Battery Calibration")
        log("Calibration: Charged to 100%. Waiting for one hour")

        Thread.sleep(forTimeInterval: 3600)

        Webhook.send(stage: "wait_1hr_done", battery: BatteryInfo().accuratePercentage)
        Notifications.displayNotification(
            message: "Battery has been maintained at 100% for one hour\nStart discharging to 15%",
            title: "Battery Calibration")
        log("Calibration: Start discharging to 15%")

        // Discharge to 15%
        Webhook.send(stage: "discharge15_start", battery: BatteryInfo().accuratePercentage)
        let dischargeResult = ProcessRunner.run(binaryPath, arguments: ["discharge", "15"])
        if !dischargeResult.succeeded {
            handleCalibrationError(stage: "err_discharge15", message: "Discharge to 15% fail",
                                  calibrateTime: calibrateTime, healthBefore: healthBefore, binaryPath: binaryPath)
            throw ExitCode.failure
        }

        Webhook.send(stage: "discharge15_end", battery: BatteryInfo().accuratePercentage)
        Notifications.displayNotification(
            message: "Calibration has discharged to 15%\nStart charging to \(maintainPct)%",
            title: "Battery Calibration")
        log("Calibration: Discharged to 15%. Start charging to \(maintainPct)%")

        // Charge back to maintain%
        let finalCharge = ProcessRunner.run(binaryPath, arguments: ["charge", String(maintainPct)])
        if !finalCharge.succeeded {
            handleCalibrationError(stage: "err_charge_maintain", message: "Charge to \(maintainPct)% fail",
                                  calibrateTime: calibrateTime, healthBefore: healthBefore, binaryPath: binaryPath)
            throw ExitCode.failure
        }

        finishCalibration(calibrateTime: calibrateTime, healthBefore: healthBefore,
                         startTime: startTime, binaryPath: binaryPath)
    }

    // MARK: - Helpers

    private func finishCalibration(calibrateTime: String, healthBefore: String,
                                   startTime: Date, binaryPath: String) {
        let battery = BatteryInfo()
        let healthAfter = "\(battery.healthPercentage)%"
        let duration = Int(Date().timeIntervalSince(startTime))
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let durationStr = "\(hours)h\(minutes)m"

        writeCalibrateLog(time: calibrateTime, completed: "Yes",
                         healthBefore: healthBefore, healthAfter: healthAfter, error: durationStr)

        Webhook.send(stage: "end", battery: battery.accuratePercentage,
                    voltage: battery.voltage, health: battery.healthPercentage)
        Notifications.displayNotification(
            message: "Calibration completed!\nHealth: \(healthBefore) -> \(healthAfter)",
            title: "Battery Calibration")
        log("Calibration: Completed! Health: \(healthBefore) -> \(healthAfter), Duration: \(durationStr)")

        // Advance calibrate_next based on schedule period so the next LaunchAgent
        // fire within the period window is skipped.
        advanceCalibrateNext()

        try? FileManager.default.removeItem(atPath: Paths.calibratePidFile)
        ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
    }

    /// Advance calibrate_next by parsing the schedule description to extract the period.
    private func advanceCalibrateNext() {
        let config = ConfigStore()
        guard let schedule = config.calibrateSchedule else { return }

        let calendar = Calendar.current
        var nextDate: Date?

        if schedule.contains("week") {
            // Extract week period: "...every N week..."
            let period = schedule.range(of: #"every (\d+) week"#, options: .regularExpression)
                .flatMap { Int(schedule[$0].split(separator: " ")[1]) } ?? 1
            nextDate = calendar.date(byAdding: .weekOfYear, value: period, to: Date())
        } else if schedule.contains("every") && schedule.contains("month") {
            // Extract month period: "...every N month..."
            let period = schedule.range(of: #"every (\d+) month"#, options: .regularExpression)
                .flatMap { Int(schedule[$0].split(separator: " ")[1]) } ?? 1
            nextDate = calendar.date(byAdding: .month, value: period, to: Date())
        } else {
            // Simple monthly: advance by 1 month
            nextDate = calendar.date(byAdding: .month, value: 1, to: Date())
        }

        if let next = nextDate {
            try? config.write("calibrate_next", value: String(Int(next.timeIntervalSince1970)))
        }
    }

    private func handleCalibrationError(stage: String, message: String,
                                        calibrateTime: String, healthBefore: String,
                                        binaryPath: String) {
        Webhook.send(stage: stage)
        Notifications.displayNotification(message: message, title: "Battery Calibration Error")
        log("Calibration Error: \(message)")
        writeCalibrateLog(time: calibrateTime, completed: "No",
                         healthBefore: healthBefore, healthAfter: "%", error: message)
        try? FileManager.default.removeItem(atPath: Paths.calibratePidFile)
        ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
    }

    private func writeCalibrateLog(time: String, completed: String,
                                   healthBefore: String, healthAfter: String, error: String) {
        let entry = [
            pad(time, 16, left: true),
            pad(completed, 9),
            pad(healthBefore, 13),
            pad(healthAfter, 12),
            error,
        ].joined(separator: ", ")
        if let handle = FileHandle(forWritingAtPath: Paths.calibrateLogFile) {
            handle.seekToEndOfFile()
            handle.write((entry + "\n").data(using: .utf8) ?? Data())
            handle.closeFile()
        }
    }
}
