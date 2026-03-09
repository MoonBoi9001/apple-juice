import ArgumentParser
import Foundation

struct Logs: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "Show the battery log"
    )

    func run() throws {
        let path = Paths.logFile
        guard FileManager.default.fileExists(atPath: path) else {
            print("No log file found at \(path)")
            return
        }
        let result = ProcessRunner.shell("tail -n 100 '\(path)'")
        print(result.stdout, terminator: "")
    }
}
