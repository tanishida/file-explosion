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
        }.onChange(of: scenePhase) { phase in
            if phase == .background {
                StorageCleaner.clearAllTempAndCacheData()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

class StorageCleaner {
    static func clearAllTempAndCacheData() {
        let fileManager = FileManager.default
        
        // 1. tmpフォルダのお掃除
        let tempUrl = fileManager.temporaryDirectory
        if let tempFiles = try? fileManager.contentsOfDirectory(at: tempUrl, includingPropertiesForKeys: nil) {
            for file in tempFiles {
                try? fileManager.removeItem(at: file)
            }
        }
        
        // 2. Cachesフォルダのお掃除
        if let cacheUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            if let cacheFiles = try? fileManager.contentsOfDirectory(at: cacheUrl, includingPropertiesForKeys: nil) {
                for file in cacheFiles {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }
    static func clearCachesExcept(currentCacheURL: URL) {
        let fileManager = FileManager.default
        if let cacheUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            if let cacheFiles = try? fileManager.contentsOfDirectory(at: cacheUrl, includingPropertiesForKeys: nil) {
                for file in cacheFiles {
                    // 今画面に表示しているキャッシュファイル「以外」だったら削除
                    if file.lastPathComponent != currentCacheURL.lastPathComponent {
                        try? fileManager.removeItem(at: file)
                    }
                }
            }
        }
    }
}
