
//
//  Untitled.swift
//  iratappu
//
//  Created by chang chiawei on 2025-03-21.
//

import SwiftUI
import Charts

struct DayCount: Identifiable {
    let id = UUID()
    let day: String
    let count: Int
}

struct StatisticsView: View {
    let sevenDayCounts: [Int]

    private var data: [DayCount] {
        let calendar = Calendar.current
        return (0..<7).map { i in
            let date = calendar.date(byAdding: .day, value: i - 6, to: Date())!
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd"
            return DayCount(day: formatter.string(from: date), count: sevenDayCounts[i])
        }
    }

    var body: some View {
        VStack {
            Text("最近7天點擊次數")
                .font(.title2)
                .padding()

            Chart(data) { entry in
                BarMark(
                    x: .value("日期", entry.day),
                    y: .value("次數", entry.count)
                )
                .foregroundStyle(.red.gradient)
            }
            .frame(height: 300)
            .padding()
        }
    }
}
