//
//  Localization.swift
//  pip_swift
//

import Foundation

enum L10n {
    static var usesChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    static func text(_ chinese: String, _ english: String) -> String {
        usesChinese ? chinese : english
    }

    static let versionDisplay = "1.0.9 beta1"

    static var appName: String { text("全局高刷", "Global Refresh") }
    static var floatingWindow: String { text("悬浮窗", "Floating") }
    static var frameRateDemo: String { text("帧率演示", "Frame Rate") }
    static var version: String { text("版本", "Version") }
    static var home: String { text("首页", "Home") }
    static var about: String { text("关于", "About") }
    static var changelog: String { text("更新日志", "Changelog") }
    static var faq: String { text("常见问题", "FAQ") }
    static var ok: String { text("确定", "OK") }
    static var cancel: String { text("取消", "Cancel") }
}
