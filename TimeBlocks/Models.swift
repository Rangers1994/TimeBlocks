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

// MARK: - Summary aggregation

enum SummaryCalculator {
    /// Counts 15-minute blocks per category id across a set of day blobs.
    /// Hours per category = count × 0.25.
    static func blockCounts(for dayBlobs: [Data]) -> [UInt8: Int] {
        var counts: [UInt8: Int] = [:]
        for blob in dayBlobs {
            for byte in blob {
                counts[byte, default: 0] += 1
            }
        }
        return counts
    }
}

// MARK: - Built-in category seeding

enum CategorySeeder {
    // `id` is the stable byte stored in day blobs and must never be reused;
    // `sort` is only the default display position.
    static let builtIns: [(id: Int, name: String, emoji: String, hex: String, sort: Int)] = [
        (0, "Free Time", "⭐️", "#FFD233", 0),
        (1, "Sleep", "🌙", "#52348C", 1),
        (2, "School", "📚", "#FF8C42", 2),
        (3, "Homework", "✏️", "#2D7DD2", 3),
        (4, "Sports", "🏃", "#4CAF50", 4),
        (8, "Activities", "🎵", "#AB47BC", 5),
        (5, "Get Ready", "🛁", "#78909C", 6),
        (6, "Meals", "🍽️", "#26A69A", 7),
        (7, "Travel", "🚌", "#9E9E9E", 8),
        (9, "Screen Time", "📱", "#EC407A", 9),
        (13, "Family", "✅", "#1D4E89", 10),
        (11, "Friends", "🧑‍🤝‍🧑", "#26C6DA", 11),
    ]

    /// Inserts any missing built-in categories. Runs on every launch so
    /// existing installs pick up newly added built-ins; user-created or
    /// user-edited categories are never touched.
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ActivityCategory>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        // One-time migration: "Ready & Travel" split into Get Ready + Travel.
        // Only renames if the user hasn't customized it.
        if let old = byID[5], old.name == "Ready & Travel" {
            old.name = "Get Ready"
            old.emoji = "🛁"
            old.colorHex = "#78909C"
        }
        // Follow-up migration: toothbrush proved too skinny in the grid
        if let getReady = byID[5], getReady.emoji == "🪥" {
            getReady.emoji = "🛁"
        }

        // Migration: built-in Family's emoji changed to a green check mark
        if let family = byID[13], family.isBuiltIn, family.emoji == "👨‍👩‍👧‍👦" {
            family.emoji = "✅"
        }

        // Migration: drop the short-lived built-in Family (id 10) — users
        // create their own. Any blocks painted with it become Free Time.
        if let brownFamily = byID[10], brownFamily.isBuiltIn, brownFamily.name == "Family" {
            remapBlocks(from: 10, to: 0, in: context)
            context.delete(brownFamily)
        }

        // One-time migration to the revised default ordering (Activities after
        // Sports, Family before Friends). Only applies while the ordering is
        // still the original scheme (sortOrder == id for every built-in), so a
        // user's custom ordering is never clobbered.
        let builtinCats = existing.filter(\.isBuiltIn)
        if !builtinCats.isEmpty, builtinCats.allSatisfy({ $0.sortOrder == $0.id }) {
            for spec in builtIns {
                byID[spec.id]?.sortOrder = spec.sort
            }
        }

        for spec in builtIns where byID[spec.id] == nil {
            context.insert(ActivityCategory(id: spec.id, name: spec.name, emoji: spec.emoji,
                                            colorHex: spec.hex, sortOrder: spec.sort, isBuiltIn: true))
        }
        try? context.save()
    }

    /// Rewrites every stored day and month template, replacing one category id
    /// with another.
    static func remapBlocks(from oldID: UInt8, to newID: UInt8, in context: ModelContext) {
        let days = (try? context.fetch(FetchDescriptor<DaySchedule>())) ?? []
        for day in days {
            var bytes = [UInt8](day.blocks)
            guard bytes.contains(oldID) else { continue }
            for i in bytes.indices where bytes[i] == oldID { bytes[i] = newID }
            day.blocks = Data(bytes)
        }
        let templates = (try? context.fetch(FetchDescriptor<MonthTemplate>())) ?? []
        for template in templates {
            var bytes = [UInt8](template.blocks)
            guard bytes.contains(oldID) else { continue }
            for i in bytes.indices where bytes[i] == oldID { bytes[i] = newID }
            template.blocks = Data(bytes)
        }
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
        // Round rather than truncate, so hex -> Color -> hex round-trips exactly
        return String(format: "#%02X%02X%02X", lround(r * 255), lround(g * 255), lround(b * 255))
    }
}
