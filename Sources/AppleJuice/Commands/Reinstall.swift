import ArgumentParser
import Foundation

struct Reinstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reinstall",
        abstract: "Reinstall apple-juice from GitHub"
    )

    func run() throws {
        let tmpFile = ProcessRunner.shell("mktemp").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        print("Downloading update script to \(tmpFile)...")
        let download = ProcessRunner.shell("curl -sSL --max-time 30 '\(Paths.githubLink)/update.sh' -o '\(tmpFile)'")
        guard download.succeeded else {
            print("Error: Failed to download setup script")
            throw ExitCode.failure
        }

        print("Review the script at \(tmpFile) before proceeding, or press Enter to continue")
        _ = readLine()

        ProcessRunner.shell("bash '\(tmpFile)'")
    }
}
