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

enum PiPShortcutFeatureAccess {
    static let enabledKey = "pip.shortcut.featureEnabled.v1"
    private static let pendingBlockedNoticeKey = "pip.shortcut.pendingBlockedNotice.v1"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: enabledKey)
        if !enabled {
            PiPShortcutActionCenter.discardPendingAction(reason: "shortcut features disabled")
        }
        defaults.synchronize()
        PiPShortcutRuntimeRegistration.refreshProviderIfAvailable()
    }

    static func recordBlockedAttempt() {
        UserDefaults.standard.set(true, forKey: pendingBlockedNoticeKey)
    }

    static func consumeBlockedAttempt() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: pendingBlockedNoticeKey) else { return false }
        defaults.removeObject(forKey: pendingBlockedNoticeKey)
        return true
    }
}

enum PiPShortcutInstallLinks {
    // Fill these after sharing the matching shortcuts from the Shortcuts app.
    // Example: "https://www.icloud.com/shortcuts/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    private static let startAndHideICloudLink = "https://www.icloud.com/shortcuts/5101796358454ce8a5fadc0c41cf51c7"
    private static let startICloudLink = "https://www.icloud.com/shortcuts/52566891402d4028b6c2ce511ab4eb6b"
    private static let hideICloudLink = "https://www.icloud.com/shortcuts/cc90abcb853a43e9be3db938e030a6eb"

    static let primaryScheme = "globalrefresh"

    static var installableActions: [PiPShortcutAction] {
        [.startAndHideFloatingWindow, .startFloatingWindow, .hideFloatingWindow]
    }

    static func fallbackURLString(for action: PiPShortcutAction) -> String {
        "\(primaryScheme)://\(urlPath(for: action))"
    }

    static func fallbackURL(for action: PiPShortcutAction) -> URL {
        URL(string: fallbackURLString(for: action))!
    }

    static func iCloudURL(for action: PiPShortcutAction) -> URL? {
        let value: String
        switch action {
        case .startFloatingWindow:
            value = startICloudLink
        case .hideFloatingWindow:
            value = hideICloudLink
        case .startAndHideFloatingWindow:
            value = startAndHideICloudLink
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private static func urlPath(for action: PiPShortcutAction) -> String {
        switch action {
        case .startFloatingWindow:
            return "start"
        case .hideFloatingWindow:
            return "hide"
        case .startAndHideFloatingWindow:
            return "startandhide"
        }
    }
}

enum PiPShortcutActionCenter {
    static let didRequestActionNotification = Notification.Name("pip.shortcutAction.requested")
    static let darwinNotificationName = "test.kaifa2.pip.shortcutAction.requested"

    private static let pendingActionKey = "pip.shortcutAction.pending"
    private static let pendingActionTimestampKey = "pip.shortcutAction.pendingTimestamp"
    private static let pendingActionMaximumAge: TimeInterval = 120
    private static let supportedURLSchemes: Set<String> = ["globalrefresh", "quanjiagaoshua", "pipshortcut"]

    @discardableResult
    static func request(_ action: PiPShortcutAction) -> Bool {
        guard PiPShortcutFeatureAccess.isEnabled else {
            PiPShortcutFeatureAccess.recordBlockedAttempt()
            AppDebugLogger.log("Shortcut action blocked because shortcut features are disabled: \(action.rawValue)")
            return false
        }
        UserDefaults.standard.set(action.rawValue, forKey: pendingActionKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: pendingActionTimestampKey)
        UserDefaults.standard.synchronize()
        AppDebugLogger.log("Shortcut intent requested: \(action.rawValue)")
        NotificationCenter.default.post(name: didRequestActionNotification, object: action.rawValue)
        postDarwinNotification()
        return true
    }

    static var hasPendingAction: Bool {
        guard PiPShortcutFeatureAccess.isEnabled else { return false }
        let defaults = UserDefaults.standard
        defaults.synchronize()
        guard let rawValue = defaults.string(forKey: pendingActionKey) else { return false }
        return PiPShortcutAction(rawValue: rawValue) != nil
    }

    static var pendingAction: PiPShortcutAction? {
        guard PiPShortcutFeatureAccess.isEnabled else { return nil }
        let defaults = UserDefaults.standard
        defaults.synchronize()
        guard let rawValue = validPendingActionRawValue(defaults: defaults, shouldRemoveExpired: true) else { return nil }
        return PiPShortcutAction(rawValue: rawValue)
    }

    static func notifyPendingActionIfNeeded() {
        guard PiPShortcutFeatureAccess.isEnabled else { return }
        let defaults = UserDefaults.standard
        defaults.synchronize()
        guard let rawValue = validPendingActionRawValue(defaults: defaults, shouldRemoveExpired: true) else { return }
        NotificationCenter.default.post(name: didRequestActionNotification, object: rawValue)
    }

    static func consumePendingAction() -> PiPShortcutAction? {
        guard PiPShortcutFeatureAccess.isEnabled else {
            discardPendingAction(reason: "shortcut features disabled before consumption")
            return nil
        }
        let defaults = UserDefaults.standard
        defaults.synchronize()
        guard
            let rawValue = validPendingActionRawValue(defaults: defaults, shouldRemoveExpired: true),
            let action = PiPShortcutAction(rawValue: rawValue)
        else {
            return nil
        }
        defaults.removeObject(forKey: pendingActionKey)
        defaults.removeObject(forKey: pendingActionTimestampKey)
        defaults.synchronize()
        return action
    }

    private static func validPendingActionRawValue(defaults: UserDefaults, shouldRemoveExpired: Bool) -> String? {
        guard let rawValue = defaults.string(forKey: pendingActionKey) else { return nil }
        let timestamp = defaults.double(forKey: pendingActionTimestampKey)
        guard timestamp > 0 else {
            guard PiPShortcutAction(rawValue: rawValue) != nil else {
                discardPendingAction(defaults: defaults, reason: "missing timestamp", shouldRemove: shouldRemoveExpired)
                return nil
            }
            return rawValue
        }

        let age = Date().timeIntervalSince1970 - timestamp
        guard age >= 0, age <= pendingActionMaximumAge else {
            discardPendingAction(defaults: defaults, reason: "expired age=\(String(format: "%.1f", age))s", shouldRemove: shouldRemoveExpired)
            return nil
        }
        return rawValue
    }

    private static func discardPendingAction(defaults: UserDefaults, reason: String, shouldRemove: Bool) {
        AppDebugLogger.log("Shortcut pending action discarded: \(reason)")
        guard shouldRemove else { return }
        defaults.removeObject(forKey: pendingActionKey)
        defaults.removeObject(forKey: pendingActionTimestampKey)
        defaults.synchronize()
    }

    static func discardPendingAction(reason: String) {
        discardPendingAction(defaults: .standard, reason: reason, shouldRemove: true)
    }

    @discardableResult
    static func request(from url: URL) -> Bool {
        guard
            let scheme = url.scheme?.lowercased(),
            supportedURLSchemes.contains(scheme),
            let action = action(from: url)
        else {
            AppDebugLogger.log("Shortcut URL ignored: \(url.absoluteString)")
            return false
        }

        return request(action)
    }

    private static func action(from url: URL) -> PiPShortcutAction? {
        var tokens = ([url.host] + url.pathComponents)
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() }
            .filter { !$0.isEmpty && $0 != "shortcut" }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let queryTokens = (components.queryItems ?? []).flatMap { item -> [String] in
                [item.name, item.value].compactMap { $0 }
            }
            tokens.append(contentsOf: queryTokens)
        }

        if let fragment = url.fragment, !fragment.isEmpty {
            tokens.append(fragment)
        }

        for token in tokens.reversed() {
            switch normalizedActionToken(token) {
            case "start", "open", "enable", "openfloatingwindow", "startfloatingwindow":
                return .startFloatingWindow
            case "hide", "hidden", "shrink", "hidefloatingwindow", "shrinkfloatingwindow":
                return .hideFloatingWindow
            case "starthide", "startandhide", "openhide", "openandhide", "startandhidefloatingwindow", "openandhidefloatingwindow":
                return .startAndHideFloatingWindow
            default:
                continue
            }
        }
        return nil
    }

    private static func normalizedActionToken(_ token: String) -> String {
        token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func postDarwinNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: darwinNotificationName as CFString),
            nil,
            nil,
            true
        )
    }
}

@available(iOS 26.0, *)
public struct StartFloatingWindowIntent: AppIntent {
    public static var title: LocalizedStringResource = "打开悬浮窗"
    public static var description = IntentDescription("打开全局高刷悬浮窗")
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool { PiPShortcutFeatureAccess.isEnabled }
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
    public static var title: LocalizedStringResource = "一键0.1pt"
    public static var description = IntentDescription("将已吸附的悬浮窗缩小到0.1pt")
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool { PiPShortcutFeatureAccess.isEnabled }
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
    public static var title: LocalizedStringResource = "打开并一键0.1pt"
    public static var description = IntentDescription("打开全局高刷悬浮窗并缩小到0.1pt")
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool { PiPShortcutFeatureAccess.isEnabled }
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
                "\(.applicationName) 打开并一键0.1pt",
                "\(.applicationName) 打开并隐藏悬浮窗"
            ],
            shortTitle: "打开并一键0.1pt",
            systemImageName: "pip.remove"
        )

        AppShortcut(
            intent: StartFloatingWindowIntent(),
            phrases: [
                "\(.applicationName) 打开悬浮窗",
                "\(.applicationName) 开启悬浮窗"
            ],
            shortTitle: "打开悬浮窗",
            systemImageName: "pip"
        )

        AppShortcut(
            intent: HideFloatingWindowIntent(),
            phrases: [
                "\(.applicationName) 一键0.1pt",
                "\(.applicationName) 隐藏悬浮窗"
            ],
            shortTitle: "一键0.1pt",
            systemImageName: "eye.slash"
        )
    }

    public static var shortcutTileColor: ShortcutTileColor = .blue
}

enum PiPShortcutRuntimeRegistration {
    static func warmUpProviderIfAvailable() {
        refreshProviderIfAvailable()
    }

    static func refreshProviderIfAvailable() {
        guard #available(iOS 26.0, *) else { return }
        _ = AppShortcuts.appShortcuts.count
        AppShortcuts.updateAppShortcutParameters()
    }
}
