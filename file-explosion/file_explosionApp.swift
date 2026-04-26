//
//  file_explosionApp.swift
//  file-explosion
//
//  Created by hiroaki nishida on 2026/04/19.
//

import SwiftUI
import SwiftData

@main
struct file_explosionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
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
            ContentView()
        }.onChange(of: scenePhase) { _, phase in
            if phase == .background {
                StorageCleaner.clearAllTempAndCacheData()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
