import Foundation
import IOKit
import IOKit.pwr_mgt

/// Manages power assertions and sleep/wake notifications.
enum PowerManager {
    nonisolated(unsafe) private static var assertionID: IOPMAssertionID = 0

    /// Create a power assertion to prevent system sleep.
    /// Returns true if successful.
    @discardableResult
    static func preventSleep(reason: String = "apple-juice battery operation") -> Bool {
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID)
        return result == kIOReturnSuccess
    }

    /// Release the sleep prevention assertion.
    static func allowSleep() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }

    /// Prevent sleep for a duration, then release.
    static func preventSleepFor(seconds: UInt32) {
        preventSleep()
        sleep(seconds)
        allowSleep()
    }
}

// MARK: - Sleep/Wake Listener

/// Listens for system sleep/wake events via IORegisterForSystemPower.
/// Runs a CFRunLoop on a background thread to receive kernel notifications.
final class SleepWakeListener {
    typealias EventHandler = (SleepWakeEvent) -> Void

    enum SleepWakeEvent {
        case willSleep
        case didWake
    }

    private var notificationPort: IONotificationPortRef?
    private var notifierObject: io_object_t = 0
    /// The IOKit root power domain connection -- needs to be accessible from the C callback
    /// to call IOAllowPowerChange.
    fileprivate var powerConnection: io_connect_t = 0
    private let handler: EventHandler
    private var runLoopThread: Thread?
    /// Synchronizes stop() with the IOKit callback to prevent use-after-free.
    fileprivate let lock = NSLock()
    /// Whether stop() has been called. Checked under lock by the callback.
    fileprivate var stopped = false

    init(handler: @escaping EventHandler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// Start listening for sleep/wake events on a background thread.
    func start() {
        runLoopThread = Thread {
            self.registerAndRun()
        }
        runLoopThread?.name = "apple-juice.sleepwake"
        runLoopThread?.start()
    }

    /// Stop listening and clean up.
    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()

        if let thread = runLoopThread {
            thread.cancel()
            runLoopThread = nil
        }
        if notifierObject != 0 {
            IODeregisterForSystemPower(&notifierObject)
            notifierObject = 0
        }
        if powerConnection != 0 {
            IOServiceClose(powerConnection)
            powerConnection = 0
        }
        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
    }

    fileprivate func handleEvent(_ event: SleepWakeEvent) {
        handler(event)
    }

    private func registerAndRun() {
        let refcon = Unmanaged.passRetained(self).toOpaque()

        powerConnection = IORegisterForSystemPower(
            refcon,
            &notificationPort,
            sleepWakeCallback,
            &notifierObject)

        guard powerConnection != 0, let port = notificationPort else {
            log("Warning: Failed to register for sleep/wake notifications")
            Unmanaged<SleepWakeListener>.fromOpaque(refcon).release()
            return
        }

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)

        while !Thread.current.isCancelled {
            CFRunLoopRunInMode(.defaultMode, 1.0, true)
        }

        // Release the retained reference when the run loop exits
        Unmanaged<SleepWakeListener>.fromOpaque(refcon).release()
    }
}

// IOKit message constants -- defined as C macros using iokit_common_msg() which Swift can't
// import directly. sys_iokit = 0xE0000000, sub_iokit_common = 0.
private let kIOMessageCanSystemSleep_: UInt32    = 0xE0000270
private let kIOMessageSystemWillSleep_: UInt32   = 0xE0000280
private let kIOMessageSystemHasPoweredOn_: UInt32 = 0xE0000300

/// C-compatible callback for IORegisterForSystemPower.
private func sleepWakeCallback(
    refcon: UnsafeMutableRawPointer?,
    service: io_service_t,
    messageType: UInt32,
    messageArgument: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }
    let listener = Unmanaged<SleepWakeListener>.fromOpaque(refcon).takeUnretainedValue()

    // Check under lock whether stop() has been called to avoid accessing
    // a zeroed powerConnection.
    listener.lock.lock()
    let isStopped = listener.stopped
    let connection = listener.powerConnection
    listener.lock.unlock()

    guard !isStopped else { return }

    switch messageType {
    case kIOMessageCanSystemSleep_:
        IOAllowPowerChange(connection, Int(bitPattern: messageArgument))

    case kIOMessageSystemWillSleep_:
        listener.handleEvent(.willSleep)
        IOAllowPowerChange(connection, Int(bitPattern: messageArgument))

    case kIOMessageSystemHasPoweredOn_:
        listener.handleEvent(.didWake)

    default:
        break
    }
}
