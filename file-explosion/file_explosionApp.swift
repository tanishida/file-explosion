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
    /// バックグラウンド移行時：tmpだけ全削除、復号キャッシュは10分以上前のものだけ削除
    static func clearAllTempAndCacheData() {
        FileManagerHelper.clearTempDirectory()
        FileManagerHelper.clearExpiredDecryptedCache(olderThan: 600)
    }
    
    /// 復号キャッシュを全消去（アプリ終了時など）
    static func clearDecryptedCache() {
        FileManagerHelper.clearTempCache()
    }
    
    static func clearCachesExcept(currentCacheURL: URL) {
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(
            at: FileManagerHelper.cacheDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in files {
                if file.lastPathComponent != currentCacheURL.lastPathComponent {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }
}
