//
//  TimeBlocksApp.swift
//  TimeBlocks
//
//  Created by Philip Renton on 10/11/26.
//

import SwiftUI
import SwiftData

@main
struct TimeBlocksApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ActivityCategory.self,
            DaySchedule.self,
            MonthTemplate.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
