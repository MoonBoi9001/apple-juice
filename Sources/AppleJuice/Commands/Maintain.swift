import ArgumentParser
import Foundation

struct Maintain: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "maintain",
        abstract: "Maintain battery at a target percentage",
        subcommands: [MaintainDaemonCommand.self]
    )

    @Argument(help: "Target percentage (10-100), or: stop, suspend, recover, longevity")
    var target: String

    @Argument(help: "Sailing target percentage (optional lower bound)")
    var sailingTarget: String?

    @Flag(name: .long, help: "Force discharge to maintain level")
    var forceDischarge = false

    func run() throws {
        let binaryPath = CommandLine.arguments[0]

        // Determine if called by another apple-juice process (suppresses notifications)
        let ppid = getppid()
        let ppidCheck = ProcessRunner.shell("ps -p \(ppid) -o args= 2>/dev/null")
        let notify = !ppidCheck.stdout.contains("apple-juice")

        let pid = ProcessHelper.readPid(Paths.pidFile)

        // Handle recover
        if target == "recover" {
            if ProcessHelper.maintainIsRunning(), let pid {
                let status = ProcessHelper.readPidFileStatus(Paths.pidFile)
                if status == "suspended" {
                    logn("Recover in 5 secs, wait .")
                    let ack = SignalHandler.sendCommand(.recover, toDaemon: pid)
                    if ack {
                        logLF("Battery maintain is recovered")
                        if notify {
                            Notifications.displayNotification(
                                message: "Battery maintain is recovered",
                                title: "apple-juice")
                        }
                    } else {
                        logLF("Error: Battery maintain recover failed")
                        if notify {
                            Notifications.displayNotification(
                                message: "Error: Battery maintain recover failed",
                                title: "apple-juice")
                        }
                        throw ExitCode.failure
                    }
                } else {
                    log("Battery maintain is already running")
                }
            } else {
                log("Battery maintain is not running")
            }
            return
        }

        // Handle suspend
        if target == "suspend" {
            guard ProcessHelper.maintainIsRunning(), let pid else {
                log("Battery maintain is not running")
                return
            }

            let status = ProcessHelper.readPidFileStatus(Paths.pidFile)
            if status == "active" {
                let command: SignalCommand = notify ? .suspend : .suspendNoCharging
                logn("Suspend in 5 secs, wait .")
                let ack = SignalHandler.sendCommand(command, toDaemon: pid)
                if ack {
                    logLF("Battery maintain is suspended")
                    if notify {
                        Notifications.displayNotification(
                            message: "Battery maintain is suspended",
                            title: "apple-juice")
                    }
                } else {
                    logLF("Error: Battery maintain suspend failed")
                    if notify {
                        Notifications.displayNotification(
                            message: "Error: Battery maintain suspend failed",
                            title: "apple-juice")
                    }
                    throw ExitCode.failure
                }
            } else {
                if notify {
                    Notifications.displayNotification(
                        message: "Battery maintain is suspended",
                        title: "apple-juice")
                }
            }
            return
        }

        // Kill old process
        if let pid {
            if kill(pid, 0) == 0 {
                kill(pid, SIGTERM)
            }
        }

        // Handle stop
        if target == "stop" {
            try? FileManager.default.removeItem(atPath: Paths.pidFile)
            DaemonManager.stopDaemon()
            DaemonManager.disableDaemon()
            DaemonManager.disableScheduleDaemon()
            let smcClient = SMCBinaryClient()
            let caps = SMCCapabilities.probe(using: smcClient)
            ChargingController(client: smcClient, caps: caps).enableCharging()
            ProcessRunner.run(binaryPath, arguments: ["status"])
            return
        }

        // Kill running calibration
        if let calPid = ProcessHelper.readPid(Paths.calibratePidFile) {
            if kill(calPid, 0) == 0 {
                kill(calPid, SIGTERM)
            }
            try? FileManager.default.removeItem(atPath: Paths.calibratePidFile)
            log("Calibration process have been stopped")
        }

        // Handle longevity preset
        var setting = target
        var sub = sailingTarget

        if target == "longevity" {
            log("Using longevity preset: 65% with sailing to 60% (optimal for battery lifespan)")
            setting = "65"
            sub = "60"
            try? ConfigStore().write("longevity_mode", value: "enabled")

            // Auto-enable monthly balance
            if ConfigStore().calibrateSchedule == nil {
                log("Setting up monthly balance (recommended for longevity mode)")
                ProcessRunner.run(binaryPath, arguments: ["schedule"])
            }
            ProcessRunner.run(binaryPath, arguments: ["schedule", "enable"])
        } else {
            try? ConfigStore().write("longevity_mode", value: nil)
        }

        // Validate percentage
        guard let pct = Int(setting), pct >= 10, pct <= 100 else {
            log("Error: \(setting) is not a valid setting for maintain. Please use a number between 10 and 100, 'longevity' for optimal lifespan, or 'stop'/'recover'.")
            throw ExitCode.failure
        }

        // Save settings before starting daemon (daemon reads config on recover)
        let config = ConfigStore()
        if let sub, let _ = Int(sub) {
            try? config.write("maintain_percentage", value: "\(setting) \(sub)")
        } else {
            try? config.write("maintain_percentage", value: setting)
        }

        // Create LaunchAgent plist and start via launchctl (no nohup)
        DaemonManager.createDaemon()
        DaemonManager.startDaemon()

        // Report status
        ProcessRunner.run(binaryPath, arguments: ["status"])

        // Ask about discharge if battery is above target
        let smcClient = SMCBinaryClient()
        let currentPct = getBatteryPercentage(using: smcClient)
        if currentPct > pct && notify {
            let answer = Notifications.displayDialog(
                message: "Do you want to discharge battery to \(pct)% now?",
                buttons: ["Yes", "No"],
                timeout: 10)
            if answer == "Yes" {
                log("Start discharging to \(pct)%")
                ProcessRunner.run(binaryPath, arguments: ["discharge", setting])
                ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
            }
        }
    }
}

/// Internal subcommand that runs the synchronous maintain loop.
/// This is what the LaunchAgent invokes directly.
struct MaintainDaemonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "maintain-daemon",
        abstract: "Internal: run maintain loop synchronously (invoked by LaunchAgent)",
        shouldDisplay: false
    )

    @Argument(help: "Upper percentage limit or 'recover'")
    var setting: String

    @Argument(help: "Lower percentage limit (sailing target)")
    var subsetting: String?

    @Flag(name: .long, help: "Force discharge to maintain level before starting")
    var forceDischarge = false

    func run() throws {
        var upper: Int
        var lower: Int

        if setting == "recover" {
            let config = ConfigStore()
            guard let mp = config.maintainPercentage else {
                log("No setting to recover, exiting")
                return
            }
            log("Recovering maintenance percentage \(mp)")
            let parts = mp.split(separator: " ")
            guard let u = Int(parts.first ?? "") else {
                log("Error: invalid recover setting")
                throw ExitCode.failure
            }
            upper = u
            lower = parts.count > 1 ? (Int(parts[1]) ?? max(u - 5, 0)) : max(u - 5, 0)
        } else {
            guard let u = Int(setting), u >= 0, u <= 100 else {
                log("Error: \(setting) is not a valid setting for maintain")
                throw ExitCode.failure
            }
            upper = u
            if let sub = subsetting, let l = Int(sub), l >= 0, l <= 100 {
                guard upper > l else {
                    log("Error: sailing target \(l) larger than or equal to maintain level \(upper) is not allowed")
                    throw ExitCode.failure
                }
                lower = l
            } else {
                lower = max(upper - 5, 0)
            }
        }

        // Optional pre-discharge
        if forceDischarge {
            if BatteryInfo.isLidClosed {
                log("Error: macbook lid must be open before discharge")
                throw ExitCode.failure
            }
            log("Triggering discharge to \(upper) before enabling charging limiter")
            let binaryPath = CommandLine.arguments[0]
            ProcessRunner.run(binaryPath, arguments: ["discharge", String(upper)])
            log("Discharge pre maintenance complete, continuing to maintenance loop")
        }

        let daemon = MaintainDaemon(upperLimit: upper, lowerLimit: lower)
        daemon.run()
    }
}
