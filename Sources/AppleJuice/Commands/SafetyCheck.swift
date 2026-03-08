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

        if ProcessHelper.maintainIsRunning() {
            // Daemon process is alive. Check for a hung loop by comparing PID
            // file staleness against system uptime (not wall clock). System
            // uptime doesn't advance during sleep, so the PID file won't
            // appear stale just because the Mac was asleep.
            if let attrs = try? FileManager.default.attributesOfItem(atPath: Paths.pidFile),
               let modified = attrs[.modificationDate] as? Date {
                let wallElapsed = Date().timeIntervalSince(modified)
                let uptime = ProcessInfo.processInfo.systemUptime
                // How long the system has been awake since the PID file was
                // last written. Approximate: if the file was modified before
                // the last sleep, awakeElapsed clamps to uptime (i.e. the
                // full duration since the most recent boot/wake).
                let awakeElapsed = min(wallElapsed, uptime)
                if awakeElapsed > 120 {
                    log("Safety watchdog: daemon PID file is stale (>2 min awake time). Killing for restart.")
                    if let pid = ProcessHelper.readPid(Paths.pidFile) {
                        kill(pid, SIGKILL)
                    }
                    // KeepAlive (SuccessfulExit: false) will restart the daemon.
                    // Don't re-enable charging here -- the restarted daemon will
                    // set the correct state.
                }
            }
            return
        }

        // Calibrate may legitimately disable charging -- don't interfere
        guard !ProcessHelper.calibrateIsRunning() else { return }

        let smcClient = SMCBinaryClient()
        let caps = SMCCapabilities.probe(using: smcClient)
        let status = getSMCChargingStatus(using: smcClient, caps: caps)

        guard status == "disabled" else { return }

        // Try to restart the daemon if the plist exists
        if FileManager.default.fileExists(atPath: Paths.daemonPath) {
            log("Safety watchdog: charging disabled, daemon not running. Attempting restart.")
            DaemonManager.startDaemon()

            Thread.sleep(forTimeInterval: 2)

            if ProcessHelper.maintainIsRunning() {
                log("Safety watchdog: daemon restarted successfully.")
                return
            }
        }

        // Fallback: re-enable charging so the Mac doesn't sit unchargeable
        log("Safety watchdog: could not restart daemon. Re-enabling charging.")
        ChargingController(client: smcClient, caps: caps).enableCharging()
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
