//
//  CategorySeederTests.swift
//  TimeBlocksTests
//
//  Tests for category seeding, the migrations that evolve existing stores,
//  and block remapping — all against in-memory SwiftData containers.
//

import Testing
import Foundation
import SwiftData
@testable import TimeBlocks

struct CategorySeederTests {

    // MARK: Helpers

    private func freshContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ActivityCategory.self, DaySchedule.self, MonthTemplate.self,
            configurations: config
        )
        return ModelContext(container)
    }

    /// Recreates the original v1 seed (pre-split, 7 categories, sortOrder == id).
    private func insertLegacyCategories(into context: ModelContext) {
        let legacy: [(Int, String, String, String)] = [
            (0, "Free Time", "⭐️", "#FFD233"),
            (1, "Sleep", "🌙", "#52348C"),
            (2, "School", "📚", "#FF8C42"),
            (3, "Homework", "✏️", "#2D7DD2"),
            (4, "Sports", "🏃", "#4CAF50"),
            (5, "Ready & Travel", "🚌", "#9E9E9E"),
            (6, "Meals", "🍽️", "#26A69A"),
        ]
        for (id, name, emoji, hex) in legacy {
            context.insert(ActivityCategory(id: id, name: name, emoji: emoji,
                                            colorHex: hex, sortOrder: id, isBuiltIn: true))
        }
        try? context.save()
    }

    private func categoriesByID(_ context: ModelContext) throws -> [Int: ActivityCategory] {
        let all = try context.fetch(FetchDescriptor<ActivityCategory>())
        return Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    // MARK: Fresh installs

    @Test func seedsAllBuiltInsIntoEmptyStore() throws {
        let context = try freshContext()
        CategorySeeder.seedIfNeeded(context)

        let byID = try categoriesByID(context)
        #expect(byID.count == CategorySeeder.builtIns.count)
        for spec in CategorySeeder.builtIns {
            let cat = try #require(byID[spec.id], "missing built-in id \(spec.id)")
            #expect(cat.name == spec.name)
            #expect(cat.emoji == spec.emoji)
            #expect(cat.sortOrder == spec.sort)
            #expect(cat.isBuiltIn)
        }
    }

    @Test func seedingTwiceDoesNotDuplicate() throws {
        let context = try freshContext()
        CategorySeeder.seedIfNeeded(context)
        CategorySeeder.seedIfNeeded(context)
        let count = try context.fetchCount(FetchDescriptor<ActivityCategory>())
        #expect(count == CategorySeeder.builtIns.count)
    }

    @Test func defaultOrderPutsActivitiesAfterSportsAndFamilyBeforeFriends() throws {
        let context = try freshContext()
        CategorySeeder.seedIfNeeded(context)
        let ordered = try context.fetch(FetchDescriptor<ActivityCategory>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )).map(\.name)

        let sports = try #require(ordered.firstIndex(of: "Sports"))
        #expect(ordered[sports + 1] == "Activities")

        let friends = try #require(ordered.firstIndex(of: "Friends"))
        #expect(ordered[friends - 1] == "Family")
    }

    // MARK: Migrations of existing stores

    @Test func splitsReadyAndTravelIntoGetReadyAndTravel() throws {
        let context = try freshContext()
        insertLegacyCategories(into: context)

        CategorySeeder.seedIfNeeded(context)

        let byID = try categoriesByID(context)
        #expect(byID[5]?.name == "Get Ready")
        #expect(byID[5]?.emoji == "🛁")
        #expect(byID[7]?.name == "Travel")
        #expect(byID[7]?.emoji == "🚌")
        #expect(byID.count == CategorySeeder.builtIns.count)
    }

    @Test func doesNotTouchUserRenamedCategory() throws {
        let context = try freshContext()
        insertLegacyCategories(into: context)
        let byIDBefore = try categoriesByID(context)
        byIDBefore[5]?.name = "Morning Routine"   // user customized it
        try context.save()

        CategorySeeder.seedIfNeeded(context)

        let byID = try categoriesByID(context)
        #expect(byID[5]?.name == "Morning Routine")
        #expect(byID[5]?.emoji == "🚌")           // user's emoji kept too
        #expect(byID[7]?.name == "Travel")        // new built-ins still added
    }

    @Test func migratesLegacySortOrderToNewDefaults() throws {
        let context = try freshContext()
        insertLegacyCategories(into: context)

        CategorySeeder.seedIfNeeded(context)

        let byID = try categoriesByID(context)
        // Activities (id 8) slots in right after Sports (sort 4)
        #expect(byID[8]?.sortOrder == 5)
        #expect(byID[5]?.sortOrder == 6)          // Get Ready pushed after Activities
    }

    @Test func preservesUserCustomOrdering() throws {
        let context = try freshContext()
        insertLegacyCategories(into: context)
        let byIDBefore = try categoriesByID(context)
        byIDBefore[0]?.sortOrder = 99             // user moved Free Time to the end
        try context.save()

        CategorySeeder.seedIfNeeded(context)

        let byID = try categoriesByID(context)
        #expect(byID[0]?.sortOrder == 99)         // custom position untouched
        #expect(byID[5]?.sortOrder == 5)          // defaults NOT reapplied
    }

    @Test func removesBrownBuiltInFamilyAndRemapsItsBlocks() throws {
        let context = try freshContext()
        insertLegacyCategories(into: context)
        context.insert(ActivityCategory(id: 10, name: "Family", emoji: "👨‍👩‍👧‍👦",
                                        colorHex: "#8D6E63", sortOrder: 10, isBuiltIn: true))
        var blocks = DayTemplate.defaultBlocks()
        for i in 40..<48 { blocks[i] = 10 }       // two hours painted with it
        context.insert(DaySchedule(dayKey: 20261015, blocks: Data(blocks)))
        try context.save()

        CategorySeeder.seedIfNeeded(context)

        let byID = try categoriesByID(context)
        #expect(byID[10] == nil, "brown Family should be deleted")
        let day = try #require(context.fetch(FetchDescriptor<DaySchedule>()).first)
        #expect(![UInt8](day.blocks).contains(10), "its blocks become Free Time")
    }

    @Test func doesNotDeleteUserCategoryThatHappensToBeNamedFamily() throws {
        let context = try freshContext()
        insertLegacyCategories(into: context)
        context.insert(ActivityCategory(id: 10, name: "Family", emoji: "💗",
                                        colorHex: "#FF00FF", sortOrder: 10, isBuiltIn: false))
        try context.save()

        CategorySeeder.seedIfNeeded(context)

        let byID = try categoriesByID(context)
        #expect(byID[10] != nil, "user-created category must survive")
    }

    @Test(arguments: ["👨‍👩‍👧‍👦", "✅"])
    func migratesFamilyEmojiToRedHeart(oldEmoji: String) throws {
        let context = try freshContext()
        insertLegacyCategories(into: context)
        context.insert(ActivityCategory(id: 13, name: "Family", emoji: oldEmoji,
                                        colorHex: "#1D4E89", sortOrder: 10, isBuiltIn: true))
        try context.save()

        CategorySeeder.seedIfNeeded(context)

        let byID = try categoriesByID(context)
        #expect(byID[13]?.emoji == "❤️")
    }

    // MARK: Block remapping

    @Test func remapRewritesDaysAndTemplates() throws {
        let context = try freshContext()
        var dayBlocks = [UInt8](repeating: 0, count: 96)
        for i in 0..<8 { dayBlocks[i] = 9 }
        context.insert(DaySchedule(dayKey: 20261001, blocks: Data(dayBlocks)))

        var templateBlocks = [UInt8](repeating: 0, count: 96)
        templateBlocks[50] = 9
        context.insert(MonthTemplate(monthKey: 202610, kind: 0, blocks: Data(templateBlocks)))
        try context.save()

        CategorySeeder.remapBlocks(from: 9, to: 3, in: context)

        let day = try #require(context.fetch(FetchDescriptor<DaySchedule>()).first)
        #expect([UInt8](day.blocks).filter { $0 == 3 }.count == 8)
        #expect(![UInt8](day.blocks).contains(9))

        let template = try #require(context.fetch(FetchDescriptor<MonthTemplate>()).first)
        #expect([UInt8](template.blocks)[50] == 3)
        #expect(![UInt8](template.blocks).contains(9))
    }

    @Test func remapLeavesOtherCategoriesAlone() throws {
        let context = try freshContext()
        let original = DayTemplate.defaultBlocks()   // sleep (1) + free (0)
        context.insert(DaySchedule(dayKey: 20261002, blocks: Data(original)))
        try context.save()

        CategorySeeder.remapBlocks(from: 9, to: 3, in: context)

        let day = try #require(context.fetch(FetchDescriptor<DaySchedule>()).first)
        #expect([UInt8](day.blocks) == original)
    }
}
