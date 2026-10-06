//
//  DartifyApp.swift
//  Dartify
//
//  Created by Max Eidet on 2026-09-24.
//

import SwiftUI
import SwiftData

@main
struct DartifyApp: App {
    /// Puts the scoreboard on an external display (AirPlay to Apple TV).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
        }
        .modelContainer(sharedModelContainer)
    }
}
