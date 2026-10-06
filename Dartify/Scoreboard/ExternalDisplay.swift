//
//  ExternalDisplay.swift
//  Dartify
//

import SwiftUI
import UIKit

/// Gives an external display (AirPlay screen mirroring to an Apple TV, or a cable) its own scene showing the
/// scoreboard, instead of mirroring the phone's camera screen.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let isExternal = connectingSceneSession.role == .windowExternalDisplayNonInteractive
        print("[Dartify] scene connecting: \(connectingSceneSession.role.rawValue)")
        // "External Display" matches the configuration declared in Dartify-Info.plist.
        let configuration = UISceneConfiguration(name: isExternal ? "External Display" : nil, sessionRole: connectingSceneSession.role)
        if isExternal {
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
        }
        return configuration
    }
}

final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ScoreboardView(model: .shared))
        window.isHidden = false
        self.window = window
        Scoreboard.shared.tvConnected = true
        print("[Dartify] scoreboard shown on external display \(windowScene.screen.bounds.size)")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        Scoreboard.shared.tvConnected = false
    }
}
