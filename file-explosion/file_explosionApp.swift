//
//  file_explosionApp.swift
//  file-explosion
//
//  Created by hiroaki nishida on 2026/04/19.
//

import SwiftUI
import SwiftData
import UserNotifications

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
    }
}
#else
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        return true
    }
}
#endif

@main
struct file_explosionApp: App {
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#else
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // 通知用のマネージャーをアプリ起動の一番最初で初期化＆権限確保
        _ = NotificationManager.shared
    }
    
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
