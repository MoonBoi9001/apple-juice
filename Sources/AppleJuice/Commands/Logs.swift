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

struct DailyLog: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dailylog",
        abstract: "Show the daily battery log"
    )

    func run() throws {
        let path = Paths.dailyLogFile
        if FileManager.default.fileExists(atPath: path) {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            print(contents, terminator: "")
        }
        print("Daily log stored at: \(path)")
    }
}

struct CalibrateLog: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calibratelog",
        abstract: "Show the calibration log"
    )

    func run() throws {
        let path = Paths.calibrateLogFile
        if FileManager.default.fileExists(atPath: path) {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            print(contents, terminator: "")
        } else {
            print("No calibration log found at \(path)")
        }
    }
}

struct SSDLog: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ssdlog",
        abstract: "Show the SSD health log"
    )

    func run() throws {
        let path = Paths.ssdLogFile
        if FileManager.default.fileExists(atPath: path) {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            print(contents, terminator: "")
        } else {
            print("No SSD log found at \(path)")
        }
    }
}
