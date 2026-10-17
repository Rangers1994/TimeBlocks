//
//  CalendarView.swift
//  TimeBlocks
//
//  Zoomed-out month view (DESIGN.md §5.1): each day cell shows a miniature
//  thumbnail of its saved schedule. Tapping a day zooms into the editor.
//

import SwiftUI
import SwiftData
import os

private let templateLog = Logger(subsystem: "com.philiprenton.TimeBlocks", category: "templates")

struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DaySchedule.dayKey) private var schedules: [DaySchedule]
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]
    @Query private var templates: [MonthTemplate]
    @State private var displayedMonth: Date = Calendar.current.startOfMonth(for: .now)
    @State private var navPath: [Int] = []   // pushed day keys; explicit to prevent double-pushes
    @Namespace private var zoomNamespace

    // Day copy/paste: long-press a planned day to copy, long-press a target to paste
    @State private var copiedBlocks: [UInt8]?
    @State private var copiedFromKey: Int?

    /// A schedule about to be applied to a non-blank day (paste or template
    /// drop), held until the user confirms the overwrite.
    private struct PendingApply: Identifiable {
        let key: Int
        let blocks: [UInt8]
        var id: Int { key }
    }
    @State private var pendingApply: PendingApply?

    private var colorMap: [UInt8: Color] {
        Dictionary(uniqueKeysWithValues: categories.map { (UInt8($0.id), $0.color) })
    }

    private var scheduleByKey: [Int: DaySchedule] {
        Dictionary(uniqueKeysWithValues: schedules.map { ($0.dayKey, $0) })
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 12) {
                monthHeader
                if copiedFromKey != nil { copyBanner }
                weekdayHeader
                monthGrid
                Spacer(minLength: 0)
                templateTray
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .background(Color.tbBlue.opacity(0.06))
            .navigationTitle("TimeBlocks")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int.self) { key in
                DayEditorView(dayKey: key)
                    .navigationTransition(.zoom(sourceID: key, in: zoomNamespace))
            }
            .alert(
                "Overwrite this day?",
                isPresented: Binding(
                    get: { pendingApply != nil },
                    set: { if !$0 { pendingApply = nil } }
                ),
                presenting: pendingApply
            ) { pending in
                Button("Overwrite", role: .destructive) { apply(pending.blocks, to: pending.key) }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text("\(DayKey.date(from: pending.key), format: .dateTime.weekday(.wide).month().day()) already has a plan. This will replace it.")
            }
        }
    }

    // MARK: Header

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

            Button("Today") {
                withAnimation { displayedMonth = Calendar.current.startOfMonth(for: .now) }
            }
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .buttonStyle(.bordered)
        }
        .tint(.tbOrange)
        .padding(.top, 8)
    }

    private var weekdayHeader: some View {
        let cal = Calendar.current
        let symbols = cal.veryShortWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return HStack {
            ForEach(ordered.indices, id: \.self) { i in
                Text(ordered[i])
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Month grid

    private var monthGrid: some View {
        let cells = monthCells
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(cells.indices, id: \.self) { i in
                if let day = cells[i] {
                    dayCell(day: day)
                } else {
                    Color.clear.frame(height: 64)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(day: Int) -> some View {
        let key = keyFor(day: day)
        let editable = DayKey.editableRange.contains(key)
        let schedule = scheduleByKey[key]
        let isToday = key == DayKey.key(for: .now)

        if editable {
            Button {
                openDay(key)
            } label: {
                DayCellView(day: day, blocks: schedule.map { [UInt8]($0.blocks) },
                            colorMap: colorMap, isToday: isToday, dimmed: false)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: key, in: zoomNamespace)
            .contextMenu {
                Button {
                    openDay(key)
                } label: {
                    Label("Open Day", systemImage: "square.and.pencil")
                }
                if let schedule {
                    Button {
                        copiedBlocks = [UInt8](schedule.blocks)
                        copiedFromKey = key
                    } label: {
                        Label("Copy Day", systemImage: "doc.on.doc")
                    }
                    Button {
                        setTemplate(kind: 0, from: schedule)
                    } label: {
                        Label("Set as Weekday Template", systemImage: "briefcase")
                    }
                    Button {
                        setTemplate(kind: 1, from: schedule)
                    } label: {
                        Label("Set as Weekend Template", systemImage: "sun.max")
                    }
                } else {
                    // Renders as a disabled explanatory row in the menu
                    Text("Plan this day to copy it or make it a template")
                }
                if copiedBlocks != nil && copiedFromKey != key {
                    Button {
                        requestPaste(to: key)
                    } label: {
                        Label("Paste Day", systemImage: "doc.on.clipboard")
                    }
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let kindID = items.first else { return false }
                return dropTemplate(kindID: kindID, onto: key)
            }
        } else {
            DayCellView(day: day, blocks: schedule.map { [UInt8]($0.blocks) },
                        colorMap: colorMap, isToday: isToday, dimmed: true)
        }
    }

    // MARK: Copy / paste

    private var copyBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.doc.fill")
            if let fromKey = copiedFromKey {
                Text("Copied \(DayKey.date(from: fromKey), format: .dateTime.month().day()) — touch and hold a day to paste")
            }
            Spacer()
            Button {
                copiedBlocks = nil
                copiedFromKey = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
        }
        .font(.system(.caption, design: .rounded, weight: .bold))
        .foregroundStyle(Color.tbDeepBlue)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.tbOrange.opacity(0.18)))
    }

    /// Pushes the day editor, ignoring the request if it is already open.
    private func openDay(_ key: Int) {
        if navPath.last != key {
            navPath.append(key)
        }
    }

    private func requestPaste(to key: Int) {
        guard let copied = copiedBlocks else { return }
        requestApply(copied, to: key)
    }

    /// Applies immediately to blank days; asks for confirmation otherwise.
    private func requestApply(_ blocks: [UInt8], to key: Int) {
        if scheduleByKey[key] != nil {
            pendingApply = PendingApply(key: key, blocks: blocks)
        } else {
            apply(blocks, to: key)
        }
    }

    private func apply(_ blocks: [UInt8], to key: Int) {
        let data = Data(blocks)
        if let existing = scheduleByKey[key] {
            existing.blocks = data
            existing.modifiedAt = .now
        } else {
            context.insert(DaySchedule(dayKey: key, blocks: data))
        }
        try? context.save()
    }

    // MARK: Month templates

    private var displayedMonthKey: Int {
        let c = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
        return (c.year ?? 2000) * 100 + (c.month ?? 1)
    }

    private func template(kind: Int) -> MonthTemplate? {
        templates.first { $0.monthKey == displayedMonthKey && $0.kind == kind }
    }

    private func setTemplate(kind: Int, from schedule: DaySchedule) {
        templateLog.notice("setTemplate kind=\(kind) monthKey=\(displayedMonthKey) sourceDay=\(schedule.dayKey)")
        if let existing = template(kind: kind) {
            existing.blocks = schedule.blocks
            existing.sourceDayKey = schedule.dayKey
            existing.modifiedAt = .now
        } else {
            context.insert(MonthTemplate(monthKey: displayedMonthKey, kind: kind,
                                         blocks: schedule.blocks, sourceDayKey: schedule.dayKey))
        }
        do {
            try context.save()
            let count = (try? context.fetchCount(FetchDescriptor<MonthTemplate>())) ?? -1
            templateLog.notice("template saved; total templates in store = \(count)")
        } catch {
            templateLog.error("template save FAILED: \(error.localizedDescription)")
        }
    }

    private func clearTemplate(kind: Int) {
        guard let existing = template(kind: kind) else { return }
        context.delete(existing)
        try? context.save()
    }

    private func dropTemplate(kindID: String, onto key: Int) -> Bool {
        let kind = kindID == "weekend" ? 1 : 0
        guard let tmpl = template(kind: kind) else { return false }
        requestApply([UInt8](tmpl.blocks), to: key)
        return true
    }

    private var templateTray: some View {
        HStack(spacing: 10) {
            TemplateSlotView(
                title: "Weekday",
                icon: "briefcase.fill",
                kindID: "weekday",
                blocks: template(kind: 0).map { [UInt8]($0.blocks) },
                sourceDayKey: template(kind: 0)?.sourceDayKey ?? 0,
                colorMap: colorMap,
                onClear: { clearTemplate(kind: 0) }
            )
            TemplateSlotView(
                title: "Weekend",
                icon: "sun.max.fill",
                kindID: "weekend",
                blocks: template(kind: 1).map { [UInt8]($0.blocks) },
                sourceDayKey: template(kind: 1)?.sourceDayKey ?? 0,
                colorMap: colorMap,
                onClear: { clearTemplate(kind: 1) }
            )
        }
    }

    // MARK: Helpers

    /// Leading nils pad the first weekday; then the days of the month.
    private var monthCells: [Int?] {
        let cal = Calendar.current
        let dayCount = cal.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        let weekday = cal.component(.weekday, from: displayedMonth)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + (1...dayCount).map { $0 }
    }

    private func keyFor(day: Int) -> Int {
        let c = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
        return (c.year ?? 2000) * 10000 + (c.month ?? 1) * 100 + day
    }

    private func step(by months: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: months, to: displayedMonth) {
            withAnimation { displayedMonth = next }
        }
    }

    /// Browsable range matches the editable window: 12 months back, 1 forward.
    private func canStep(by months: Int) -> Bool {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: displayedMonth) else { return false }
        let cal = Calendar.current
        let lower = cal.startOfMonth(for: cal.date(byAdding: .month, value: -12, to: .now) ?? .now)
        let upper = cal.startOfMonth(for: cal.date(byAdding: .month, value: 1, to: .now) ?? .now)
        return next >= lower && next <= upper
    }
}

// MARK: - Template tray slot

/// One template slot (weekday or weekend) for the displayed month. When set,
/// it shows the template's thumbnail and can be dragged onto calendar days.
private struct TemplateSlotView: View {
    let title: String
    let icon: String
    let kindID: String
    let blocks: [UInt8]?
    let sourceDayKey: Int
    let colorMap: [UInt8: Color]
    let onClear: () -> Void

    private var caption: String {
        if blocks == nil { return "Hold a day to set" }
        guard sourceDayKey > 0 else { return "Drag onto a day" }
        let date = DayKey.date(from: sourceDayKey)
        return "From \(date.formatted(.dateTime.month(.abbreviated).day())) — drag onto a day"
    }

    var body: some View {
        if let blocks {
            // No contextMenu here: a long-press menu would swallow the
            // press-and-hold needed to start dragging. Clearing is the ✕ button.
            slotContent(blocks: blocks)
                .draggable(kindID)
                .overlay(alignment: .topTrailing) {
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.white, Color.tbDeepBlue.opacity(0.7))
                    }
                    .offset(x: 6, y: -6)
                }
        } else {
            slotContent(blocks: nil)
        }
    }

    private func slotContent(blocks: [UInt8]?) -> some View {
        HStack(spacing: 10) {
            Group {
                if let blocks {
                    MiniDayThumbnail(blocks: blocks, colorMap: colorMap)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 32, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: icon)
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .foregroundStyle(Color.tbDeepBlue)
                Text(caption)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemBackground)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.tbBlue.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Day cell

private struct DayCellView: View {
    let day: Int
    let blocks: [UInt8]?
    let colorMap: [UInt8: Color]
    let isToday: Bool
    let dimmed: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(blocks == nil ? Color(.systemBackground) : .clear)

            if let blocks {
                MiniDayThumbnail(blocks: blocks, colorMap: colorMap)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text("\(day)")
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .foregroundStyle(blocks == nil ? Color.primary : .white)
                .shadow(color: blocks == nil ? .clear : .black.opacity(0.6), radius: 2)
                .padding(4)
        }
        .frame(height: 64)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isToday ? Color.tbOrange : Color.tbBlue.opacity(0.25),
                        lineWidth: isToday ? 3 : 1)
        )
        .opacity(dimmed ? 0.3 : 1)
    }
}

/// A day's 96 blocks drawn as a tiny 24-row × 4-column color grid.
struct MiniDayThumbnail: View {
    let blocks: [UInt8]
    let colorMap: [UInt8: Color]

    var body: some View {
        Canvas { context, size in
            let cw = size.width / 4
            let ch = size.height / 24
            for i in 0..<min(96, blocks.count) {
                let rect = CGRect(x: CGFloat(i % 4) * cw, y: CGFloat(i / 4) * ch, width: cw + 0.5, height: ch + 0.5)
                context.fill(Path(rect), with: .color(colorMap[blocks[i]] ?? .gray))
            }
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
