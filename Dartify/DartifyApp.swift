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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Shared with MatchController, which saves finished matches outside of any view.
        .modelContainer(StatsStore.container)
    }
}
