import ArgumentParser
import Foundation

let appVersion = "2.0.0"

@main
struct AppleJuice: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apple-juice",
        abstract: "Battery charging manager for macOS",
        version: "apple-juice CLI v\(appVersion)",
        subcommands: [
            Status.self,
            Maintain.self,
            Charge.self,
            Discharge.self,
            Calibrate.self,
            Balance.self,
            Schedule.self,
            Logs.self,
            DailyLog.self,
            CalibrateLog.self,
            SSD.self,
            SSDLog.self,
            Update.self,
            Reinstall.self,
            Uninstall.self,
            Visudo.self,
            Changelog.self,
            SafetyCheck.self,
        ]
    )

    /// Runs before any subcommand. Handles migration and safety recovery.
    static func startup() {
        Migration.runAll()
        Migration.startupRecoveryCheck()
    }
}

/// One-time startup hook. Evaluated lazily on first access.
private let _startup: Void = {
    // Skip recovery check when running as the maintain daemon itself
    let args = CommandLine.arguments
    let isDaemon = args.contains("maintain-daemon")
    if !isDaemon {
        AppleJuice.startup()
    }
}()

/// Wraps any ParsableCommand to inject the startup hook before run().
protocol StartupAware: ParsableCommand {}
extension Status: StartupAware {}
extension Maintain: StartupAware {}
extension Charge: StartupAware {}
extension Discharge: StartupAware {}
extension Calibrate: StartupAware {}
extension Balance: StartupAware {}
extension Schedule: StartupAware {}
extension Update: StartupAware {}
extension Uninstall: StartupAware {}

extension StartupAware {
    mutating func validate() throws {
        _ = _startup
    }
}

// MARK: - Paths

enum Paths {
    static let binfolder: String = {
        // Resolve the actual binary location
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let dir = executableURL.deletingLastPathComponent().path
        let smcPath = (dir as NSString).appendingPathComponent("smc")
        if FileManager.default.isExecutableFile(atPath: smcPath) {
            return dir
        }
        return "/usr/local/co.apple-juice"
    }()

    static let configFolder = (NSHomeDirectory() as NSString).appendingPathComponent(".apple-juice")
    static let pidFile = (configFolder as NSString).appendingPathComponent("apple-juice.pid")
    static let logFile = (configFolder as NSString).appendingPathComponent("apple-juice.log")
    static let sigPidFile = (configFolder as NSString).appendingPathComponent("sig.pid")
    static let calibratePidFile = (configFolder as NSString).appendingPathComponent("calibrate.pid")
    static let dailyLogFile = (configFolder as NSString).appendingPathComponent("daily.log")
    static let calibrateLogFile = (configFolder as NSString).appendingPathComponent("calibrate.log")
    static let ssdLogFile = (configFolder as NSString).appendingPathComponent("ssd.log")

    static let daemonPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/LaunchAgents/apple-juice.plist")
    static let schedulePath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/LaunchAgents/apple-juice_schedule.plist")
    static let shutdownPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/LaunchAgents/apple-juice_shutdown.plist")
    static let safetyDaemonPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/LaunchAgents/apple-juice_safety.plist")

    static let chargeStateFile = (configFolder as NSString).appendingPathComponent("charge.state")

    static let visudoFolder = "/private/etc/sudoers.d"
    static let visudoFile = "/private/etc/sudoers.d/apple-juice"

    static let githubLink = "https://raw.githubusercontent.com/MoonBoi9001/apple-juice/main"

    static let smcPath: String = {
        (binfolder as NSString).appendingPathComponent("smc")
    }()
}
