//
//  TimeBlocksTests.swift
//  TimeBlocksTests
//
//  Unit tests for the model layer: day keys, the default day template,
//  summary aggregation, template keys, and color hex round-trips.
//

import Testing
import Foundation
import SwiftUI
@testable import TimeBlocks

// MARK: - DayKey

struct DayKeyTests {

    @Test func encodesDateAsYYYYMMDD() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 19)))
        #expect(DayKey.key(for: date) == 20261019)
    }

    @Test func roundTripsToday() {
        let key = DayKey.key(for: .now)
        let date = DayKey.date(from: key)
        #expect(DayKey.key(for: date) == key)
    }

    @Test func handlesYearBoundary() throws {
        let newYearsEve = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31)))
        #expect(DayKey.key(for: newYearsEve) == 20261231)

        let nextDay = try #require(Calendar.current.date(byAdding: .day, value: 1, to: newYearsEve))
        #expect(DayKey.key(for: nextDay) == 20270101)
    }

    @Test func singleDigitMonthAndDayArePadded() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 5)))
        #expect(DayKey.key(for: date) == 20270105)
    }

    // Editable window: 12 months back through 1 month ahead
    @Test func editableWindowContainsToday() {
        #expect(DayKey.editableRange.contains(DayKey.key(for: .now)))
    }

    @Test func editableWindowIncludesNearFutureAndRecentPast() throws {
        let cal = Calendar.current
        let inTwoWeeks = try #require(cal.date(byAdding: .day, value: 14, to: .now))
        #expect(DayKey.editableRange.contains(DayKey.key(for: inTwoWeeks)))

        let sixMonthsAgo = try #require(cal.date(byAdding: .month, value: -6, to: .now))
        #expect(DayKey.editableRange.contains(DayKey.key(for: sixMonthsAgo)))
    }

    @Test func editableWindowExcludesFarFutureAndAgedOut() throws {
        let cal = Calendar.current
        let inTwoMonths = try #require(cal.date(byAdding: .month, value: 2, to: .now))
        #expect(!DayKey.editableRange.contains(DayKey.key(for: inTwoMonths)))

        let thirteenMonthsAgo = try #require(cal.date(byAdding: .month, value: -13, to: .now))
        #expect(!DayKey.editableRange.contains(DayKey.key(for: thirteenMonthsAgo)))
    }
}

// MARK: - Default day template

struct DayTemplateTests {

    @Test func hasExactly96Blocks() {
        #expect(DayTemplate.defaultBlocks().count == 96)
    }

    @Test func sleepIs8HoursStartingAt10PM() {
        let blocks = DayTemplate.defaultBlocks()
        // 32 sleep blocks (8h), 64 free-time blocks (16h)
        #expect(blocks.filter { $0 == 1 }.count == 32)
        #expect(blocks.filter { $0 == 0 }.count == 64)

        for hour in [22, 23, 0, 1, 2, 3, 4, 5] {
            for quarter in 0..<4 {
                #expect(blocks[hour * 4 + quarter] == 1, "hour \(hour) should be sleep")
            }
        }
        for hour in 6...21 {
            for quarter in 0..<4 {
                #expect(blocks[hour * 4 + quarter] == 0, "hour \(hour) should be free time")
            }
        }
    }
}

// MARK: - Summary aggregation

struct SummaryCalculatorTests {

    @Test func emptyInputYieldsNoCounts() {
        #expect(SummaryCalculator.blockCounts(for: []).isEmpty)
    }

    @Test func countsBlocksAcrossMultipleDays() {
        // Day 1: school (id 2) from 9:00 to 15:00, rest free time
        var day1 = [UInt8](repeating: 0, count: 96)
        for i in (9 * 4)..<(15 * 4) { day1[i] = 2 }
        // Day 2: untouched default template
        let day2 = DayTemplate.defaultBlocks()

        let counts = SummaryCalculator.blockCounts(for: [Data(day1), Data(day2)])

        #expect(counts[2] == 24)             // 6h school = 24 blocks
        #expect(counts[1] == 32)             // 8h sleep from the template day
        #expect(counts[0] == 72 + 64)        // free time from both days
        #expect(counts.values.reduce(0, +) == 192)
    }

    @Test func hoursConversion() {
        var day = [UInt8](repeating: 0, count: 96)
        for i in 0..<10 { day[i] = 4 }       // 10 blocks of sports
        let counts = SummaryCalculator.blockCounts(for: [Data(day)])
        #expect(Double(counts[4] ?? 0) * 0.25 == 2.5)   // 10 blocks = 2.5 hours
    }
}

// MARK: - Month templates

struct MonthTemplateTests {

    @Test func uniqueKeyCombinesMonthAndKind() {
        let weekday = MonthTemplate(monthKey: 202610, kind: 0, blocks: Data())
        let weekend = MonthTemplate(monthKey: 202610, kind: 1, blocks: Data())
        #expect(weekday.key == 2026100)
        #expect(weekend.key == 2026101)
        #expect(weekday.key != weekend.key)
    }

    @Test func recordsSourceDay() {
        let template = MonthTemplate(monthKey: 202610, kind: 0, blocks: Data(), sourceDayKey: 20261019)
        #expect(template.sourceDayKey == 20261019)
    }
}

// MARK: - Color hex

struct ColorHexTests {

    @Test(arguments: ["#FF8C42", "#2D7DD2", "#52348C", "#FFD233", "#000000", "#FFFFFF"])
    func roundTripsExactly(hex: String) {
        #expect(Color(hex: hex).hexString == hex)
    }
}
