import ArgumentParser
import Foundation

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Uninstall apple-juice and re-enable charging"
    )

    func run() throws {
        print("This will enable charging, and remove the smc tool and apple-juice")
        print("Press any key to continue")
        _ = readLine()

        let smcClient = SMCBinaryClient()
        let caps = SMCCapabilities.probe(using: smcClient)
        let controller = ChargingController(client: smcClient, caps: caps)

        controller.enableCharging()
        controller.disableDischarging()

        // Verify charging was actually re-enabled before deleting binaries
        let chargingStatus = getSMCChargingStatus(using: smcClient, caps: caps)
        if chargingStatus == "disabled" {
            print("Warning: could not verify charging is re-enabled.")
            print("This can happen if the smc binary is missing or sudo was denied.")
            print("Please reboot your Mac to restore normal charging, then retry uninstall.")
            print("SMC charging keys reset on reboot -- your laptop WILL charge after restarting.")
            throw ExitCode.failure
        }

        // Stop and unload LaunchAgents before removing plists
        DaemonManager.stopDaemon()
        DaemonManager.disableDaemon()
        DaemonManager.removeDaemon()
        DaemonManager.disableScheduleDaemon()
        DaemonManager.removeScheduleDaemon()
        DaemonManager.removeSafetyDaemon()

        try? FileManager.default.removeItem(atPath: Paths.shutdownPath)

        // Remove binaries
        let binfolder = Paths.binfolder
        ProcessRunner.shell("sudo rm -v '\(binfolder)/smc' '\(binfolder)/apple-juice' '\(Paths.visudoFile)' '\(binfolder)/shutdown.sh' 2>/dev/null")

        // Remove config folder
        ProcessRunner.shell("sudo rm -v -r '\(Paths.configFolder)' 2>/dev/null")

        // Remove sleepwatcher hooks
        let home = NSHomeDirectory()
        ProcessRunner.shell("sudo rm -rf '\(home)/.sleep' '\(home)/.wakeup' '\(home)/.shutdown' '\(home)/.reboot' 2>/dev/null")

        // Kill remaining apple-juice processes (excluding ourselves)
        let myPid = getpid()
        func killRemainingProcesses(signal: Int32) {
            let result = ProcessRunner.shell("pgrep -f 'apple-juice '")
            for pidStr in result.stdout.split(separator: "\n") {
                guard let pid = pid_t(pidStr.trimmingCharacters(in: .whitespaces)),
                      pid != myPid else { continue }
                kill(pid, signal)
            }
        }
        killRemainingProcesses(signal: SIGTERM)
        Thread.sleep(forTimeInterval: 1)
        killRemainingProcesses(signal: SIGKILL)

        print("apple-juice has been uninstalled")
    }
}
