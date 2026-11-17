import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // An external monitor gets its own scene. Building the app in it would
        // show a second, unrelated page on the monitor, and on iPads without
        // extended display support nothing can reach it. Drop the scene so
        // iPadOS falls back to mirroring the iPad screen.
        guard session.role == .windowApplication else {
            DispatchQueue.main.async {
                UIApplication.shared.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
            }
            return
        }
        let window = UIWindow(windowScene: windowScene)
        // Must be the root view controller: UIKit asks the root for
        // prefersPointerLocked, and RootViewController forwards to the browser.
        window.rootViewController = RootViewController()
        // Dark throughout: onboarding, menus, sheets and alerts match the game pages.
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        self.window = window
    }
}
