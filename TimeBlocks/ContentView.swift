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

    var body: some View {
        TabView {
            Tab("Calendar", systemImage: "calendar") {
                CalendarView()
            }
            Tab("Summary", systemImage: "chart.bar.fill") {
                SummaryView()
            }
            Tab("Categories", systemImage: "paintpalette.fill") {
                CategoriesView()
            }
        }
        .tint(.tbOrange)
        .task {
            CategorySeeder.seedIfNeeded(modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ActivityCategory.self, DaySchedule.self], inMemory: true)
}
