import Foundation

enum StatsConfig {
    /// 統計寫入 UserDefaults 的去抖時間（秒）
    static let flushDelay: TimeInterval = 2.0
    static let dayKey = "lastDateKey"
}

/// 今日 / 七天 / 最高連擊的統計：放在記憶體，定時或在結算、進背景時才寫入 UserDefaults。
/// 計算方式維持舊的意義：每個手勢算一次。
final class StatsBuffer: ObservableObject {
    @Published private(set) var sessionCount = 0
    @Published private(set) var todayCount = 0
    @Published private(set) var sevenDayTotal = 0
    private(set) var counts: [Int] = Array(repeating: 0, count: 7)
    private(set) var maxComboToday = 0

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private var dirty = false
    private var timer: Timer?

    init(defaults: UserDefaults = .standard,
         calendar: Calendar = .current,
         now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        load()
    }

    private func load() {
        todayCount = defaults.integer(forKey: "todayCount")
        maxComboToday = defaults.integer(forKey: "todayComboCount")
        if let data = defaults.data(forKey: "sevenDayCountsData"),
           let decoded = try? JSONDecoder().decode([Int].self, from: data), decoded.count == 7 {
            counts = decoded
        }
        sevenDayTotal = counts.reduce(0, +)
    }

    /// 一個手勢
    func recordGesture() {
        sessionCount += 1
        todayCount += 1
        counts[6] = todayCount
        sevenDayTotal = counts.reduce(0, +)
        markDirty()
    }

    func recordCombo(_ combo: Int) {
        guard combo > maxComboToday else { return }
        maxComboToday = combo
        markDirty()
    }

    private func markDirty() {
        dirty = true
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: StatsConfig.flushDelay, repeats: false) { [weak self] _ in
            self?.flush()
        }
    }

    func flush() {
        timer?.invalidate()
        timer = nil
        guard dirty else { return }
        dirty = false
        defaults.set(todayCount, forKey: "todayCount")
        defaults.set(maxComboToday, forKey: "todayComboCount")
        defaults.set((try? JSONEncoder().encode(counts)) ?? Data(), forKey: "sevenDayCountsData")
    }

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }

    private func date(fromKey key: String) -> Date? {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f.date(from: key)
    }

    /// 跨日：七天序列依實際經過的天數往前推（最多 7），今天的數字歸零。
    /// 啟動、回前景、午夜（NSCalendarDayChanged）都會呼叫。
    func rollDayIfNeeded() {
        flush()
        let todayKey = dayKey(now())
        let lastKey = defaults.string(forKey: StatsConfig.dayKey) ?? ""
        guard todayKey != lastKey else { return }

        // 第一次啟動：只記下今天。
        // 注意要明確擋掉空字串：DateFormatter("yyyyMMdd") 會把 "" 解析成 2000-01-01，
        // 會讓第一次啟動被當成過了很多天而把今天的數字歸零。
        guard !lastKey.isEmpty, let last = date(fromKey: lastKey) else {
            defaults.set(todayKey, forKey: StatsConfig.dayKey)
            return
        }
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: last),
                                              to: calendar.startOfDay(for: now())).day ?? 0
        // 時鐘被往回調：視為「同一天、不重置」，保留原本記下的日期（不採用較早的日期）
        guard elapsed > 0 else { return }
        defaults.set(todayKey, forKey: StatsConfig.dayKey)

        let shift = min(elapsed, counts.count)
        counts.removeFirst(shift)
        counts.append(contentsOf: Array(repeating: 0, count: shift))
        todayCount = 0
        maxComboToday = 0
        sevenDayTotal = counts.reduce(0, +)
        defaults.set(0, forKey: "todayAppLaunchCount")
        dirty = true
        flush()
    }
}
