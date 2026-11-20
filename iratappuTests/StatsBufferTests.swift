import Testing
import Foundation
@testable import IRAPPO

struct StatsBufferTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: hour))!
    }

    private final class Clock { var now: Date; init(_ d: Date) { now = d } }

    private func make(day: Int, defaults: UserDefaults? = nil) -> (StatsBuffer, UserDefaults, Clock) {
        let suite = "stats-test-\(UUID().uuidString)"
        let d = defaults ?? UserDefaults(suiteName: suite)!
        let clock = Clock(date(day))
        let calendar = cal
        let s = StatsBuffer(defaults: d, calendar: calendar, now: { clock.now })
        return (s, d, clock)
    }

    private func seed(_ d: UserDefaults, counts: [Int], today: Int, key: String) {
        d.set(try! JSONEncoder().encode(counts), forKey: "sevenDayCountsData")
        d.set(today, forKey: "todayCount")
        d.set(key, forKey: StatsConfig.dayKey)
    }

    @Test func firstLaunchOnlyRecordsDay() {
        let (s, d, _) = make(day: 10)
        s.recordGesture()
        s.rollDayIfNeeded()
        #expect(s.todayCount == 1)                       // 沒有歸零、沒有推進
        #expect(d.string(forKey: StatsConfig.dayKey) == "20260310")
    }

    @Test func sameDayDoesNothing() {
        let suite = "stats-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        seed(d, counts: [1, 2, 3, 4, 5, 6, 7], today: 7, key: "20260310")
        let (s, _, _) = make(day: 10, defaults: d)
        s.rollDayIfNeeded()
        #expect(s.counts == [1, 2, 3, 4, 5, 6, 7])
        #expect(s.todayCount == 7)
    }

    @Test func nextDayShiftsByOne() {
        let d = UserDefaults(suiteName: "stats-test-\(UUID().uuidString)")!
        seed(d, counts: [1, 2, 3, 4, 5, 6, 7], today: 7, key: "20260310")
        let (s, _, _) = make(day: 11, defaults: d)
        s.rollDayIfNeeded()
        #expect(s.counts == [2, 3, 4, 5, 6, 7, 0])
        #expect(s.todayCount == 0)
        #expect(s.maxComboToday == 0)
        #expect(d.string(forKey: StatsConfig.dayKey) == "20260311")
    }

    @Test func gapShiftsByElapsedDays() {
        let d = UserDefaults(suiteName: "stats-test-\(UUID().uuidString)")!
        seed(d, counts: [1, 2, 3, 4, 5, 6, 7], today: 7, key: "20260310")
        let (s, _, _) = make(day: 13, defaults: d)      // 過了 3 天
        s.rollDayIfNeeded()
        #expect(s.counts == [4, 5, 6, 7, 0, 0, 0])
    }

    @Test func longGapCapsAtSeven() {
        let d = UserDefaults(suiteName: "stats-test-\(UUID().uuidString)")!
        seed(d, counts: [1, 2, 3, 4, 5, 6, 7], today: 7, key: "20260301")
        let (s, _, _) = make(day: 28, defaults: d)      // 27 天
        s.rollDayIfNeeded()
        #expect(s.counts == [0, 0, 0, 0, 0, 0, 0])
        #expect(s.sevenDayTotal == 0)
    }

    @Test func clockMovedBackwardsDoesNotShift() {
        let d = UserDefaults(suiteName: "stats-test-\(UUID().uuidString)")!
        seed(d, counts: [1, 2, 3, 4, 5, 6, 7], today: 7, key: "20260310")
        let (s, _, _) = make(day: 8, defaults: d)
        s.rollDayIfNeeded()
        #expect(s.counts == [1, 2, 3, 4, 5, 6, 7])
        #expect(s.todayCount == 7)
        #expect(d.string(forKey: StatsConfig.dayKey) == "20260310")   // 不採用較早的日期
    }

    @Test func midnightWhileRunningFlushesThenRolls() {
        let (s, d, clock) = make(day: 10)
        s.rollDayIfNeeded()                              // 記下 3/10
        s.recordGesture()
        s.recordGesture()
        s.recordCombo(9)
        clock.now = date(11, hour: 0)                    // 前景跨過午夜
        s.rollDayIfNeeded()
        #expect(s.counts[5] == 2)                        // 昨天的 2 下被保留在序列裡
        #expect(s.counts[6] == 0)
        #expect(s.todayCount == 0)
        #expect(s.maxComboToday == 0)
        let stored = try! JSONDecoder().decode([Int].self, from: d.data(forKey: "sevenDayCountsData")!)
        #expect(stored[5] == 2)
        s.recordGesture()
        #expect(s.counts[6] == 1)
    }

    @Test func rollResetsLaunchCounter() {
        let d = UserDefaults(suiteName: "stats-test-\(UUID().uuidString)")!
        seed(d, counts: [0, 0, 0, 0, 0, 0, 3], today: 3, key: "20260310")
        d.set(5, forKey: "todayAppLaunchCount")
        let (s, _, _) = make(day: 11, defaults: d)
        s.rollDayIfNeeded()
        #expect(d.integer(forKey: "todayAppLaunchCount") == 0)
    }

    @Test func gestureCountsAreBufferedUntilFlush() {
        let (s, d, _) = make(day: 10)
        s.recordGesture()
        #expect(d.integer(forKey: "todayCount") == 0)    // 還沒寫入
        s.flush()
        #expect(d.integer(forKey: "todayCount") == 1)
    }
}
