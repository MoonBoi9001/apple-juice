import Foundation

/// Migrates old configuration formats and cleans up deprecated files.
enum Migration {
    /// Run all migrations.
    static func runAll() {
        migrateOldConfigFile()
        migrateConfigKeys()
        cleanupDeprecated()
        regenerateLaunchAgentIfNeeded()
    }

    /// Migrate old single-file config to file-per-key format.
    /// Matches bash `migrate_config()`.
    static func migrateOldConfigFile() {
        let configFolder = Paths.configFolder
        let oldConfig = (configFolder as NSString).appendingPathComponent("config")

        guard FileManager.default.fileExists(atPath: oldConfig) else { return }
        guard let contents = try? String(contentsOfFile: oldConfig, encoding: .utf8) else { return }

        let store = ConfigStore()

        for line in contents.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            // Parse "key = value" format
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let val = parts[1].trimmingCharacters(in: .whitespaces)
                try? store.write(key, value: val)
            } else {
                // Try "key value" format (space-separated as in bash IFS)
                let spaceParts = trimmed.split(separator: " ", maxSplits: 1)
                if spaceParts.count == 2 {
                    let key = String(spaceParts[0])
                    let val = String(spaceParts[1])
                    try? store.write(key, value: val)
                }
            }
        }

        // Rename old config
        try? FileManager.default.moveItem(atPath: oldConfig, toPath: oldConfig + ".migrated")
    }

    /// Migrate old config key names to new format.
    static func migrateConfigKeys() {
        let store = ConfigStore()
        let renames: [(String, String)] = [
            ("informed.version", "informed_version"),
            ("maintain.percentage", "maintain_percentage"),
            ("ha_webhook.id", "webhookid"),
        ]

        for (oldKey, newKey) in renames {
            if let val = store.read(oldKey), store.read(newKey) == nil {
                try? store.write(newKey, value: val)
                store.delete(oldKey)
            }
        }

        // Clean up deprecated keys
        let deprecated = ["sig", "state", "language.code", "language"]
        for key in deprecated {
            store.delete(key)
        }
    }

    /// Clean up deprecated sleepwatcher files.
    static func cleanupDeprecated() {
        let home = NSHomeDirectory()
        let sleepwatcherFiles = [".sleep", ".wakeup", ".shutdown", ".reboot"]
        let fm = FileManager.default

        for file in sleepwatcherFiles {
            let path = (home as NSString).appendingPathComponent(file)
            if fm.fileExists(atPath: path) {
                // Check if it's a sleepwatcher/apple-juice hook
                if let contents = try? String(contentsOfFile: path, encoding: .utf8),
                   contents.contains("apple-juice") || contents.contains(".battery") {
                    try? fm.removeItem(atPath: path)
                }
            }
        }
    }

    /// Regenerate the LaunchAgent plist if it exists but lacks KeepAlive.
    /// Users upgrading from v1.x have an old plist without crash recovery.
    static func regenerateLaunchAgentIfNeeded() {
        let plistPath = Paths.daemonPath
        guard FileManager.default.fileExists(atPath: plistPath) else { return }
        guard let contents = try? String(contentsOfFile: plistPath, encoding: .utf8) else { return }

        if !contents.contains("SuccessfulExit") {
            DaemonManager.createDaemon()
        }
    }

    /// Startup recovery: if charging is disabled but maintain is not running, re-enable charging.
    /// Matches bash lines 1261-1269.
    static func startupRecoveryCheck() {
        guard !ProcessHelper.maintainIsRunning() else { return }

        let smcClient = SMCBinaryClient()
        let caps = SMCCapabilities.probe(using: smcClient)
        let chargingStatus = getSMCChargingStatus(using: smcClient, caps: caps)

        if chargingStatus == "disabled" {
            log("Safety: charging was disabled but maintain is not running. Re-enabling charging.")
            ChargingController(client: smcClient, caps: caps).enableCharging()
        }
    }
}
