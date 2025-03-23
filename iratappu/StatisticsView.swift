//
//  StatisticsView.swift
//  YourApp
//
//  Created by Your Name on YYYY/MM/DD.
//

import SwiftUI
import Charts
import GoogleMobileAds

// MARK: - 資料模型

/// 每日資料結構（請根據實際需求調整欄位）
struct DayCount: Identifiable {
    let id = UUID()
    let date: Date          // 當天日期
    let count: Int          // 當天點擊次數
    let comboCount: Int     // 當天最高 combo 次數（可用作最高點擊次數）
    let appLaunchCount: Int // 當天 app 啟動次數
}

/// 統計範圍選項
enum StatisticsRange: String, CaseIterable, Identifiable {
    case week = "最近7日間"
    case month = "今月"
    case quarter = "過去3ヶ月"
    case year = "今年"
    
    var id: Self { self }
}

// MARK: - StatisticsView 主視圖

struct StatisticsView: View {
    /// 所有的每日資料（請確保資料範圍足夠，例如最近 365 天）
    let allDailyData: [DayCount]
    
    /// 使用者目前選擇的統計範圍
    @State private var selectedRange: StatisticsRange = .week
    
    var body: some View {
        VStack(spacing: 16) {
            // 範圍切換
            Picker("統計期間を選択", selection: $selectedRange) {
                ForEach(StatisticsRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // 柱狀圖：以每日點擊次數繪製
            Chart(filteredData) { dayCount in
                BarMark(
                    x: .value("日付", formatDate(dayCount.date)),
                    y: .value("タップ回数", dayCount.count)
                )
                .foregroundStyle(.red.gradient)
            }
            .frame(height: 300)
            .padding(.horizontal)
            
            // 統計摘要：兩列四個項目
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    summaryItemView(title: "総タップ数", value: "\(totalTapCount)")
                    summaryItemView(title: "最高タップ数（連続）", value: "\(maxComboCount)")
                }
                HStack(spacing: 16) {
                    summaryItemView(title: "平均タップ数", value: String(format: "%.1f", averageTapCount))
                    summaryItemView(title: "アプリ起動回数", value: "\(totalAppLaunchCount)")
                }
            }
            .padding()
            
            Spacer() // 讓廣告顯示在底部
            
            BannerAdView(adUnitID: "ca-app-pub-9275380963550837/6757899905")
                .frame(height: 50)
        }
        .navigationTitle("イライラ統計🥹🥹🥹")
    }
}

// MARK: - 資料篩選與日期格式化
extension StatisticsView {
    /// 根據選擇的統計範圍，篩選出相應區間的資料
    private var filteredData: [DayCount] {
        let now = Date()
        let calendar = Calendar.current
        // 取得今天的開始時刻
        let todayStart = calendar.startOfDay(for: now)
        
        switch selectedRange {
        case .week:
            // 往前推6天，再取得那天的開始時刻
            if let rawStartDate = calendar.date(byAdding: .day, value: -6, to: todayStart) {
                let startDate = calendar.startOfDay(for: rawStartDate)
                return allDailyData.filter {
                    let dataDay = calendar.startOfDay(for: $0.date)
                    return dataDay >= startDate && dataDay <= todayStart
                }
            }
        case .month:
            if let rawStartDate = calendar.date(byAdding: .day, value: -29, to: todayStart) {
                let startDate = calendar.startOfDay(for: rawStartDate)
                return allDailyData.filter {
                    let dataDay = calendar.startOfDay(for: $0.date)
                    return dataDay >= startDate && dataDay <= todayStart
                }
            }
        case .quarter:
            if let rawStartDate = calendar.date(byAdding: .day, value: -89, to: todayStart) {
                let startDate = calendar.startOfDay(for: rawStartDate)
                return allDailyData.filter {
                    let dataDay = calendar.startOfDay(for: $0.date)
                    return dataDay >= startDate && dataDay <= todayStart
                }
            }
        case .year:
            if let rawStartDate = calendar.date(byAdding: .day, value: -364, to: todayStart) {
                let startDate = calendar.startOfDay(for: rawStartDate)
                return allDailyData.filter {
                    let dataDay = calendar.startOfDay(for: $0.date)
                    return dataDay >= startDate && dataDay <= todayStart
                }
            }
        }
        return []
    }

    /// 日期格式化 (例如 "MM/dd")
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
    
}

// MARK: - 統計數據計算
extension StatisticsView {
    /// 總點擊次數：將篩選資料中 count 累加
    private var totalTapCount: Int {
        filteredData.reduce(0) { $0 + $1.count }
    }
    
    /// 最高點擊次數：這裡以當天最高 comboCount 為例
    private var maxComboCount: Int {
        filteredData.map { $0.comboCount }.max() ?? 0
    }
    
    /// 平均點擊次數：算法為 (總點擊次數) ÷ (資料天數)
    private var averageTapCount: Double {
        guard !filteredData.isEmpty else { return 0 }
        return Double(totalTapCount) / Double(filteredData.count)
    }
    
    /// 統計 app 啟動次數：累計所有資料中的 appLaunchCount
    private var totalAppLaunchCount: Int {
        filteredData.reduce(0) { $0 + $1.appLaunchCount }
    }
}

// MARK: - 統計摘要的 UI 小工具
extension StatisticsView {
    /// 統計摘要項目視圖
    private func summaryItemView(title: String, value: String) -> some View {
        VStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .bold()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - 預覽
struct StatisticsView_Previews: PreviewProvider {
    static var previews: some View {
        // 建立模擬資料：假設過去 365 天的隨機資料
        let calendar = Calendar.current
        let today = Date()
        var dummyData = [DayCount]()
        for i in 0..<365 {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                dummyData.append(
                    DayCount(date: date,
                             count: Int.random(in: 0...100),
                             comboCount: Int.random(in: 0...50),
                             appLaunchCount: Int.random(in: 0...5))
                )
            }
        }
        
        return NavigationView {
            StatisticsView(allDailyData: dummyData)
        }
    }
}
