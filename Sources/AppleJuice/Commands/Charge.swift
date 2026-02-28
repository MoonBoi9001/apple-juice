import ArgumentParser
import Foundation

struct Charge: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "charge",
        abstract: "Charge battery to a target percentage"
    )

    @Argument(help: "Target percentage (1-100) or 'stop'")
    var target: String

    func run() throws {
        // Kill existing charge processes
        killProcesses(matching: "apple-juice charge")

        if target == "stop" {
            return
        }

        guard let targetPct = Int(target), targetPct >= 1, targetPct <= 100 else {
            log("Error: \(target) is not a valid setting for charge. Please use a number between 1 and 100")
            throw ExitCode.failure
        }

        // Kill running discharge processes
        killProcesses(matching: "apple-juice discharge")

        // Save and suspend maintain
        let originalMaintainStatus = ProcessHelper.readPidFileStatus(Paths.pidFile)
        let binaryPath = CommandLine.arguments[0]
        ProcessRunner.run(binaryPath, arguments: ["maintain", "suspend"])

        // Setup SMC
        let smcClient = SMCBinaryClient()
        let caps = SMCCapabilities.probe(using: smcClient)
        let controller = ChargingController(client: smcClient, caps: caps)

        let batteryPct = getBatteryPercentage(using: smcClient)
        log("Charging to \(targetPct)% from \(batteryPct)%")
        controller.enableCharging()
        controller.changeMagSafeLED(.orange)

        signal(SIGTERM, SIG_IGN)
        let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        sigSource.setEventHandler {
            controller.enableCharging()
            controller.changeMagSafeLED(.auto)
            if originalMaintainStatus == "active" && !ProcessHelper.calibrateIsRunning() {
                ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
            }
            Darwin.exit(1)
        }
        sigSource.resume()

        // Charge loop
        var prevPct = batteryPct
        var errorCount = 0
        var chargeError = false

        while true {
            let battery = BatteryInfo()
            let accuratePct = Double(battery.accuratePercentage) ?? 0
            if accuratePct >= Double(targetPct) { break }

            let currentPct = getBatteryPercentage(using: smcClient)
            if currentPct != prevPct {
                log("Battery at \(currentPct)% (target \(targetPct)%)")
                prevPct = currentPct
            }

            let nearTarget = currentPct >= targetPct - 3
            let maxErrors = nearTarget ? 36 : 3
            if errorCount > maxErrors {
                chargeError = true
                break
            }

            let sleepTime: UInt32 = nearTarget ? 5 : 60
            preventSleepAndWait(seconds: sleepTime)

            let chbi = smcClient.readDecimal(.CHBI) ?? 0
            if chbi == 0 {
                errorCount += 1
            } else {
                errorCount = 0
            }
        }

        // Finalize
        let isCalibrating = ProcessHelper.calibrateIsRunning()
        if !isCalibrating || targetPct != 100 {
            controller.disableCharging()
        }

        Thread.sleep(forTimeInterval: 5)
        controller.changeMagSafeLED(.auto)

        let finalPct = getBatteryPercentage(using: smcClient)
        if !chargeError {
            log("Charging completed at \(finalPct)%")
            if !isCalibrating && originalMaintainStatus == "active" {
                ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
            }
        } else {
            log("Error: charge abnormal")
            if !isCalibrating && originalMaintainStatus == "active" {
                ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
            }
            throw ExitCode.failure
        }
    }
}

struct Discharge: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "discharge",
        abstract: "Discharge battery to a target percentage"
    )

    @Argument(help: "Target percentage (1-100) or 'stop'")
    var target: String

    func run() throws {
        // Kill existing discharge processes
        killProcesses(matching: "apple-juice discharge")

        if target == "stop" {
            return
        }

        guard let targetPct = Int(target), targetPct >= 1, targetPct <= 100 else {
            log("Error: \(target) is not a valid setting for discharge. Please use a number between 1 and 100")
            throw ExitCode.failure
        }

        // Check lid
        if BatteryInfo.isLidClosed {
            log("Error: macbook lid must be open before discharge")
            throw ExitCode.failure
        }

        // Kill running charge processes
        killProcesses(matching: "apple-juice charge")

        // Save and suspend maintain
        let originalMaintainStatus = ProcessHelper.readPidFileStatus(Paths.pidFile)
        let binaryPath = CommandLine.arguments[0]
        ProcessRunner.run(binaryPath, arguments: ["maintain", "suspend"])

        // Setup SMC
        let smcClient = SMCBinaryClient()
        let caps = SMCCapabilities.probe(using: smcClient)
        let controller = ChargingController(client: smcClient, caps: caps)

        let batteryPct = getBatteryPercentage(using: smcClient)
        log("Discharging to \(targetPct)% from \(batteryPct)%")
        controller.enableDischarging()
        controller.changeMagSafeLED(.none)

        signal(SIGTERM, SIG_IGN)
        let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        sigSource.setEventHandler {
            controller.disableDischarging()
            controller.changeMagSafeLED(.auto)
            if originalMaintainStatus == "active" && !ProcessHelper.calibrateIsRunning() {
                ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
            }
            Darwin.exit(1)
        }
        sigSource.resume()

        // Discharge loop
        var prevPct = batteryPct
        var errorCount = 0
        var dischargeError = false

        while true {
            let currentBattery = BatteryInfo()
            let accuratePct = Double(currentBattery.accuratePercentage) ?? 0
            if accuratePct <= Double(targetPct) { break }

            let currentPct = getBatteryPercentage(using: smcClient)
            if currentPct != prevPct {
                log("Battery at \(currentPct)% (target \(targetPct)%)")
                prevPct = currentPct
            }

            preventSleepAndWait(seconds: 60)

            let chbi = smcClient.readDecimal(.CHBI) ?? 0
            let b0ac = smcClient.readDecimal(.B0AC) ?? 0

            if b0ac == 0 || chbi > 0 {
                errorCount += 1
                if errorCount > 3 {
                    dischargeError = true
                    break
                }
            } else {
                errorCount = 0
            }
        }

        controller.disableDischarging()
        Thread.sleep(forTimeInterval: 5)
        controller.changeMagSafeLED(.auto)

        let finalPct = getBatteryPercentage(using: smcClient)
        if !dischargeError {
            log("Discharging completed at \(finalPct)%")
            if !ProcessHelper.calibrateIsRunning() && originalMaintainStatus == "active" {
                ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
            }
        } else {
            log("Error: discharge abnormal")
            if !ProcessHelper.calibrateIsRunning() && originalMaintainStatus == "active" {
                ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
            }
            throw ExitCode.failure
        }
    }
}

// MARK: - Helpers

/// Get integer battery percentage from BRSC SMC key.
func getBatteryPercentage(using client: SMCClientProtocol) -> Int {
    guard let raw = client.readDecimal(.BRSC) else { return 0 }
    return raw > 100 ? raw / 256 : raw
}

/// Get maintain upper limit from config.
func getMaintainUpperLimit() -> Int {
    let config = ConfigStore()
    guard let mp = config.maintainPercentage else { return 100 }
    let parts = mp.split(separator: " ")
    return Int(parts.first ?? "") ?? 100
}

/// Kill processes matching a pattern (validated PID + apple-juice check).
func killProcesses(matching pattern: String) {
    let myPid = getpid()
    let result = ProcessRunner.shell("pgrep -f '\(pattern)'")
    let pids = result.stdout.split(separator: "\n")
    for pidStr in pids {
        guard let pid = pid_t(pidStr.trimmingCharacters(in: .whitespaces)),
              pid != myPid else { continue }
        // Verify it's an apple-juice process
        let check = ProcessRunner.shell("ps -p \(pid) -o args= 2>/dev/null")
        if check.stdout.contains("apple-juice") {
            kill(pid, SIGTERM)
        }
    }
}

/// Prevent sleep and wait for a duration using IOPMAssertion.
func preventSleepAndWait(seconds: UInt32) {
    PowerManager.preventSleepFor(seconds: seconds)
}
