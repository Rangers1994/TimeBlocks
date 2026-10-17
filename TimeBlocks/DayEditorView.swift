//
//  DayEditorView.swift
//  TimeBlocks
//
//  Zoomed-in day editor (DESIGN.md §5.2): a 24-hour × 4-quarter grid drawn
//  in a single Canvas. Pick a category brush, then tap or drag to paint.
//  Edits auto-save; untouched template days are never persisted.
//

import SwiftUI
import SwiftData

struct DayEditorView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]

    @State private var dayKey: Int
    @State private var blocks: [UInt8] = DayTemplate.defaultBlocks()
    @State private var brush: UInt8 = 0
    @State private var dirty = false
    @State private var paintCount = 0   // increments per painted block to trigger haptics

    // Stroke-based undo: one tap or drag = one undo step (96 bytes each)
    @State private var undoStack: [[UInt8]] = []
    @State private var redoStack: [[UInt8]] = []
    @State private var strokeSnapshot: [UInt8]?

    init(dayKey: Int) {
        _dayKey = State(initialValue: dayKey)
    }

    private var colorMap: [UInt8: Color] {
        Dictionary(uniqueKeysWithValues: categories.map { (UInt8($0.id), $0.color) })
    }

    private var emojiMap: [UInt8: String] {
        Dictionary(uniqueKeysWithValues: categories.map { (UInt8($0.id), $0.emoji) })
    }

    var body: some View {
        VStack(spacing: 8) {
            dateBar
            quarterHeader
            grid
            palette
        }
        .padding(.horizontal, 12)
        .background(Color.tbBlue.opacity(0.06))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
        .onDisappear { save() }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: paintCount)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { undo() } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                }
                .disabled(undoStack.isEmpty)

                Button { redo() } label: {
                    Image(systemName: "arrow.uturn.forward.circle.fill")
                }
                .disabled(redoStack.isEmpty)
            }
        }
        .tint(.tbOrange)
    }

    // MARK: Date bar

    private var dateBar: some View {
        HStack {
            Button { step(by: -1) } label: {
                Image(systemName: "chevron.left.circle.fill").font(.title2)
            }
            .disabled(!canStep(by: -1))

            Spacer()
            Text(DayKey.date(from: dayKey), format: .dateTime.weekday(.wide).month().day())
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.tbDeepBlue)
            Spacer()

            Button { step(by: 1) } label: {
                Image(systemName: "chevron.right.circle.fill").font(.title2)
            }
            .disabled(!canStep(by: 1))

            Button("Today") { jump(to: DayKey.key(for: .now)) }
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .buttonStyle(.bordered)
        }
        .tint(.tbOrange)
    }

    private var quarterHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 36, height: 1)
            ForEach([":00", ":15", ":30", ":45"], id: \.self) { label in
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 2)
            }
        }
    }

    // MARK: Grid

    private var grid: some View {
        HStack(spacing: 2) {
            hourGutter
            GeometryReader { geo in
                gridCanvas
                    .accessibilityElement()
                    .accessibilityIdentifier("dayGrid")
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if strokeSnapshot == nil { strokeSnapshot = blocks }
                                paint(at: value.location, in: geo.size)
                            }
                            .onEnded { _ in
                                endStroke()
                                save()
                            }
                    )
            }
        }
    }

    private var hourGutter: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var gridCanvas: some View {
        Canvas { ctx, size in
            let cw = size.width / 4
            let ch = size.height / 24

            // Cells
            for i in 0..<96 {
                let rect = CGRect(x: CGFloat(i % 4) * cw, y: CGFloat(i / 4) * ch, width: cw, height: ch)
                    .insetBy(dx: 1, dy: 1)
                let path = Path(roundedRect: rect, cornerRadius: 3)
                ctx.fill(path, with: .color(colorMap[blocks[i]] ?? .gray))
            }

            // One emoji per contiguous run of a category within each row
            for row in 0..<24 {
                var col = 0
                while col < 4 {
                    let id = blocks[row * 4 + col]
                    var end = col
                    while end + 1 < 4 && blocks[row * 4 + end + 1] == id { end += 1 }
                    if let emoji = emojiMap[id] {
                        let center = CGPoint(
                            x: (CGFloat(col) + CGFloat(end - col + 1) / 2) * cw,
                            y: (CGFloat(row) + 0.5) * ch
                        )
                        ctx.draw(Text(emoji).font(.system(size: ch * 0.62)), at: center)
                    }
                    col = end + 1
                }
            }
        }
    }

    // MARK: Palette

    private var palette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { cat in
                    let id = UInt8(cat.id)
                    Button {
                        brush = id
                    } label: {
                        HStack(spacing: 4) {
                            Text(cat.emoji)
                            Text(cat.name)
                                .font(.system(.caption, design: .rounded, weight: .heavy))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(cat.color))
                        .overlay(
                            Capsule().stroke(brush == id ? Color.tbDeepBlue : .clear, lineWidth: 3)
                        )
                        .scaleEffect(brush == id ? 1.08 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: brush)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
    }

    // MARK: Painting

    private func paint(at point: CGPoint, in size: CGSize) {
        let col = min(max(Int(point.x / (size.width / 4)), 0), 3)
        let row = min(max(Int(point.y / (size.height / 24)), 0), 23)
        let index = row * 4 + col
        if blocks[index] != brush {
            blocks[index] = brush
            dirty = true
            paintCount += 1
        }
    }

    // MARK: Undo / redo

    /// Commits the finished stroke as one undo step, if it changed anything.
    private func endStroke() {
        if let snapshot = strokeSnapshot, snapshot != blocks {
            undoStack.append(snapshot)
            if undoStack.count > 100 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        strokeSnapshot = nil
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(blocks)
        blocks = previous
        dirty = true
        paintCount += 1
        save()
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(blocks)
        blocks = next
        dirty = true
        paintCount += 1
        save()
    }

    // MARK: Persistence

    private func load() {
        let key = dayKey
        let fetch = FetchDescriptor<DaySchedule>(predicate: #Predicate { $0.dayKey == key })
        if let existing = try? context.fetch(fetch).first {
            blocks = [UInt8](existing.blocks)
        } else {
            blocks = DayTemplate.defaultBlocks()
        }
        dirty = false
        undoStack.removeAll()
        redoStack.removeAll()
        strokeSnapshot = nil
    }

    /// Upserts the day — but only if the user actually painted something,
    /// so untouched template days never pollute saved data.
    private func save() {
        guard dirty else { return }
        let key = dayKey
        let data = Data(blocks)
        let fetch = FetchDescriptor<DaySchedule>(predicate: #Predicate { $0.dayKey == key })
        if let existing = try? context.fetch(fetch).first {
            existing.blocks = data
            existing.modifiedAt = .now
        } else {
            context.insert(DaySchedule(dayKey: key, blocks: data))
        }
        // Save explicitly: autosave may not flush before the app is killed
        try? context.save()
        dirty = false
    }

    // MARK: Date stepping

    private func step(by days: Int) {
        let next = Calendar.current.date(byAdding: .day, value: days, to: DayKey.date(from: dayKey)) ?? .now
        jump(to: DayKey.key(for: next))
    }

    private func jump(to key: Int) {
        guard DayKey.editableRange.contains(key) else { return }
        save()
        dayKey = key
        load()
    }

    private func canStep(by days: Int) -> Bool {
        let next = Calendar.current.date(byAdding: .day, value: days, to: DayKey.date(from: dayKey)) ?? .now
        return DayKey.editableRange.contains(DayKey.key(for: next))
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12 AM"
        case 1...11: return "\(hour) AM"
        case 12: return "12 PM"
        default: return "\(hour - 12) PM"
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ActivityCategory.self, DaySchedule.self, configurations: config)
    CategorySeeder.seedIfNeeded(container.mainContext)
    return NavigationStack {
        DayEditorView(dayKey: DayKey.key(for: .now))
    }
    .modelContainer(container)
}
