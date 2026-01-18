//
//  AnalyticsView.swift
//  MeetingRecorder
//
//  Usage dashboard with spend, charts, and breakdown
//

import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var viewModel: MainAppViewModel
    @State private var selectedMonth = Date()

    // Budget limit (could be user-configurable later)
    let budgetLimit: Double = 10.0

    // Computed properties for clean separation
    private var meetingsOnly: [Meeting] {
        viewModel.meetings.filter { $0.sourceApp != "Dictation" }
    }

    private var dictationsOnly: [Meeting] {
        viewModel.meetings.filter { $0.sourceApp == "Dictation" }
    }

    private var meetingsHours: Double {
        meetingsOnly.reduce(0) { $0 + $1.duration } / 3600
    }

    private var meetingsCost: Double {
        Double(meetingsOnly.compactMap { $0.apiCostCents }.reduce(0, +)) / 100
    }

    private var dictationsMinutes: Double {
        dictationsOnly.reduce(0) { $0 + $1.duration } / 60
    }

    private var dictationsCost: Double {
        Double(dictationsOnly.compactMap { $0.apiCostCents }.reduce(0, +)) / 100
    }

    private var last14DaysData: [DayChartData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

        return (0..<14).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let weekday = calendar.component(.weekday, from: date)
            let count = viewModel.meetings.filter {
                calendar.isDate($0.startTime, inSameDayAs: date)
            }.count

            return DayChartData(
                day: date,
                count: count,
                label: dayLabels[weekday - 1],
                isWeekend: weekday == 1 || weekday == 7
            )
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Month Header
                HStack {
                    Text("Analytics")
                        .font(.brandDisplay(24, weight: .bold))
                    
                    Spacer()
                    
                    HStack {
                        Text(selectedMonth.formatted(.dateTime.month().year()))
                            .font(.brandMono(14))
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.brandBorder, lineWidth: 1)
                    )
                }
                
                // Spend Card
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("$\(viewModel.totalCost, specifier: "%.2f")")
                                .font(.brandDisplay(48, weight: .bold))
                                .foregroundColor(.brandViolet)
                            
                            Text("spent this month")
                                .font(.brandSerif(16))
                                .foregroundColor(.brandTextSecondary)
                        }
                        Spacer()
                    }
                    
                    // Progress Bar
                    VStack(alignment: .leading, spacing: 8) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.brandBorder)
                                    .frame(height: 8)
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(colors: [.brandViolet, .brandVioletBright], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: min(geometry.size.width * (viewModel.totalCost / budgetLimit), geometry.size.width), height: 8)
                            }
                        }
                        .frame(height: 8)
                        
                        HStack {
                            Text("\(Int((viewModel.totalCost / budgetLimit) * 100))% of $\(Int(budgetLimit))")
                                .font(.brandMono(12))
                                .foregroundColor(.brandTextSecondary)
                            Spacer()
                        }
                    }
                }
                .padding(24)
                .background(Color.white)
                .cornerRadius(BrandRadius.large)
                .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
                
                // Usage Chart
                VStack(alignment: .leading, spacing: 16) {
                    Text("Usage")
                        .font(.brandDisplay(18, weight: .semibold))

                    if viewModel.totalMeetings > 0 {
                        let maxCount = max(1, last14DaysData.map(\.count).max() ?? 1)
                        let chartHeight: CGFloat = 80

                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(last14DaysData, id: \.day) { dayData in
                                VStack(spacing: 4) {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(dayData.isWeekend ? Color.brandBorder : Color.brandViolet)
                                        .frame(height: dayData.count > 0
                                            ? max(4, chartHeight * CGFloat(dayData.count) / CGFloat(maxCount))
                                            : 4)

                                    Text(dayData.label)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(height: chartHeight + 20) // chart + labels
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("No recordings yet")
                            .font(.brandSerif(14))
                            .foregroundColor(.brandTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    }
                }
                .padding(24)
                .background(Color.white)
                .cornerRadius(BrandRadius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.medium)
                        .stroke(Color.brandBorder, lineWidth: 1)
                )
                
                // Breakdown
                HStack(spacing: 16) {
                    BreakdownCard(
                        count: meetingsOnly.count,
                        label: "meetings",
                        subtext: "\(String(format: "%.1f", meetingsHours)) hrs • $\(String(format: "%.2f", meetingsCost))"
                    )

                    BreakdownCard(
                        count: dictationsOnly.count,
                        label: "dictations",
                        subtext: "\(String(format: "%.0f", dictationsMinutes)) min • $\(String(format: "%.2f", dictationsCost))"
                    )
                }
                
                // All Time
                VStack(alignment: .leading, spacing: 12) {
                    Text("All Time")
                        .font(.brandDisplay(18, weight: .semibold))

                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(viewModel.totalMeetings) recordings")
                            Text("\(String(format: "%.1f", viewModel.totalHours)) hrs • $\(String(format: "%.2f", viewModel.totalCost))")
                                .font(.brandMono(12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(BrandRadius.medium)
                }
            }
            .padding(32)
        }
        .background(Color.brandBackground)
    }
}

struct BreakdownCard: View {
    let count: Int
    let label: String
    let subtext: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(count)")
                .font(.brandDisplay(32, weight: .bold))
                .foregroundColor(.brandTextPrimary)
            
            Text(label)
                .font(.brandSerif(16))
                .foregroundColor(.brandTextSecondary)
            
            Text(subtext)
                .font(.brandMono(12))
                .foregroundColor(.brandTextSecondary)
                .padding(8)
                .background(Color.brandBackground)
                .cornerRadius(4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(BrandRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.medium)
                .stroke(Color.brandBorder, lineWidth: 1)
        )
    }
}

// MARK: - Chart Data Model

fileprivate struct DayChartData {
    let day: Date
    let count: Int
    let label: String
    let isWeekend: Bool
}
