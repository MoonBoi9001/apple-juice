import Foundation

/// Result of running an external process.
struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

/// Runs external commands and captures output.
enum ProcessRunner {
    /// Run a command with arguments and return the result.
    @discardableResult
    static func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        // Handle timeout
        if let timeout {
            let deadline = DispatchTime.now() + timeout
            let processGroup = DispatchGroup()
            let pipeGroup = DispatchGroup()
            nonisolated(unsafe) var stdoutData = Data()
            nonisolated(unsafe) var stderrData = Data()

            pipeGroup.enter()
            DispatchQueue.global().async {
                stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                pipeGroup.leave()
            }
            pipeGroup.enter()
            DispatchQueue.global().async {
                stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                pipeGroup.leave()
            }
            processGroup.enter()
            DispatchQueue.global().async {
                process.waitUntilExit()
                processGroup.leave()
            }

            if processGroup.wait(timeout: deadline) == .timedOut {
                process.terminate()
                pipeGroup.wait()
                return ProcessResult(exitCode: -1, stdout: "", stderr: "Process timed out")
            }
            pipeGroup.wait()
            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? "")
        } else {
            // Read pipes before waiting to prevent deadlock: if the child fills
            // the pipe buffer (64KB), waitUntilExit blocks forever.
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
        }
    }

    /// Run a command via /bin/bash -c.
    @discardableResult
    static func shell(_ command: String, timeout: TimeInterval? = nil) -> ProcessResult {
        run("/bin/bash", arguments: ["-c", command], timeout: timeout)
    }

    /// Run smc binary with arguments.
    @discardableResult
    static func smc(_ arguments: String...) -> ProcessResult {
        run(Paths.smcPath, arguments: Array(arguments))
    }

    /// Run smc binary with sudo.
    @discardableResult
    static func sudoSMC(_ arguments: String...) -> ProcessResult {
        run("/usr/bin/sudo", arguments: [Paths.smcPath] + arguments)
    }
}
