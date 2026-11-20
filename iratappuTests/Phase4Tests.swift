import Testing
import Foundation
import SwiftData
import UIKit
@testable import IRAPPO

struct RunRecordTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([RunRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func summary(mode: GameMode = .rage, kos: Int = 3, unlocked: [Int] = []) -> RunSummary {
        RunSummary(mode: mode, koCount: kos, taps: 120, maxCombo: 37, seconds: 41, merit: 0,
                   newBestCombo: nil, newBestRun: nil, unlockedCharacters: unlocked)
    }

    @Test func recordCreatedWithSummaryFields() throws {
        let ctx = try makeContext()
        let rec = RunRecorder(context: ctx).record(summary(unlocked: [3, 4]), weaponId: "hammer",
                                                  date: Date(timeIntervalSince1970: 1_000_000))
        #expect(rec.kos == 3)
        #expect(rec.taps == 120)
        #expect(rec.maxCombo == 37)
        #expect(rec.durationSeconds == 41)
        #expect(rec.weaponId == "hammer")
        #expect(rec.mood == nil)
        #expect(rec.newCharacterCount == 2)
        #expect(rec.mode == .rage)
        let all = try ctx.fetch(FetchDescriptor<RunRecord>())
        #expect(all.count == 1)
    }

    @Test func oneRecordPerRunAndMokugyoMode() throws {
        let ctx = try makeContext()
        let recorder = RunRecorder(context: ctx)
        recorder.record(summary(), weaponId: "fist")
        recorder.record(summary(mode: .mokugyo, kos: 0), weaponId: "mokugyo")
        let all = try ctx.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date)]))
        #expect(all.count == 2)
        #expect(Set(all.map(\.mode)) == [.rage, .mokugyo])
    }

    @Test func moodUpdateAndChange() throws {
        let ctx = try makeContext()
        let recorder = RunRecorder(context: ctx)
        let rec = recorder.record(summary(), weaponId: "fist")
        recorder.setMood(1, on: rec)
        #expect(try ctx.fetch(FetchDescriptor<RunRecord>()).first?.mood == 1)
        recorder.setMood(2, on: rec)                      // 改選
        #expect(try ctx.fetch(FetchDescriptor<RunRecord>()).first?.mood == 2)
    }
}

struct SettingsStoreTests {
    private func makeStore(dir: URL? = nil) -> (SettingsStore, UserDefaults, PhotoStore) {
        let d = UserDefaults(suiteName: "settings-test-\(UUID().uuidString)")!
        let photos = PhotoStore(directory: dir ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("irappo-test-\(UUID().uuidString)", isDirectory: true))
        return (SettingsStore(defaults: d, photos: photos), d, photos)
    }

    private func image() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 8))
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        }
    }

    @Test func defaults() {
        let (s, _, _) = makeStore()
        #expect(s.mode == .rage)
        #expect(s.startingCharacter == 0)
        #expect(!s.useCustomPhoto)
        #expect(s.loadPhoto() == nil)
    }

    @Test func modeAndStartingCharacterRoundTrip() {
        let (s, d, photos) = makeStore()
        s.mode = .mokugyo
        s.startingCharacter = 7
        let s2 = SettingsStore(defaults: d, photos: photos)       // 重開 app
        #expect(s2.mode == .mokugyo)
        #expect(s2.startingCharacter == 7)
        s2.mode = .rage
        #expect(SettingsStore(defaults: d, photos: photos).mode == .rage)
    }

    @Test func photoRoundTripAsFile() {
        let (s, d, photos) = makeStore()
        s.savePhoto(image())
        s.useCustomPhoto = true
        #expect(photos.exists)                                    // 存成檔案，不是 UserDefaults
        #expect(d.data(forKey: "customPhoto") == nil)
        let s2 = SettingsStore(defaults: d, photos: photos)
        let loaded = s2.loadPhoto()
        #expect(loaded != nil)
        #expect(Int(loaded?.size.width ?? 0) * Int(loaded?.scale ?? 1) >= 12)
    }

    @Test func photoOnlyRestoredWhenToggleOn() {
        let (s, _, _) = makeStore()
        s.savePhoto(image())
        s.useCustomPhoto = false
        #expect(s.loadPhoto() == nil)
    }

    /// 方向 .right 的圖（相機照片常見）：存檔再載入後要是 .up 且寬高對調
    private func rotatedImage() -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        let base = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 8), format: f).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        }                                                    // 12 x 8 像素
        return UIImage(cgImage: base.cgImage!, scale: 1, orientation: .right)
    }

    @Test func nonUpImageIsNormalizedBeforeSaving() {
        let (s, d, photos) = makeStore()
        let src = rotatedImage()
        #expect(src.imageOrientation == .right)
        #expect(Int(src.size.width) == 8 && Int(src.size.height) == 12)   // 顯示尺寸已對調
        s.savePhoto(src)
        s.useCustomPhoto = true
        let loaded = SettingsStore(defaults: d, photos: photos).loadPhoto()
        #expect(loaded?.imageOrientation == .up)
        #expect(Int((loaded?.size.width ?? 0) * (loaded?.scale ?? 1)) == 8)
        #expect(Int((loaded?.size.height ?? 0) * (loaded?.scale ?? 1)) == 12)
    }

    @Test func largePhotoIsDownscaledToMaxSide() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500),
                                               format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let big = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        }
        let out = PhotoStore.normalized(big)
        #expect(Int(out.size.width) == 1024)
        #expect(Int(out.size.height) == 512)
        #expect(out.imageOrientation == .up)
    }

    @Test func deletingPhotoRemovesFile() {
        let (s, _, photos) = makeStore()
        s.savePhoto(image())
        #expect(photos.exists)
        s.savePhoto(nil)
        #expect(!photos.exists)
    }
}

struct StatisticsPeriodTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(
        timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 6, day: 30, hour: 12))!

    @Test func noDataOffersTodayAndWeekOnly() {
        #expect(StatisticsRange.available(oldest: nil, now: now, calendar: cal) == [.today, .week])
    }

    @Test func recentDataStillOnlyTodayAndWeek() {
        #expect(StatisticsRange.available(oldest: date(6, 28), now: now, calendar: cal) == [.today, .week])
        #expect(StatisticsRange.available(oldest: date(6, 24), now: now, calendar: cal) == [.today, .week])  // 剛好 7 天內
    }

    @Test func monthAppearsOnceDataIsOlderThanAWeek() {
        #expect(StatisticsRange.available(oldest: date(6, 23), now: now, calendar: cal) == [.today, .week, .month])
    }

    @Test func quarterAndYearNeedOlderData() {
        #expect(StatisticsRange.available(oldest: date(5, 20), now: now, calendar: cal) == [.today, .week, .month, .quarter])
        #expect(StatisticsRange.available(oldest: date(2, 1), now: now, calendar: cal) == [.today, .week, .month, .quarter, .year])
    }

    // MARK: 彙總

    private func snap(_ day: Int, kos: Int, taps: Int = 10, combo: Int = 5, mood: Int? = nil,
                      mode: GameMode = .rage, month: Int = 6) -> RunSnapshot {
        RunSnapshot(date: date(month, day), mode: mode, kos: kos, taps: taps, maxCombo: combo, mood: mood)
    }

    @Test func summaryTotalsAndStreak() {
        let records = [snap(30, kos: 3, taps: 50, combo: 20, mood: 2),
                       snap(30, kos: 7, taps: 80, combo: 35, mood: 0),
                       snap(29, kos: 1, taps: 5, combo: 4, mood: 2),
                       snap(10, kos: 99, taps: 999, combo: 99)]          // 7 天之外
        let s = RecordsCalculator.summary(records, range: .week, now: now, calendar: cal)
        #expect(s.runs == 3)
        #expect(s.totalKOs == 11)
        #expect(s.bestStreak == 7)
        #expect(s.totalTaps == 135)
        #expect(s.maxCombo == 35)
        #expect(s.moods == [1, 0, 2])
        #expect(s.days.map(\.kos) == [1, 10])
    }

    @Test func allTimeIsIndependentOfRange() {
        let records = [snap(30, kos: 3, taps: 50, combo: 20),
                       snap(10, kos: 9, taps: 100, combo: 44),                 // 很久以前
                       snap(30, kos: 0, taps: 300, combo: 80, mode: .mokugyo)]
        let all = RecordsCalculator.allTime(records, bestRunKO: 0, bestCombo: 0)
        #expect(all.totalKOs == 12)
        #expect(all.totalTaps == 150)
        #expect(all.bestStreak == 9)
        #expect(all.maxCombo == 44)
        // 記錄值（bestRunKO / bestCombo）比紀錄資料大時取記錄值
        let merged = RecordsCalculator.allTime(records, bestRunKO: 15, bestCombo: 60)
        #expect(merged.bestStreak == 15)
        #expect(merged.maxCombo == 60)
    }

    @Test func todayRangeOnlyCountsToday() {
        let records = [snap(30, kos: 2), snap(29, kos: 5)]
        let s = RecordsCalculator.summary(records, range: .today, now: now, calendar: cal)
        #expect(s.runs == 1)
        #expect(s.totalKOs == 2)
    }

    @Test func mokugyoCountsRunsAndMoodsButNotKOs() {
        let records = [snap(30, kos: 0, taps: 300, combo: 80, mood: 1, mode: .mokugyo)]
        let s = RecordsCalculator.summary(records, range: .week, now: now, calendar: cal)
        #expect(s.runs == 1)
        #expect(s.moods == [0, 1, 0])
        #expect(s.totalTaps == 0)
        #expect(s.maxCombo == 0)
    }
}
