//
//  PiPShortcutIntents.swift
//  pip_swift
//

import Foundation
import AppIntents

enum PiPShortcutAction: String {
    case startFloatingWindow
    case hideFloatingWindow
    case startAndHideFloatingWindow
}

enum PiPShortcutActionCenter {
    static let didRequestActionNotification = Notification.Name("pip.shortcutAction.requested")

    private static let pendingActionKey = "pip.shortcutAction.pending"

    static func request(_ action: PiPShortcutAction) {
        UserDefaults.standard.set(action.rawValue, forKey: pendingActionKey)
        UserDefaults.standard.synchronize()
        AppDebugLogger.log("Shortcut intent requested: \(action.rawValue)")
        NotificationCenter.default.post(name: didRequestActionNotification, object: action.rawValue)
    }

    static var hasPendingAction: Bool {
        guard let rawValue = UserDefaults.standard.string(forKey: pendingActionKey) else {
            return false
        }
        return PiPShortcutAction(rawValue: rawValue) != nil
    }

    static func notifyPendingActionIfNeeded() {
        guard let rawValue = UserDefaults.standard.string(forKey: pendingActionKey) else { return }
        NotificationCenter.default.post(name: didRequestActionNotification, object: rawValue)
    }

    static func consumePendingAction() -> PiPShortcutAction? {
        let defaults = UserDefaults.standard
        guard
            let rawValue = defaults.string(forKey: pendingActionKey),
            let action = PiPShortcutAction(rawValue: rawValue)
        else {
            return nil
        }
        defaults.removeObject(forKey: pendingActionKey)
        return action
    }
}

@available(iOS 26.0, *)
public struct StartFloatingWindowIntent: AppIntent {
    public static var title: LocalizedStringResource = "Open Floating Window"
    public static var description = IntentDescription("Open Global Refresh PiP")
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool = true
    public static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    public static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    public init() {}

    public func perform() async throws -> some IntentResult {
        PiPShortcutActionCenter.request(.startFloatingWindow)
        return .result()
    }
}

@available(iOS 26.0, *)
public struct HideFloatingWindowIntent: AppIntent {
    public static var title: LocalizedStringResource = "Hide Floating Window"
    public static var description = IntentDescription("Shrink the active docked floating window to 0.1 pt")
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool = true
    public static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    public static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    public init() {}

    public func perform() async throws -> some IntentResult {
        PiPShortcutActionCenter.request(.hideFloatingWindow)
        return .result()
    }
}

@available(iOS 26.0, *)
public struct StartAndHideFloatingWindowIntent: AppIntent {
    public static var title: LocalizedStringResource = "Open and Hide Floating Window"
    public static var description = IntentDescription("Open Global Refresh PiP, then shrink it to 0.1 pt")
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool = true
    public static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    public static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    public init() {}

    public func perform() async throws -> some IntentResult {
        PiPShortcutActionCenter.request(.startAndHideFloatingWindow)
        return .result()
    }
}

@available(iOS 26.0, *)
public struct AppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartAndHideFloatingWindowIntent(),
            phrases: [
                "\(.applicationName) open and hide floating window",
                "\(.applicationName) open hidden floating window"
            ],
            shortTitle: "Open and Hide",
            systemImageName: "pip.remove"
        )

        AppShortcut(
            intent: StartFloatingWindowIntent(),
            phrases: [
                "\(.applicationName) open floating window",
                "\(.applicationName) enable floating window"
            ],
            shortTitle: "Open Floating",
            systemImageName: "pip"
        )

        AppShortcut(
            intent: HideFloatingWindowIntent(),
            phrases: [
                "\(.applicationName) hide floating window",
                "\(.applicationName) shrink floating window"
            ],
            shortTitle: "Hide Floating",
            systemImageName: "eye.slash"
        )
    }

    public static var shortcutTileColor: ShortcutTileColor = .blue
}

enum PiPShortcutRuntimeRegistration {
    static func warmUpProviderIfAvailable() {
        guard #available(iOS 26.0, *) else { return }
        _ = AppShortcuts.appShortcuts.count
        AppShortcuts.updateAppShortcutParameters()
    }
}
