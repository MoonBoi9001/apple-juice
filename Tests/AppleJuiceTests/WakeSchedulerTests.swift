import Testing
import Foundation
@testable import apple_juice

@Suite("WakeScheduler Tests")
struct WakeSchedulerTests {

    @Test func primaryPathScalesAvgTimeToFull() {
        // 50% -> 80%, avgTimeToFull = 100 min (for 50% -> 100%)
        // gap=30, fullGap=50, scaled = 100 * 30/50 = 60 min
        // seconds = (60 - 5) * 60 = 3300
        let result = WakeScheduler.calculateTimeToTarget(
            currentPercent: 50, targetPercent: 80,
            avgTimeToFullMinutes: 100,
            instantAmperage: nil, rawMaxCapacity: nil, rawCurrentCapacity: nil)
        #expect(result == 3300)
    }

    @Test func fallbackPathUsesAmperage() {
        // target=80%, maxCap=5000, currentCap=3000, amperage=1000
        // targetCap = 80 * 5000 / 100 = 4000
        // remaining = 4000 - 3000 = 1000
        // hours = 1000 / 1000 = 1.0
        // seconds = max((1.0 * 3600) - 300, 600) = 3300
        let result = WakeScheduler.calculateTimeToTarget(
            currentPercent: 60, targetPercent: 80,
            avgTimeToFullMinutes: nil,
            instantAmperage: 1000, rawMaxCapacity: 5000, rawCurrentCapacity: 3000)
        #expect(result == 3300)
    }

    @Test func alreadyAtTargetReturnsNil() {
        let result = WakeScheduler.calculateTimeToTarget(
            currentPercent: 80, targetPercent: 80,
            avgTimeToFullMinutes: 100,
            instantAmperage: nil, rawMaxCapacity: nil, rawCurrentCapacity: nil)
        #expect(result == nil)
    }

    @Test func minimumTenMinuteFloor() {
        // 99% -> 100%, avgTimeToFull = 1 min
        // gap=1, fullGap=1, scaled = 1 * 1/1 = 1 min
        // seconds = max((1 - 5) * 60, 600) = max(-240, 600) = 600
        let result = WakeScheduler.calculateTimeToTarget(
            currentPercent: 99, targetPercent: 100,
            avgTimeToFullMinutes: 1,
            instantAmperage: nil, rawMaxCapacity: nil, rawCurrentCapacity: nil)
        #expect(result == 600)
    }

    @Test func noDataReturnsNil() {
        let result = WakeScheduler.calculateTimeToTarget(
            currentPercent: 50, targetPercent: 80,
            avgTimeToFullMinutes: nil,
            instantAmperage: nil, rawMaxCapacity: nil, rawCurrentCapacity: nil)
        #expect(result == nil)
    }
}
