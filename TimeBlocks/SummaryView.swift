//
//  SummaryView.swift
//  TimeBlocks
//
//  Monthly summary (DESIGN.md §5.3): hours per category for the saved days
//  of a month, computed on the fly from the 96-byte day blobs.
//

import SwiftUI
import SwiftData

struct SummaryView: View {
    @Query(sort: \DaySchedule.dayKey) private var schedules: [DaySchedule]
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]
    @State private var displayedMonth: Date = Calendar.current.startOfMonth(for: .now)

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                monthHeader
                if monthSchedules.isEmpty {
                    emptyState
                } else {
                    summaryList
                }
            }
            .padding(.horizontal, 12)
            .background(Color.tbBlue.opacity(0.06))
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Month selection

    private var monthHeader: some View {
        HStack {
            Button { step(by: -1) } label: {
                Image(systemName: "chevron.left.circle.fill").font(.title2)
            }
            .disabled(!canStep(by: -1))

            Spacer()
            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.tbDeepBlue)
            Spacer()

            Button { step(by: 1) } label: {
                Image(systemName: "chevron.right.circle.fill").font(.title2)
            }
            .disabled(!canStep(by: 1))
        }
        .tint(.tbOrange)
        .padding(.top, 8)
    }

    // MARK: Aggregation

    private var monthSchedules: [DaySchedule] {
        let c = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
        let base = (c.year ?? 2000) * 10000 + (c.month ?? 1) * 100
        return schedules.filter { $0.dayKey > base && $0.dayKey <= base + 31 }
    }

    /// Blocks per category id across the month's saved days.
    private var blockCounts: [UInt8: Int] {
        SummaryCalculator.blockCounts(for: monthSchedules.map(\.blocks))
    }

    // MARK: Rows

    private var summaryList: some View {
        let counts = blockCounts
        let total = max(counts.values.reduce(0, +), 1)
        let maxCount = max(counts.values.max() ?? 1, 1)

        return List {
            Section {
                Text("\(monthSchedules.count) day\(monthSchedules.count == 1 ? "" : "s") planned")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)

                ForEach(categories.filter { counts[UInt8($0.id)] != nil }) { cat in
                    let count = counts[UInt8(cat.id)] ?? 0
                    SummaryRow(
                        category: cat,
                        hours: Double(count) * 0.25,
                        fraction: Double(count) / Double(maxCount),
                        percent: Double(count) / Double(total)
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.visible)
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("📊")
                .font(.system(size: 56))
            Text("No days planned this month yet")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Stepping (12 months back through current month)

    private func step(by months: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: months, to: displayedMonth) {
            withAnimation { displayedMonth = next }
        }
    }

    private func canStep(by months: Int) -> Bool {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: displayedMonth) else { return false }
        let cal = Calendar.current
        let lower = cal.startOfMonth(for: cal.date(byAdding: .month, value: -12, to: .now) ?? .now)
        let upper = cal.startOfMonth(for: .now)
        return next >= lower && next <= upper
    }
}

private struct SummaryRow: View {
    let category: ActivityCategory
    let hours: Double
    let fraction: Double
    let percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(category.emoji)
                Text(category.name)
                    .font(.system(.body, design: .rounded, weight: .bold))
                Spacer()
                Text("\(hours.formatted(.number.precision(.fractionLength(0...2)))) h")
                    .font(.system(.body, design: .rounded, weight: .heavy))
                    .foregroundStyle(Color.tbDeepBlue)
                Text(percent.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            GeometryReader { geo in
                Capsule()
                    .fill(category.color)
                    .frame(width: max(geo.size.width * fraction, 8))
            }
            .frame(height: 10)
        }
        .padding(.vertical, 2)
    }
}
