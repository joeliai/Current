@testable import Current
import UIKit
import XCTest

@MainActor
final class AppearanceSettingsTests: XCTestCase {
    func testMissingOrInvalidPreferenceFollowsSystem() throws {
        try withDefaults { defaults in
            let settings = AppearanceSettings(defaults: defaults)
            XCTAssertEqual(settings.mode, .automatic)
            XCTAssertEqual(settings.mode.interfaceStyle, .unspecified)
            defaults.set("unknown-value", forKey: AppearanceSettings.preferenceKey)
            XCTAssertEqual(AppearanceSettings(defaults: defaults).mode, .automatic)
        }
    }

    func testAllChoicesSurviveRecreatingSettings() throws {
        try withDefaults { defaults in
            let settings = AppearanceSettings(defaults: defaults)
            for mode in AppearanceMode.allCases {
                settings.select(mode, windows: [])
                XCTAssertEqual(defaults.string(forKey: AppearanceSettings.preferenceKey), mode.rawValue)
                XCTAssertEqual(AppearanceSettings(defaults: defaults).mode, mode)
            }
        }
    }

    func testChoiceAppliesToAllWindowsAndAutoRemovesOverrides() throws {
        try withDefaults { defaults in
            let settings = AppearanceSettings(defaults: defaults)
            let windows = try [makeWindow(), makeWindow()]
            for mode in [AppearanceMode.dark, .light, .automatic] {
                settings.select(mode, windows: windows)
                XCTAssertTrue(windows.allSatisfy { $0.overrideUserInterfaceStyle == mode.interfaceStyle })
            }
            XCTAssertTrue(windows.allSatisfy { $0.overrideUserInterfaceStyle == .unspecified })
        }
    }

    func testSavedChoiceIsAppliedToANewWindowBeforePresentation() throws {
        try withDefaults { defaults in
            defaults.set("dark", forKey: AppearanceSettings.preferenceKey)
            let settings = AppearanceSettings(defaults: defaults)
            let window = try makeWindow()
            settings.apply(to: window)
            XCTAssertEqual(window.overrideUserInterfaceStyle, .dark)
        }
    }

    func testDebugOverrideDoesNotOverwriteSavedChoice() throws {
        try withDefaults { defaults in
            defaults.set("light", forKey: AppearanceSettings.preferenceKey)
            let settings = AppearanceSettings(defaults: defaults, initialOverride: .dark)
            XCTAssertEqual(settings.mode, .dark)
            XCTAssertEqual(AppearanceSettings(defaults: defaults).mode, .light)
        }
    }

    func testExplicitlySelectingTheOverridePersistsIt() throws {
        try withDefaults { defaults in
            defaults.set("light", forKey: AppearanceSettings.preferenceKey)
            let settings = AppearanceSettings(defaults: defaults, initialOverride: .dark)
            settings.select(.dark, windows: [])
            XCTAssertEqual(AppearanceSettings(defaults: defaults).mode, .dark)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "Current.AppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func makeWindow() throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        return UIWindow(windowScene: scene)
    }
}
