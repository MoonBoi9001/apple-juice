import ArgumentParser
import Foundation

struct Changelog: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "changelog",
        abstract: "Show the changelog of the latest version"
    )

    func run() throws {
        let result = ProcessRunner.shell("curl -sSLf --max-time 10 '\(Paths.githubLink)/CHANGELOG.md'")
        guard result.succeeded else {
            log("Error: Failed to fetch changelog")
            throw ExitCode.failure
        }
        print(result.stdout)
    }
}
