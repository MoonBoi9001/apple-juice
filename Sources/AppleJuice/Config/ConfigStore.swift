import Foundation

/// File-per-key configuration store.
///
/// Each config key is stored as an individual file under `~/.apple-juice/`.
/// Reading returns the file contents (trimmed). Writing an empty or nil value
/// deletes the file. This matches the bash implementation exactly.
struct ConfigStore {
    let folder: String

    init(folder: String = Paths.configFolder) {
        self.folder = folder
    }

    /// Ensure the config directory exists.
    func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            atPath: folder, withIntermediateDirectories: true)
    }

    /// Read a config value. Returns nil if the file doesn't exist or is empty.
    func read(_ key: String) -> String? {
        let path = (folder as NSString).appendingPathComponent(key)
        guard let data = FileManager.default.contents(atPath: path),
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Write a config value. Empty or nil deletes the file.
    func write(_ key: String, value: String?) throws {
        let path = (folder as NSString).appendingPathComponent(key)

        guard let value, !value.isEmpty else {
            try? FileManager.default.removeItem(atPath: path)
            return
        }

        try ensureDirectory()
        try value.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Delete a config key.
    func delete(_ key: String) {
        let path = (folder as NSString).appendingPathComponent(key)
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Check if a config key exists.
    func exists(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent(key))
    }
}

// MARK: - Known config keys

extension ConfigStore {
    var maintainPercentage: String? { read("maintain_percentage") }
    var calibrateMethod: String? { read("calibrate_method") }
    var calibrateSchedule: String? { read("calibrate_schedule") }
    var calibrateNext: String? { read("calibrate_next") }
    var informedVersion: String? { read("informed_version") }
    var dailyLast: String? { read("daily_last") }
    var clamshellDischarge: String? { read("clamshell_discharge") }
    var webhookId: String? { read("webhookid") }
    var haURL: String? { read("ha_url") }
    var longevityMode: String? { read("longevity_mode") }
}
