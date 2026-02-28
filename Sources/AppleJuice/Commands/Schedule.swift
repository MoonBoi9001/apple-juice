import ArgumentParser
import Foundation

struct Schedule: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Schedule periodic calibration"
    )

    @Argument(parsing: .captureForPassthrough, help: "Schedule parameters")
    var args: [String] = []

    func run() throws {
        let config = ConfigStore()

        // Handle enable/disable
        if args.first == "disable" {
            if config.calibrateSchedule != nil {
                log("Schedule disabled")
                print("")
                DaemonManager.disableScheduleDaemon()
            }
            return
        }

        if args.first == "enable" {
            if config.calibrateSchedule != nil {
                DaemonManager.enableScheduleDaemon()
            }
            showSchedule()
            return
        }

        // Parse schedule parameters
        var days: [Int] = []
        var weekday: Int? = nil
        var weekPeriod = 4
        var monthPeriod = 1
        var hour = 9
        var minute = 0

        var i = 0
        let tokens = args.isEmpty ? ["schedule"] : args
        while i < tokens.count {
            let token = tokens[i]
            switch token {
            case "schedule":
                break // skip the command name
            case "day":
                // Read up to 4 day values after "day"
                for j in 1...4 {
                    let idx = i + j
                    guard idx < tokens.count, let d = Int(tokens[idx]), d >= 1, d <= 28 else {
                        if idx < tokens.count, let d = Int(tokens[idx]), d >= 29, d <= 31 {
                            log("Error: day must be in [1..28]")
                            throw ExitCode.failure
                        }
                        break
                    }
                    days.append(d)
                    i = idx
                }
            case "weekday":
                i += 1
                guard i < tokens.count, let w = Int(tokens[i]), w >= 0, w <= 6 else {
                    log("Error: weekday must be in [0..6]")
                    throw ExitCode.failure
                }
                weekday = w
            case "week_period":
                i += 1
                guard i < tokens.count, let wp = Int(tokens[i]), wp >= 1, wp <= 12 else {
                    log("Error: week_period must be in [1..12]")
                    throw ExitCode.failure
                }
                weekPeriod = wp
            case "month_period":
                i += 1
                guard i < tokens.count, let mp = Int(tokens[i]), mp >= 1, mp <= 3 else {
                    log("Error: month_period must be in [1..3]")
                    throw ExitCode.failure
                }
                monthPeriod = mp
            case "hour":
                i += 1
                guard i < tokens.count, let h = Int(tokens[i]), h >= 0, h <= 23 else {
                    log("Error: hour must be in [0..23]")
                    throw ExitCode.failure
                }
                hour = h
            case "minute":
                i += 1
                guard i < tokens.count, let m = Int(tokens[i]), m >= 0, m <= 59 else {
                    log("Error: minute must be in [0..59]")
                    throw ExitCode.failure
                }
                minute = m
            default:
                break
            }
            i += 1
        }

        // Defaults
        if days.isEmpty && weekday == nil {
            days = [1] // Default: day 1 per month
        }

        let minuteStr = String(format: "%02d", minute)

        // Weekday names
        let weekdayNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

        // Build schedule description and save config
        var scheduleText: String
        if let wd = weekday {
            let wdName = weekdayNames[wd]
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")

            let calendar = Calendar.current
            let weekNum = calendar.component(.weekOfYear, from: Date())
            let year = calendar.component(.year, from: Date())

            scheduleText = "Schedule calibration on \(wdName) every \(weekPeriod) week at \(hour):\(minuteStr) starting from Week \(String(format: "%02d", weekNum)) of Year \(year)"
        } else {
            if monthPeriod == 1 {
                let dayList = days.map(String.init).joined(separator: " ")
                scheduleText = "Schedule calibration on day \(dayList) at \(hour):\(minuteStr)"
            } else {
                let monthStr = {
                    let f = DateFormatter()
                    f.dateFormat = "MM"
                    f.locale = Locale(identifier: "en_US_POSIX")
                    return f.string(from: Date())
                }()
                let yearStr = {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy"
                    f.locale = Locale(identifier: "en_US_POSIX")
                    return f.string(from: Date())
                }()
                scheduleText = "Schedule calibration on day \(days[0]) every \(monthPeriod) month at \(hour):\(minuteStr) starting from Month \(monthStr) of Year \(yearStr)"
            }
        }

        try? config.write("calibrate_schedule", value: scheduleText)

        // Build LaunchAgent calendar intervals
        var intervals: [[String: Any]] = []
        if let wd = weekday {
            let launchctlWeekday = wd == 0 ? 7 : wd
            intervals.append([
                "Weekday": launchctlWeekday,
                "Hour": hour,
                "Minute": minute
            ])
        } else {
            for day in days {
                intervals.append([
                    "Day": day,
                    "Hour": hour,
                    "Minute": minute
                ])
            }
        }

        DaemonManager.createScheduleDaemon(calendarIntervals: intervals)
        DaemonManager.enableScheduleDaemon()

        // Compute calibrate_next so the daemon knows when to actually run.
        // The LaunchAgent fires on every matching interval, but the Calibrate
        // command checks calibrate_next and skips if it's too early. This is
        // how week_period and month_period are enforced.
        let calendar = Calendar.current
        var nextDate: Date?

        if let wd = weekday {
            // Weekly: find next occurrence of this weekday, then add (weekPeriod - 1) weeks
            var components = DateComponents()
            components.weekday = wd == 0 ? 1 : wd + 1  // DateComponents weekday: 1=Sun
            components.hour = hour
            components.minute = minute
            if let next = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) {
                nextDate = calendar.date(byAdding: .weekOfYear, value: weekPeriod - 1, to: next)
            }
        } else {
            // Monthly: find next occurrence of this day, then add (monthPeriod - 1) months
            let day = days.first ?? 1
            var components = DateComponents()
            components.day = day
            components.hour = hour
            components.minute = minute
            if let next = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) {
                nextDate = calendar.date(byAdding: .month, value: monthPeriod - 1, to: next)
            }
        }

        if let next = nextDate {
            let timestamp = String(Int(next.timeIntervalSince1970))
            try? config.write("calibrate_next", value: timestamp)
        }

        print("")
        showSchedule()
        print("")
    }
}
