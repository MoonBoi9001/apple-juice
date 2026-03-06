import Foundation

/// Manages LaunchAgent plists for the maintain daemon and schedule.
enum DaemonManager {
    private static let uid = String(getuid())

    /// Run a shell command and log its stderr on failure.
    @discardableResult
    private static func launchctl(_ command: String, silent: Bool = false) -> ProcessResult {
        let result = ProcessRunner.shell(command)
        if !silent && !result.succeeded
            && !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            log("launchctl: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return result
    }

    // MARK: - Maintain daemon

    /// Generate and install the maintain LaunchAgent plist (and the safety watchdog).
    static func createDaemon() {
        createSafetyDaemon()
        let binaryPath = Paths.smcPath.replacingOccurrences(of: "/smc", with: "/apple-juice")

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.apple-juice.app</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(binaryPath)</string>
                    <string>maintain-daemon</string>
                    <string>recover</string>
                </array>
                <key>StandardOutPath</key>
                <string>\(Paths.logFile)</string>
                <key>StandardErrorPath</key>
                <string>\(Paths.logFile)</string>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <dict>
                    <key>SuccessfulExit</key>
                    <false/>
                </dict>
                <key>ProcessType</key>
                <string>Interactive</string>
                <key>ExitTimeOut</key>
                <integer>30</integer>
            </dict>
        </plist>
        """

        let path = Paths.daemonPath
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Check if existing plist is different
        if let existing = try? String(contentsOfFile: path, encoding: .utf8) {
            let existingTrimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            let newTrimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
            if existingTrimmed == newTrimmed {
                return
            }
        }

        try? plist.write(toFile: path, atomically: true, encoding: .utf8)

        // Enable daemon
        launchctl("launchctl enable gui/\(uid)/com.apple-juice.app")
    }

    /// Start the maintain daemon via launchctl bootstrap + kickstart.
    static func startDaemon() {
        launchctl("launchctl bootout gui/\(uid)/com.apple-juice.app", silent: true)
        Thread.sleep(forTimeInterval: 0.5)
        launchctl("launchctl enable gui/\(uid)/com.apple-juice.app")
        if FileManager.default.fileExists(atPath: Paths.daemonPath) {
            let result = launchctl("launchctl bootstrap gui/\(uid) '\(Paths.daemonPath)'")
            if !result.succeeded {
                Thread.sleep(forTimeInterval: 1)
                launchctl("launchctl bootstrap gui/\(uid) '\(Paths.daemonPath)'")
            }
        }
        launchctl("launchctl kickstart gui/\(uid)/com.apple-juice.app")
    }

    /// Stop and unload the maintain daemon.
    static func stopDaemon() {
        launchctl("launchctl bootout gui/\(uid)/com.apple-juice.app", silent: true)
    }

    /// Disable the maintain daemon (prevent future loads).
    static func disableDaemon() {
        launchctl("launchctl disable gui/\(uid)/com.apple-juice.app")
    }

    /// Remove the maintain daemon plist.
    static func removeDaemon() {
        try? FileManager.default.removeItem(atPath: Paths.daemonPath)
    }

    // MARK: - Safety watchdog daemon

    /// Generate and install the safety watchdog LaunchAgent plist.
    /// Runs `safety-check` every 30 minutes to catch orphaned charging states.
    /// Independent of the maintain daemon -- not removed by `maintain stop`.
    static func createSafetyDaemon() {
        let binaryPath = Paths.smcPath.replacingOccurrences(of: "/smc", with: "/apple-juice")

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.apple-juice.safety</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(binaryPath)</string>
                    <string>safety-check</string>
                </array>
                <key>StartCalendarInterval</key>
                <array>
                    <dict>
                        <key>Minute</key>
                        <integer>0</integer>
                    </dict>
                    <dict>
                        <key>Minute</key>
                        <integer>30</integer>
                    </dict>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
        </plist>
        """

        let path = Paths.safetyDaemonPath
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Only rewrite the plist if content has changed
        let needsWrite: Bool
        if let existing = try? String(contentsOfFile: path, encoding: .utf8) {
            let existingTrimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            let newTrimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
            needsWrite = existingTrimmed != newTrimmed
        } else {
            needsWrite = true
        }

        if needsWrite {
            try? plist.write(toFile: path, atomically: true, encoding: .utf8)
        }

        // Always run launchctl calls -- the plist being on disk doesn't mean
        // the service is loaded in launchd.
        launchctl("launchctl enable gui/\(uid)/com.apple-juice.safety")
        launchctl("launchctl bootout gui/\(uid)/com.apple-juice.safety", silent: true)
        Thread.sleep(forTimeInterval: 0.5)
        let result = launchctl("launchctl bootstrap gui/\(uid) '\(path)'")
        if !result.succeeded {
            Thread.sleep(forTimeInterval: 1)
            launchctl("launchctl bootstrap gui/\(uid) '\(path)'")
        }
        // No kickstart -- let StartCalendarInterval handle timing.
        // Kickstarting here races with daemon startup since createSafetyDaemon()
        // is called from createDaemon() just before startDaemon().
    }

    /// Remove the safety watchdog plist and unload it. Only called during uninstall.
    static func removeSafetyDaemon() {
        launchctl("launchctl disable gui/\(uid)/com.apple-juice.safety")
        launchctl("launchctl bootout gui/\(uid)/com.apple-juice.safety", silent: true)
        try? FileManager.default.removeItem(atPath: Paths.safetyDaemonPath)
    }

    // MARK: - Schedule daemon

    /// Generate the schedule LaunchAgent plist with StartCalendarInterval.
    static func createScheduleDaemon(calendarIntervals: [[String: Any]]) {
        let binaryPath = Paths.smcPath.replacingOccurrences(of: "/smc", with: "/apple-juice")

        var intervalsXML = ""
        for interval in calendarIntervals {
            intervalsXML += "            <dict>\n"
            for (key, value) in interval.sorted(by: { $0.key < $1.key }) {
                intervalsXML += "                <key>\(key)</key>\n"
                intervalsXML += "                <integer>\(value)</integer>\n"
            }
            intervalsXML += "            </dict>\n"
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.apple-juice_schedule.app</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(binaryPath)</string>
                    <string>calibrate</string>
                </array>
                <key>StartCalendarInterval</key>
                <array>
        \(intervalsXML)        </array>
            </dict>
        </plist>
        """

        let path = Paths.schedulePath
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try? plist.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Remove the schedule daemon plist.
    static func removeScheduleDaemon() {
        try? FileManager.default.removeItem(atPath: Paths.schedulePath)
    }

    /// Enable the schedule daemon.
    static func enableScheduleDaemon() {
        launchctl("launchctl enable gui/\(uid)/com.apple-juice_schedule.app")
        // Bootstrap if not loaded
        if FileManager.default.fileExists(atPath: Paths.schedulePath) {
            launchctl("launchctl bootstrap gui/\(uid) '\(Paths.schedulePath)'")
        }
    }

    /// Disable the schedule daemon.
    static func disableScheduleDaemon() {
        launchctl("launchctl disable gui/\(uid)/com.apple-juice_schedule.app")
        launchctl("launchctl bootout gui/\(uid)/com.apple-juice_schedule.app", silent: true)
    }
}
