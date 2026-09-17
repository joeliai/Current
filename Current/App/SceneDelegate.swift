import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options _: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.tintColor = Palette.accent
        window.backgroundColor = Palette.background
        AppearanceSettings.shared.apply(to: window)
        window.rootViewController = MainTabBarController()
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_: UIScene) {
        BatteryMonitor.shared.start()
    }

    func sceneDidEnterBackground(_: UIScene) {
        BatteryMonitor.shared.pause()
    }

    func sceneDidDisconnect(_: UIScene) {
        BatteryMonitor.shared.pause()
    }
}
