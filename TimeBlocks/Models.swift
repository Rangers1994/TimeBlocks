//
//  Models.swift
//  TimeBlocks
//
//  Data model per DESIGN.md §3: a day is 96 bytes (one byte per 15-minute
//  block, holding a category id). Categories are reusable color+emoji labels.
//

import SwiftUI
import SwiftData

// MARK: - SwiftData models

@Model
final class ActivityCategory {
    @Attribute(.unique) var id: Int   // 0–255; stable index used in day blobs
    var name: String
    var emoji: String
    var colorHex: String
    var sortOrder: Int
    var isBuiltIn: Bool

    init(id: Int, name: String, emoji: String, colorHex: String, sortOrder: Int, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
    }

    var color: Color { Color(hex: colorHex) }
}

@Model
final class DaySchedule {
    @Attribute(.unique) var dayKey: Int   // yyyymmdd, e.g. 20261011
    var blocks: Data                      // exactly 96 bytes; blocks[i] = category id
    var modifiedAt: Date

    init(dayKey: Int, blocks: Data) {
        self.dayKey = dayKey
        self.blocks = blocks
        self.modifiedAt = .now
    }
}

/// A reusable day plan scoped to one month: each month can have one weekday
/// and one weekend template, set from any planned day and applied to other
/// days by drag and drop on the calendar.
@Model
final class MonthTemplate {
    @Attribute(.unique) var key: Int   // monthKey * 10 + kind
    var monthKey: Int                  // yyyymm, e.g. 202610
    var kind: Int                      // 0 = weekday, 1 = weekend
    var blocks: Data                   // 96 bytes, same format as DaySchedule
    var sourceDayKey: Int = 0          // dayKey the template was set from (0 = unknown)
    var modifiedAt: Date

    init(monthKey: Int, kind: Int, blocks: Data, sourceDayKey: Int = 0) {
        self.key = monthKey * 10 + kind
        self.monthKey = monthKey
        self.kind = kind
        self.blocks = blocks
        self.sourceDayKey = sourceDayKey
        self.modifiedAt = .now
    }
}

// MARK: - Day keys (yyyymmdd ints)

enum DayKey {
    static func key(for date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 2000) * 10000 + (c.month ?? 1) * 100 + (c.day ?? 1)
    }

    static func date(from key: Int) -> Date {
        var c = DateComponents()
        c.year = key / 10000
        c.month = (key / 100) % 100
        c.day = key % 100
        return Calendar.current.date(from: c) ?? .now
    }

    /// Editable window: 12 months back through 1 month ahead of today.
    static var editableRange: ClosedRange<Int> {
        let cal = Calendar.current
        let lower = cal.date(byAdding: .month, value: -12, to: .now) ?? .now
        let upper = cal.date(byAdding: .month, value: 1, to: .now) ?? .now
        return key(for: lower)...key(for: upper)
    }
}

// MARK: - Default day template

enum DayTemplate {
    /// Sleep (id 1) from 22:00–06:00, Free Time (id 0) everywhere else.
    static func defaultBlocks() -> [UInt8] {
        var blocks = [UInt8](repeating: 0, count: 96)
        for hour in [22, 23, 0, 1, 2, 3, 4, 5] {
            for quarter in 0..<4 {
                blocks[hour * 4 + quarter] = 1
            }
        }
        return blocks
    }
}

// MARK: - Built-in category seeding

enum CategorySeeder {
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<ActivityCategory>())) ?? 0
        guard count == 0 else { return }

        let builtIns: [(Int, String, String, String)] = [
            (0, "Free Time", "⭐️", "#FFD233"),
            (1, "Sleep", "🌙", "#52348C"),
            (2, "School", "📚", "#FF8C42"),
            (3, "Homework", "✏️", "#2D7DD2"),
            (4, "Sports", "🏃", "#4CAF50"),
            (5, "Ready & Travel", "🚌", "#9E9E9E"),
            (6, "Meals", "🍽️", "#26A69A"),
        ]
        for (id, name, emoji, hex) in builtIns {
            context.insert(ActivityCategory(id: id, name: name, emoji: emoji, colorHex: hex, sortOrder: id, isBuiltIn: true))
        }
        try? context.save()
    }
}

// MARK: - Hex color support

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
