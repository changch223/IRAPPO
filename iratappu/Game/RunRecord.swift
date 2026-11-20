import Foundation
import SwiftData
import os

// MARK: - 每輪一筆紀錄（SwiftData）

@Model
final class RunRecord {
    var date: Date
    var modeRaw: String
    var kos: Int
    var taps: Int
    var maxCombo: Int
    var durationSeconds: Int
    var weaponId: String
    /// 0 還是氣 / 1 好一點 / 2 好多了；沒選＝nil
    var mood: Int?
    var newCharacterCount: Int

    init(date: Date, mode: GameMode, kos: Int, taps: Int, maxCombo: Int, durationSeconds: Int,
         weaponId: String, mood: Int? = nil, newCharacterCount: Int = 0) {
        self.date = date
        self.modeRaw = mode == .mokugyo ? "mokugyo" : "rage"
        self.kos = kos
        self.taps = taps
        self.maxCombo = maxCombo
        self.durationSeconds = durationSeconds
        self.weaponId = weaponId
        self.mood = mood
        self.newCharacterCount = newCharacterCount
    }

    var mode: GameMode { modeRaw == "mokugyo" ? .mokugyo : .rage }

    var snapshot: RunSnapshot {
        RunSnapshot(date: date, mode: mode, kos: kos, taps: taps, maxCombo: maxCombo, mood: mood)
    }
}

/// 計算用的值型別（和 SwiftData 脫鉤，方便測試）
struct RunSnapshot: Equatable {
    var date: Date
    var mode: GameMode
    var kos: Int
    var taps: Int
    var maxCombo: Int
    var mood: Int?
}

/// 結算頁出現時寫入一筆；選心情時更新。
final class RunRecorder {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func record(_ summary: RunSummary, weaponId: String, date: Date = Date()) -> RunRecord {
        let record = RunRecord(date: date, mode: summary.mode, kos: summary.koCount, taps: summary.taps,
                               maxCombo: summary.maxCombo, durationSeconds: summary.seconds,
                               weaponId: weaponId, newCharacterCount: summary.unlockedCharacters.count)
        context.insert(record)
        save("insert")
        return record
    }

    func setMood(_ mood: Int?, on record: RunRecord) {
        record.mood = mood
        save("mood")
    }

    private func save(_ what: String) {
        do {
            try context.save()
        } catch {
            AppLog.records.error("RunRecord save failed (\(what, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - 統計期間

enum StatisticsRange: String, CaseIterable, Identifiable {
    case today, week, month, quarter, year

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .today: return L("range_today")
        case .week: return L("statisticsRange.week")
        case .month: return L("statisticsRange.month")
        case .quarter: return L("statisticsRange.quarter")
        case .year: return L("statisticsRange.year")
        }
    }

    /// 含今天在內共幾天
    var days: Int {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        }
    }

    func startDate(now: Date, calendar: Calendar) -> Date {
        let todayStart = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
    }

    /// 只列出資料撐得起來的期間：今天、7 天一定有（今天的手勢數與 7 天統計來自 StatsBuffer，紀錄也從第一輪開始累積）。
    /// 更長的期間要等到最舊的紀錄比「上一個較短期間」的起點還早，才會出現（否則只是重複同一份資料）。
    static func available(oldest: Date?, now: Date, calendar: Calendar) -> [StatisticsRange] {
        var result: [StatisticsRange] = [.today, .week]
        guard let oldest else { return result }
        let oldestDay = calendar.startOfDay(for: oldest)
        let ladder: [StatisticsRange] = [.week, .month, .quarter, .year]
        for i in 1..<ladder.count {
            let previousStart = ladder[i - 1].startDate(now: now, calendar: calendar)
            if oldestDay < previousStart { result.append(ladder[i]) } else { break }
        }
        return result
    }
}

// MARK: - 紀錄頁的計算

struct DayBucket: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var runs: Int
    var kos: Int
}

struct RecordsSummary: Equatable {
    var runs = 0
    var totalKOs = 0
    var bestStreak = 0
    var totalTaps = 0
    var maxCombo = 0
    /// 還是氣 / 好一點 / 好多了
    var moods = [0, 0, 0]
    var days: [DayBucket] = []
}

enum RecordsCalculator {
    /// 累計（不受選擇的期間影響）：擊退、打擊、連擊只算憤怒模式。
    /// 最佳連續擊退 / 最高連擊取「記錄值」與「紀錄資料」較大者（紀錄是從第一輪開始累積，記錄值涵蓋更早之前）。
    static func allTime(_ records: [RunSnapshot], bestRunKO: Int, bestCombo: Int) -> RecordsSummary {
        var s = RecordsSummary()
        s.runs = records.count
        for r in records where r.mode == .rage {
            s.totalKOs += r.kos
            s.totalTaps += r.taps
            s.bestStreak = max(s.bestStreak, r.kos)
            s.maxCombo = max(s.maxCombo, r.maxCombo)
        }
        s.bestStreak = max(s.bestStreak, bestRunKO)
        s.maxCombo = max(s.maxCombo, bestCombo)
        return s
    }

    /// 擊退、打擊、連擊只算憤怒模式；心情與輪數含木魚。
    static func summary(_ records: [RunSnapshot], range: StatisticsRange, now: Date, calendar: Calendar) -> RecordsSummary {
        let start = range.startDate(now: now, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let inRange = records.filter { $0.date >= start && $0.date < end }

        var s = RecordsSummary()
        s.runs = inRange.count
        var buckets: [Date: DayBucket] = [:]
        for r in inRange {
            if let m = r.mood, (0..<3).contains(m) { s.moods[m] += 1 }
            let day = calendar.startOfDay(for: r.date)
            var b = buckets[day] ?? DayBucket(date: day, runs: 0, kos: 0)
            b.runs += 1
            if r.mode == .rage {
                s.totalKOs += r.kos
                s.bestStreak = max(s.bestStreak, r.kos)
                s.totalTaps += r.taps
                s.maxCombo = max(s.maxCombo, r.maxCombo)
                b.kos += r.kos
            }
            buckets[day] = b
        }
        s.days = buckets.values.sorted { $0.date < $1.date }
        return s
    }
}
