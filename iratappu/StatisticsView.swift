//
//  StatisticsView.swift
//  紀錄頁（sheet）：今天的數字、心情、期間切換與每日擊退長條圖
//

import SwiftUI
import SwiftData
import Charts
import GoogleMobileAds

struct StatisticsView: View {
    /// 今日 / 7 天的手勢次數（沿用舊的統計）
    @ObservedObject var stats: StatsBuffer
    @Query(sort: \RunRecord.date) private var records: [RunRecord]
    @Environment(\.uiScale) private var k

    @State private var selectedRange: StatisticsRange = .week

    private var calendar: Calendar { .current }

    private var availableRanges: [StatisticsRange] {
        StatisticsRange.available(oldest: records.first?.date, now: Date(), calendar: calendar)
    }

    private var today: RecordsSummary {
        RecordsCalculator.summary(records.map(\.snapshot), range: .today, now: Date(), calendar: calendar)
    }

    /// 長條圖的期間：今天沒有「每日」可畫，改畫最近 7 天；其他期間就是自己
    private var chartRange: StatisticsRange {
        effectiveRange == .today ? .week : effectiveRange
    }

    private var summary: RecordsSummary {
        RecordsCalculator.summary(records.map(\.snapshot), range: chartRange, now: Date(), calendar: calendar)
    }

    /// 期間內每一天一根，沒有資料的日子補 0（固定 domain）
    private var chartDays: [DayBucket] {
        let todayStart = calendar.startOfDay(for: Date())
        let lookup = Dictionary(uniqueKeysWithValues: summary.days.map { (calendar.startOfDay(for: $0.date), $0) })
        return (0..<chartRange.days).compactMap { i in
            guard let d = calendar.date(byAdding: .day, value: i - (chartRange.days - 1), to: todayStart) else { return nil }
            let hit = lookup[d]
            return DayBucket(date: d, runs: hit?.runs ?? 0, kos: hit?.kos ?? 0)
        }
    }

    /// 選到的期間若不在可用清單裡就退回 7 天
    private var effectiveRange: StatisticsRange {
        availableRanges.contains(selectedRange) ? selectedRange : .week
    }

    private var allTime: RecordsSummary {
        RecordsCalculator.allTime(records.map(\.snapshot),
                                  bestRunKO: UserDefaults.standard.integer(forKey: "bestRunKO"),
                                  bestCombo: UserDefaults.standard.integer(forKey: "bestCombo"))
    }

    var body: some View {
        SheetScaffold(title: L("records_title")) {
            // 今天
            SheetLab(text: L("range_today"))
            HStack(alignment: .top, spacing: 8 * k) {
                num(L("result_ko"), today.totalKOs)
                num(L("result_taps"), today.totalTaps)
                num(L("result_maxcombo"), today.maxCombo)
            }

            VStack(spacing: 0) {
                row("🏅 " + L("records_best_streak"), today.bestStreak)
                row("😌 " + L("mood_good"), today.moods[2])
                row("😮‍💨 " + L("mood_ok"), today.moods[1])
                row("😤 " + L("mood_bad"), today.moods[0])
            }

            // 期間切換 + 每日擊退
            rangePicker

            if summary.runs == 0 {
                Text(L("records_empty"))
                    .uiFont(15, .bold)
                    .foregroundColor(Theme.ink.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18 * k)
            } else {
                SheetLab(text: L("records_chart_ko"))
                let days = chartDays
                Chart(days) { day in
                    BarMark(x: .value("day", day.date, unit: .day), y: .value("KO", day.kos))
                        .foregroundStyle(Theme.hot)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                }
                .chartXScale(domain: (days.first?.date ?? Date())...(calendar.date(byAdding: .day, value: 1, to: days.last?.date ?? Date()) ?? Date()))
                .chartXAxis {
                    if days.count <= 7 {
                        // 七欄：每天一根，X 軸標籤用星期
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        }
                    } else {
                        AxisMarks()
                    }
                }
                .frame(height: 130 * k)
                SheetLab(text: String(format: L("records_runs_count"), summary.runs))
            }

            // 全部累計
            SheetLab(text: L("records_all_time"))
            VStack(spacing: 0) {
                row(L("records_total_ko"), allTime.totalKOs)
                row(L("records_best_streak_all"), allTime.bestStreak)
                row(L("records_total_taps"), allTime.totalTaps)
                row(L("records_max_combo"), allTime.maxCombo)
            }

            // 舊的手勢次數統計（今日 / 最近 7 天）
            SheetLab(text: L("records_chart_taps"))
            VStack(spacing: 0) {
                row(L("todayCount"), stats.todayCount)
                row(L("sevenDaysCount"), stats.sevenDayTotal)
            }
            Chart(Array(stats.counts.enumerated()), id: \.offset) { item in
                BarMark(x: .value("day", item.offset), y: .value("taps", item.element))
                    .foregroundStyle(Theme.hot)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
            }
            .chartXAxis(.hidden)
            .frame(height: 70 * k)

            BannerAdView(adUnitID: "ca-app-pub-9275380963550837/7125166187")
                .frame(height: 50)
                .frame(maxWidth: .infinity)
        }
    }

    // 數字格：數字 28pt rounded black，標籤 15pt bold 65%
    private func num(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2 * k) {
            Text("\(value)").uiFont(28, .black, number: true)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).uiFont(15, .bold)
                .foregroundColor(Theme.ink.opacity(0.65))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // row：字 18pt，數字粗體，分隔線 ink 12%
    private func row(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label).uiFont(18, .medium)
            Spacer(minLength: 8)
            Text("\(value)").uiFont(21, .black, number: true)
        }
        .padding(.vertical, 10 * k)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.ink.opacity(0.12)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// 和主畫面模式切換同款的膠囊
    private var rangePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(availableRanges) { range in
                    let on = range == effectiveRange
                    Button { selectedRange = range } label: {
                        Text(range.localizedName)
                            .uiFont(16, .bold)
                            .lineLimit(1)
                            .foregroundColor(on ? Theme.paper : Theme.ink)
                            .padding(.vertical, 8 * k)
                            .padding(.horizontal, 14 * k)
                            .background(Capsule().fill(on ? Theme.ink : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(4.5 * k)
            .background(Capsule().fill(Theme.ink.opacity(0.08)))
        }
        .accessibilityLabel(L("statisticsRange"))
    }
}
