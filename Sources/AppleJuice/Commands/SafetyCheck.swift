import ArgumentParser
import Foundation

/// Periodic charging safety watchdog. Runs via a dedicated LaunchAgent every 30 minutes.
/// If the maintain daemon is not running and charging is disabled, re-enables charging.
/// Also detects hung daemons (stale PID file) and orphaned charge/discharge operations.
struct SafetyCheck: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "safety-check",
        abstract: "Internal: periodic charging safety check",
        shouldDisplay: false
    )

    func run() throws {
        // Check for orphaned charge/discharge operations first
        recoverOrphanedChargeState()

        // If the maintain daemon is alive and responsive, nothing to do
        if ProcessHelper.maintainIsRunning() {
            // Also check for a hung daemon: PID file exists but hasn't been updated
            if let attrs = try? FileManager.default.attributesOfItem(atPath: Paths.pidFile),
               let modified = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) > 300 {
                log("Safety watchdog: daemon PID file is stale (>5 min). Re-enabling charging.")
                let smcClient = SMCBinaryClient()
                let caps = SMCCapabilities.probe(using: smcClient)
                ChargingController(client: smcClient, caps: caps).enableCharging()
            }
            return
        }

        // Calibrate may legitimately disable charging -- don't interfere
        guard !ProcessHelper.calibrateIsRunning() else { return }

        let smcClient = SMCBinaryClient()
        let caps = SMCCapabilities.probe(using: smcClient)
        let status = getSMCChargingStatus(using: smcClient, caps: caps)

        if status == "disabled" {
            log("Safety watchdog: charging disabled with no daemon running. Re-enabling.")
            ChargingController(client: smcClient, caps: caps).enableCharging()
        }
    }
}

/// Detect and recover from orphaned charge/discharge state files.
/// Called by both the safety watchdog and the startup recovery check.
func recoverOrphanedChargeState() {
    guard let stateContents = try? String(contentsOfFile: Paths.chargeStateFile, encoding: .utf8) else {
        return
    }

    let parts = stateContents.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
    guard let pid = pid_t(parts.first ?? "") else {
        // Malformed state file -- clean it up
        try? FileManager.default.removeItem(atPath: Paths.chargeStateFile)
        return
    }

    // kill(pid, 0) returns 0 if process exists, -1 if not
    if kill(pid, 0) != 0 {
        log("Safety: orphaned charge/discharge state detected (PID \(pid) dead). Recovering.")
        try? FileManager.default.removeItem(atPath: Paths.chargeStateFile)

        let smcClient = SMCBinaryClient()
        let caps = SMCCapabilities.probe(using: smcClient)
        ChargingController(client: smcClient, caps: caps).enableCharging()

        // Recover maintain if it was active before the orphaned operation
        if parts.count >= 3 && parts[2] == "active" {
            let binaryPath = CommandLine.arguments[0]
            ProcessRunner.run(binaryPath, arguments: ["maintain", "recover"])
        }
    }
}
