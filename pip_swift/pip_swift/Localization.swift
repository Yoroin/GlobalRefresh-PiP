//
//  Localization.swift
//  pip_swift
//

import Foundation

enum L10n {
    enum Language: String {
        case chinese = "zh"
        case english = "en"

        var usesChinese: Bool {
            self == .chinese
        }

        var toggled: Language {
            usesChinese ? .english : .chinese
        }
    }

    static let languageDidChangeNotification = Notification.Name("L10n.languageDidChangeNotification")

    static let languageOverrideKey = "app.language.override"
    private static let systemLanguageMarkerKey = "app.language.lastSystem"

    static var languageOverride: Language? {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: languageOverrideKey) else {
                return nil
            }
            return Language(rawValue: rawValue)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: languageOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: languageOverrideKey)
            }
        }
    }

    static var systemLanguage: Language {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .chinese : .english
    }

    static var currentLanguage: Language {
        if let languageOverride {
            return languageOverride
        }
        return systemLanguage
    }

    static var usesChinese: Bool {
        currentLanguage.usesChinese
    }

    static func text(_ chinese: String, _ english: String) -> String {
        usesChinese ? chinese : english
    }

    static var languageToggleTitle: String {
        usesChinese ? "EN" : "中"
    }

    static func toggleLanguageOverride() {
        languageOverride = currentLanguage.toggled
        NotificationCenter.default.post(name: languageDidChangeNotification, object: nil)
    }

    static func rememberCurrentSystemLanguageIfNeeded() {
        if UserDefaults.standard.string(forKey: systemLanguageMarkerKey) == nil {
            UserDefaults.standard.set(systemLanguage.rawValue, forKey: systemLanguageMarkerKey)
        }
    }

    static func followSystemLanguageIfActuallyChanged() {
        let currentSystemLanguage = systemLanguage.rawValue
        let previousSystemLanguage = UserDefaults.standard.string(forKey: systemLanguageMarkerKey)
        guard previousSystemLanguage != currentSystemLanguage else { return }
        UserDefaults.standard.set(currentSystemLanguage, forKey: systemLanguageMarkerKey)
        followSystemLanguageAndNotify()
    }

    static func followSystemLanguageAndNotify() {
        languageOverride = nil
        UserDefaults.standard.set(systemLanguage.rawValue, forKey: systemLanguageMarkerKey)
        NotificationCenter.default.post(name: languageDidChangeNotification, object: nil)
    }

    static var versionDisplay: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0fix"
    }

    static var isBetaBuild: Bool {
        let normalizedVersion = versionDisplay.lowercased()
        return normalizedVersion.contains("beta")
            || normalizedVersion.contains("alpha")
            || normalizedVersion.contains("test")
            || normalizedVersion.contains("测试")
    }

    static var appName: String { text("全局高刷", "Global Refresh") }
    static var floatingWindow: String { text("悬浮窗", "Floating") }
    static var frameRateDemo: String { text("帧率演示", "Frame Rate") }
    static var version: String { text("版本", "Version") }
    static var home: String { text("首页", "Home") }
    static var about: String { text("关于", "About") }
    static var changelog: String { text("更新日志", "Changelog") }
    static var faq: String { text("常见问题", "FAQ") }
    static var cacheCleanupTitle: String { text("清理缓存", "Clear Cache") }
    static var cacheCleanupMessage: String {
        text(
            "将删除 App 缓存和历史临时视频，不会清理设置、内置素材或诊断日志。正在运行的悬浮窗会保留当前媒体缓存。",
            "This removes app caches and old temporary videos. Settings, bundled assets, and diagnostic logs are kept. The active PiP media cache is preserved."
        )
    }
    static var cacheCleanupConfirm: String { text("清理", "Clear") }
    static var cacheCleanupCompleted: String { text("缓存清理完成", "Cache Cleared") }
    static var ok: String { text("确定", "OK") }
    static var cancel: String { text("取消", "Cancel") }
}
