//
//  ContentView.swift
//  TimeBlocks
//
//  Root tab layout (DESIGN.md §5): Calendar (home), Summary, Categories.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: Int = {
        #if DEBUG
        // "-tab summary|categories" selects an initial tab (screenshots/demos)
        if let i = CommandLine.arguments.firstIndex(of: "-tab"), i + 1 < CommandLine.arguments.count {
            switch CommandLine.arguments[i + 1] {
            case "summary": return 1
            case "categories": return 2
            default: return 0
            }
        }
        #endif
        return 0
    }()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Calendar", systemImage: "calendar", value: 0) {
                CalendarView()
            }
            Tab("Summary", systemImage: "chart.bar.fill", value: 1) {
                SummaryView()
            }
            Tab("Categories", systemImage: "paintpalette.fill", value: 2) {
                CategoriesView()
            }
        }
        .tint(.tbOrange)
        .task {
            CategorySeeder.seedIfNeeded(modelContext)
            #if DEBUG
            DemoDataSeeder.seedIfRequested(modelContext)
            #endif
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ActivityCategory.self, DaySchedule.self, MonthTemplate.self], inMemory: true)
}
