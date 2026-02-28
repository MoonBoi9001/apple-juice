import ArgumentParser
import Foundation

struct Balance: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "balance",
        abstract: "Perform BMS cell balancing (charge to 100%, hold, return to maintain level)"
    )

    func run() throws {
        let binaryPath = CommandLine.arguments[0]
        try "\(getpid())".write(toFile: Paths.calibratePidFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: Paths.calibratePidFile) }

        guard ProcessHelper.maintainIsRunning() else {
            log("Error: Battery maintain must be running before balance")
            throw ExitCode.failure
        }

        let maintainPct = getMaintainUpperLimit()

        log("Balance: Starting BMS cell balancing")
        log("Balance: Suspending maintain, charging to 100%")

        // Suspend maintain
        ProcessRunner.run(binaryPath, arguments: ["maintain", "suspend"])

        // Charge to 100%
        Webhook.send(stage: "balance_charge100_start", battery: BatteryInfo().accuratePercentage)
        let chargeResult = ProcessRunner.run(binaryPath, arguments: ["charge", "100"])
        if !chargeResult.succeeded {
            log("Balance Error: Charge to 100% failed")
            Webhook.send(stage: "balance_err_charge100")
            ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
            throw ExitCode.failure
        }

        // Hold at 100% for 90 minutes (5400s) for BMS cell balancing
        log("Balance: Holding at 100% for 90 minutes for BMS cell balancing")
        Webhook.send(stage: "balance_hold_start", battery: BatteryInfo().accuratePercentage)
        Notifications.displayNotification(
            message: "Holding at 100% for 90 minutes for cell balancing",
            title: "apple-juice Balance")
        Thread.sleep(forTimeInterval: 5400)

        // Discharge back to maintain level
        log("Balance: Discharging to \(maintainPct)%")
        Webhook.send(stage: "balance_discharge_start", battery: BatteryInfo().accuratePercentage)
        let dischargeResult = ProcessRunner.run(binaryPath, arguments: ["discharge", String(maintainPct)])
        if !dischargeResult.succeeded {
            log("Balance Error: Discharge to \(maintainPct)% failed")
            Webhook.send(stage: "balance_err_discharge")
            ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
            throw ExitCode.failure
        }

        // Recover maintain
        log("Balance: Cell balancing complete")
        Webhook.send(stage: "balance_end", battery: BatteryInfo().accuratePercentage)
        Notifications.displayNotification(
            message: "Cell balancing complete",
            title: "apple-juice Balance")
        ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
    }
}
