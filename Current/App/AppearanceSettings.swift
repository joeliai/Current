import UIKit

enum AppearanceMode: String, CaseIterable {
    case automatic = "auto"
    case dark
    case light

    var title: String {
        switch self {
        case .automatic: "Auto"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var symbol: String {
        switch self {
        case .automatic: "circle.lefthalf.filled"
        case .dark: "moon"
        case .light: "sun.max"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .automatic: .unspecified
        case .dark: .dark
        case .light: .light
        }
    }
}

@MainActor
final class AppearanceSettings {
    static let preferenceKey = "appearanceMode"
    static let shared = AppearanceSettings(initialOverride: launchOverride)
    private let defaults: UserDefaults
    private(set) var mode: AppearanceMode

    init(defaults: UserDefaults = .standard, initialOverride: AppearanceMode? = nil) {
        self.defaults = defaults
        mode = initialOverride
            ?? defaults.string(forKey: Self.preferenceKey).flatMap(AppearanceMode.init(rawValue:))
            ?? .automatic
    }

    func select(_ mode: AppearanceMode, windows: [UIWindow]? = nil) {
        self.mode = mode
        // Even selecting a temporary launch override explicitly must save it.
        defaults.set(mode.rawValue, forKey: Self.preferenceKey)
        let windows = windows ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        windows.forEach(apply)
    }

    func apply(to window: UIWindow) {
        if window.overrideUserInterfaceStyle != mode.interfaceStyle {
            window.overrideUserInterfaceStyle = mode.interfaceStyle
        }
    }

    private static var launchOverride: AppearanceMode? {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--dark") { return .dark }
            if arguments.contains("--light") { return .light }
        #endif
        return nil
    }
}
