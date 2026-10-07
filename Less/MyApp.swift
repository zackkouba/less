import SwiftUI
import UIKit

private enum QuickAction {
    static let settingsType = "com.less.open-settings"

    @MainActor
    static func open(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard shortcutItem.type == settingsType else { return false }
        AppNavigation.shared.showsSettings = true
        return true
    }
}

@MainActor
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            _ = QuickAction.open(shortcutItem)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem
    ) async -> Bool {
        QuickAction.open(shortcutItem)
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.shortcutItems = [
            UIApplicationShortcutItem(
                type: QuickAction.settingsType,
                localizedTitle: "Settings",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "gearshape"),
                userInfo: nil
            )
        ]

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = SceneDelegate.self
        }
        return configuration
    }
}

@main
struct LessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
