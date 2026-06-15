//
//  PiPShortcutIntents.swift
//  pip_swift
//

import Foundation
import AppIntents

enum PiPShortcutAction: String {
    case toggleFloatingWindow
    case hideFloatingWindow
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

@available(iOS 16.0, *)
struct ToggleFloatingWindowIntent: AppIntent {
    static var title: LocalizedStringResource = "开关悬浮窗"
    static var description = IntentDescription("打开或关闭全局高刷悬浮窗")
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    func perform() async throws -> some IntentResult {
        PiPShortcutActionCenter.request(.toggleFloatingWindow)
        return .result()
    }
}

@available(iOS 16.0, *)
struct HideFloatingWindowIntent: AppIntent {
    static var title: LocalizedStringResource = "隐藏悬浮窗"
    static var description = IntentDescription("将已开启并吸附到侧边的悬浮窗缩小到0.1pt")
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    func perform() async throws -> some IntentResult {
        PiPShortcutActionCenter.request(.hideFloatingWindow)
        return .result()
    }
}

@available(iOS 16.0, *)
struct GlobalRefreshShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleFloatingWindowIntent(),
            phrases: [
                "\(.applicationName)开关悬浮窗",
                "\(.applicationName)开启悬浮窗",
                "\(.applicationName)关闭悬浮窗"
            ],
            shortTitle: "开关悬浮窗",
            systemImageName: "pip"
        )

        AppShortcut(
            intent: HideFloatingWindowIntent(),
            phrases: [
                "\(.applicationName)隐藏悬浮窗",
                "\(.applicationName)缩小悬浮窗"
            ],
            shortTitle: "隐藏悬浮窗",
            systemImageName: "eye.slash"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .blue
}
