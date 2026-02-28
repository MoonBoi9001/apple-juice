import Foundation

/// Schedules and cancels macOS wake events via `pmset` for charging control during sleep.
///
/// When the daemon detects the Mac is going to sleep with the battery below the maintain target,
/// it estimates when charging will reach the target and schedules a brief wake. On wake, the
/// daemon disables charging and the Mac returns to idle sleep.
enum WakeScheduler {
    /// The date string of the currently scheduled wake (pmset format), if any.
    nonisolated(unsafe) private(set) static var scheduledWakeDate: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Schedule the Mac to wake at a specific date.
    /// Cancels any existing scheduled wake first.
    static func scheduleWake(at date: Date) {
        cancelWake()

        let dateString = dateFormatter.string(from: date)
        let result = ProcessRunner.run(
            "/usr/bin/sudo",
            arguments: ["/usr/bin/pmset", "schedule", "wake", dateString],
            timeout: 10)

        if result.succeeded {
            scheduledWakeDate = dateString
            log("Scheduled wake at \(dateString) for charging check")
        } else {
            log("Warning: failed to schedule wake: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    /// Cancel any previously scheduled wake.
    static func cancelWake() {
        guard let dateString = scheduledWakeDate else { return }

        ProcessRunner.run(
            "/usr/bin/sudo",
            arguments: ["/usr/bin/pmset", "schedule", "cancel", "wake", dateString],
            timeout: 10)

        scheduledWakeDate = nil
    }

    /// Estimate seconds until the battery reaches `targetPercent` from `currentPercent`.
    ///
    /// Uses `AvgTimeToFull` from IOKit (OS-computed, accounts for CC-CV curve) scaled
    /// proportionally to the partial charge needed. Falls back to `InstantAmperage` with
    /// raw capacity for a manual calculation.
    ///
    /// Returns nil if not charging or data is unavailable. Subtracts a 5-minute safety
    /// margin and enforces a 10-minute minimum.
    static func estimateTimeToTarget(currentPercent: Int, targetPercent: Int) -> TimeInterval? {
        guard currentPercent < targetPercent else { return nil }

        let battery = BatteryInfo()
        let gap = targetPercent - currentPercent
        let fullGap = 100 - currentPercent

        // Primary: scale AvgTimeToFull proportionally
        if let avgMinutes = battery.avgTimeToFull, avgMinutes > 0, fullGap > 0 {
            let scaledMinutes = Double(avgMinutes) * Double(gap) / Double(fullGap)
            let seconds = max((scaledMinutes - 5) * 60, 600)
            return seconds
        }

        // Fallback: InstantAmperage + raw capacity
        if let amperage = battery.instantAmperage, amperage > 0,
           let maxCap = battery.rawMaxCapacity, maxCap > 0,
           let currentCap = battery.rawCurrentCapacity {
            let targetCap = Double(targetPercent) * Double(maxCap) / 100.0
            let remaining = targetCap - Double(currentCap)
            guard remaining > 0 else { return nil }
            let hours = remaining / Double(amperage)
            let seconds = max((hours * 3600) - 300, 600)
            return seconds
        }

        return nil
    }
}
