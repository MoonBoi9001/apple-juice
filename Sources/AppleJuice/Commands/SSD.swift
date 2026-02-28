import ArgumentParser
import Foundation

struct SSD: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ssd",
        abstract: "Show SSD health information"
    )

    func run() throws {
        // Check if smartctl is available
        let which = ProcessRunner.shell("which smartctl 2>&1")
        guard which.succeeded, !which.stdout.isEmpty else {
            print("smartctl not found. Install with: brew install smartmontools")
            return
        }

        // Enable SMART
        ProcessRunner.shell("smartctl -s on disk0")

        // Get extended info
        let result = ProcessRunner.shell("smartctl -x disk0")
        let info = result.stdout

        // Detect firmware format
        let firmware: Int
        if info.contains("Data Units Read:") {
            firmware = 1
        } else if info.contains("Logical Sectors Read") {
            firmware = 2
        } else {
            print("SSD SMART data not supported by firmware")
            return
        }

        let fields = parseSSDInfo(info, firmware: firmware)

        print("")
        log("SSD Health Report")
        log("Test result: \(fields.result)")
        log("Data read: \(fields.readUnit), Data written: \(fields.writeUnit)")
        log("Percentage used: \(fields.used)")
        log("Power cycles: \(fields.powerCycles), Power hours: \(fields.powerHours)")
        log("Unsafe shutdowns: \(fields.unsafeShutdowns)")
        log("Temperature: \(fields.temperature)")
        log("Integrity errors: \(fields.errors)")
        print("")
    }

    private struct SSDFields {
        var result = "NA"
        var readUnit = "NA"
        var writeUnit = "NA"
        var used = "NA"
        var powerCycles = "NA"
        var powerHours = "NA"
        var unsafeShutdowns = "NA"
        var temperature = "NA"
        var errors = "NA"
    }

    private func parseSSDInfo(_ info: String, firmware: Int) -> SSDFields {
        var fields = SSDFields()

        if firmware == 1 {
            fields.result = extractField(info, pattern: "test result:", field: 5) ?? "NA"
            fields.readUnit = extractBracketedValue(info, pattern: "Data Units Read:") ?? "NA"
            fields.writeUnit = extractBracketedValue(info, pattern: "Data Units Written:") ?? "NA"
            fields.used = extractField(info, pattern: "Percentage Used:", field: 2) ?? "NA"
            fields.powerCycles = extractField(info, pattern: "Power Cycles:", field: 2) ?? "NA"
            fields.powerHours = extractField(info, pattern: "Power On Hours:", field: 3) ?? "NA"
            fields.unsafeShutdowns = extractField(info, pattern: "Unsafe Shutdowns:", field: 2) ?? "NA"
            if let temp = extractField(info, pattern: "Temperature:", field: 1) {
                fields.temperature = "\(temp)\u{00B0}C"
            }
            fields.errors = extractField(info, pattern: "Media and Data Integrity Errors:", field: 5) ?? "NA"
        } else {
            fields.result = extractField(info, pattern: "test result:", field: 5) ?? "NA"
            if let readMiB = extractField(info, pattern: "Host_Reads_MiB", field: 7),
               let readVal = Double(readMiB) {
                fields.readUnit = String(format: "%.2fTB", readVal / 1048576.0)
            }
            if let writeMiB = extractField(info, pattern: "Host_Writes_MiB", field: 7),
               let writeVal = Double(writeMiB) {
                fields.writeUnit = String(format: "%.2fTB", writeVal / 1048576.0)
            }
            if let used = extractField(info, pattern: "Percentage Used", field: 3) {
                fields.used = "\(used)%"
            }
            fields.powerCycles = extractField(info, pattern: "Power_Cycle_Count", field: 7) ?? "NA"
            fields.powerHours = extractField(info, pattern: "Power_On_Hours", field: 7) ?? "NA"
            fields.unsafeShutdowns = extractField(info, pattern: "Power-Off_Retract_Count", field: 7) ?? "NA"
            if let temp = extractField(info, pattern: "Temperature", field: 7) {
                fields.temperature = "\(temp)\u{00B0}C"
            }
            fields.errors = extractField(info, pattern: "Uncorrectable Errors", field: 3) ?? "NA"
        }

        return fields
    }

    private func extractField(_ text: String, pattern: String, field: Int) -> String? {
        guard let line = text.split(separator: "\n").first(where: { $0.contains(pattern) }) else {
            return nil
        }
        let parts = line.split(whereSeparator: { $0.isWhitespace })
        guard field < parts.count else { return nil }
        return String(parts[field])
    }

    private func extractBracketedValue(_ text: String, pattern: String) -> String? {
        guard let line = text.split(separator: "\n").first(where: { $0.contains(pattern) }) else {
            return nil
        }
        // Extract value between [ and ]
        guard let start = line.range(of: "["), let end = line.range(of: "]") else { return nil }
        return String(line[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
    }
}
