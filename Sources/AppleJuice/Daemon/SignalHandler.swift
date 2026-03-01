import Foundation

/// Bidirectional SIGUSR1 IPC protocol.
///
/// Caller writes command to `sig.pid` ("PID COMMAND"), sends SIGUSR1 to daemon,
/// daemon reads command, processes it, sends SIGUSR1 back as ACK.
enum SignalCommand: String {
    case suspend
    case suspendNoCharging = "suspend_no_charging"
    case recover
}

/// Manages signal handling for the maintain daemon.
final class SignalHandler {
    private var usr1Source: DispatchSourceSignal?
    private var termSource: DispatchSourceSignal?
    private var intSource: DispatchSourceSignal?

    var onCommand: ((SignalCommand) -> Void)?
    var onTerminate: (() -> Void)?

    init() {
        // Ignore default signal handlers
        signal(SIGUSR1, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
    }

    /// Start listening for signals on a dispatch queue.
    func startListening(on queue: DispatchQueue = .global()) {
        // SIGUSR1 - IPC from command caller
        usr1Source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: queue)
        usr1Source?.setEventHandler { [weak self] in
            self?.handleUSR1()
        }
        usr1Source?.resume()

        // SIGTERM
        termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        termSource?.setEventHandler { [weak self] in
            self?.onTerminate?()
        }
        termSource?.resume()

        // SIGINT
        intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
        intSource?.setEventHandler { [weak self] in
            self?.onTerminate?()
        }
        intSource?.resume()
    }

    /// Stop listening for signals.
    func stopListening() {
        usr1Source?.cancel()
        termSource?.cancel()
        intSource?.cancel()
    }

    private func handleUSR1() {
        // Read command from sig.pid
        guard let contents = try? String(contentsOfFile: Paths.sigPidFile, encoding: .utf8) else { return }
        let parts = contents.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard parts.count >= 2 else { return }

        let callerPid = pid_t(parts[0]) ?? 0
        let commandStr = String(parts[1])

        guard let command = SignalCommand(rawValue: commandStr) else { return }

        // Process the command
        onCommand?(command)

        // Send ACK (SIGUSR1 back to caller)
        if callerPid > 0 {
            kill(callerPid, SIGUSR1)
        }
    }

    // MARK: - Caller side (send command to daemon)

    /// Send a signal command to the running maintain daemon.
    /// Returns true if ACK received within timeout.
    static func sendCommand(_ command: SignalCommand, toDaemon pid: pid_t, timeout: Int = 10) -> Bool {
        // Setup ACK receiver before sending anything to avoid race
        let semaphore = DispatchSemaphore(value: 0)
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .global())
        source.setEventHandler {
            semaphore.signal()
        }
        source.resume()

        // Write command to sig.pid
        let payload = "\(getpid()) \(command.rawValue)"
        try? payload.write(toFile: Paths.sigPidFile, atomically: true, encoding: .utf8)

        // Brief delay for file write to flush before signaling
        Thread.sleep(forTimeInterval: 0.1)

        // Send SIGUSR1 to daemon
        kill(pid, SIGUSR1)

        // Wait for ACK
        let result = semaphore.wait(timeout: .now() + Double(timeout))

        source.cancel()
        return result == .success
    }
}
