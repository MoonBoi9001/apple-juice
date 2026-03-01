import ArgumentParser
import Foundation

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Check for and install updates"
    )

    @Argument(help: "Optional: 'force' or 'beta <branch>'")
    var args: [String] = []

    func run() throws {
        let isForce = args.contains("force")
        let isBeta = args.first == "beta"

        if isBeta, args.count > 1 {
            // Beta: download update.sh from specified branch
            let branch = args[1]
            let githubLink = "https://raw.githubusercontent.com/MoonBoi9001/apple-juice/refs/heads/\(branch)"

            let tmpFile = ProcessRunner.shell("mktemp").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            defer { try? FileManager.default.removeItem(atPath: tmpFile) }

            let downloadResult = ProcessRunner.shell("curl -sSL --max-time 30 '\(githubLink)/update.sh' -o '\(tmpFile)'")
            guard downloadResult.succeeded else {
                log("Error: Failed to download update script from branch \(branch)")
                throw ExitCode.failure
            }
            ProcessRunner.shell("bash '\(tmpFile)'")
            return
        }

        // Check latest release version via GitHub API
        let apiResult = ProcessRunner.shell(
            "curl -sSL --max-time 10 'https://api.github.com/repos/MoonBoi9001/apple-juice/releases/latest'"
        )
        guard apiResult.succeeded else {
            log("Error: Failed to check for updates")
            throw ExitCode.failure
        }

        let versionNew = parseTagName(apiResult.stdout)

        if versionNew.isEmpty {
            log("Error: Could not determine latest version")
            throw ExitCode.failure
        }

        if versionNew == "v\(appVersion)" && !isForce {
            Notifications.displayDialog(
                message: "Your version v\(appVersion) is already the latest. No need to update.",
                buttons: ["OK"],
                timeout: 60)
            return
        }

        // Fetch changelog
        let changelogResult = ProcessRunner.shell(
            "curl -sSLf --max-time 10 '\(Paths.githubLink)/CHANGELOG.md'"
        )
        let changelog = parseChangelog(changelogResult.stdout)
        let latestVersion = parseLatestVersion(changelogResult.stdout)

        let displayVersion = latestVersion.isEmpty ? versionNew : latestVersion

        Notifications.displayDialog(
            message: "\(displayVersion) changes include\n\n\(changelog)",
            buttons: ["Continue"],
            timeout: nil)

        let answer = Notifications.displayDialog(
            message: "Do you want to update to version \(displayVersion) now?",
            buttons: ["Yes", "No"])

        if answer == "Yes" {
            let tmpFile = ProcessRunner.shell("mktemp").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            defer { try? FileManager.default.removeItem(atPath: tmpFile) }

            let downloadResult = ProcessRunner.shell(
                "curl -sSL --max-time 30 '\(Paths.githubLink)/update.sh' -o '\(tmpFile)'"
            )
            if downloadResult.succeeded {
                ProcessRunner.shell("bash '\(tmpFile)'")
            } else {
                print("Error: Failed to download update script")
            }
        }
    }

    /// Extract tag_name from GitHub API JSON response.
    private func parseTagName(_ json: String) -> String {
        // Simple extraction: find "tag_name": "vX.Y.Z"
        guard let range = json.range(of: #""tag_name"\s*:\s*"([^"]+)""#, options: .regularExpression) else {
            return ""
        }
        let match = json[range]
        // Extract the value between the last pair of quotes
        if let valueStart = match.range(of: #":\s*""#, options: .regularExpression)?.upperBound,
           let valueEnd = match[valueStart...].firstIndex(of: "\"") {
            return String(match[valueStart..<valueEnd])
        }
        return ""
    }

    /// Parse the changelog to show only the latest version's changes.
    private func parseChangelog(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var foundFirst = false

        for line in lines {
            if isVersionLine(line) {
                if foundFirst { break }
                foundFirst = true
                continue
            }
            if foundFirst {
                result.append(line)
            }
        }

        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get the latest version string from changelog (e.g., "v2.0.0" from "## v2.0.0").
    private func parseLatestVersion(_ text: String) -> String {
        for line in text.components(separatedBy: "\n") {
            if isVersionLine(line) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return trimmed
            }
        }
        return ""
    }

    /// Check if a line looks like a version header (e.g., "## v1.0.2").
    private func isVersionLine(_ line: String) -> Bool {
        let cleaned = line.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard cleaned.hasPrefix("v"), cleaned.contains(".") else { return false }
        let parts = cleaned.dropFirst().split(separator: ".")
        return parts.count == 3 && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}
