import UIKit

final class MainTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let charging = navigationController(
            for: ChargingViewController(), title: "Charging", symbol: "bolt.fill", tag: 0
        )
        let health = navigationController(
            for: HealthViewController(), title: "Health", symbol: "heart.text.clipboard", tag: 1
        )
        let sessions = navigationController(
            for: SessionsViewController(), title: "Sessions", symbol: "chart.xyaxis.line", tag: 2
        )
        viewControllers = [charging, health, sessions]
        tabBar.tintColor = Palette.accent
        tabBar.accessibilityIdentifier = "mainTabs"
    }

    private func navigationController(
        for controller: UIViewController, title: String, symbol: String, tag: Int
    ) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: controller)
        navigation.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), tag: tag)
        navigation.tabBarItem.accessibilityIdentifier = "tab.\(title.lowercased())"
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: Palette.ink]
        navigation.navigationBar.standardAppearance = appearance
        navigation.navigationBar.scrollEdgeAppearance = appearance
        return navigation
    }
}
