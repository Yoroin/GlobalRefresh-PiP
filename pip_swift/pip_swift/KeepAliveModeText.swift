//
//  KeepAliveModeText.swift
//  pip_swift
//

import Foundation

enum KeepAliveModeText {
    private static let lowPowerDefaultMigrationKey = "pip.keepAlive.lowPowerDefaultMigration.1.0.7"

    static var current: String {
        ensureDefaultIfNeeded()
        return UserDefaults.standard.bool(forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey) ? "音频强保活" : "PiP保活-低功耗"
    }

    static var currentDescription: String {
        ensureDefaultIfNeeded()
        return UserDefaults.standard.bool(forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
            ? "音频强保活，强力保活方案，缺点较为耗电，且小部分场景可能影响音频，已默认不再使用，仅适合超强保活且不在意耗电的需求用户"
            : "新方案仅PiP保活，经实测较老方案更为省电，保活效果一致，并且解决音频冲突问题，优先推荐"
    }

    static func migrateDefaultToLowPowerPiPIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: lowPowerDefaultMigrationKey) else { return }
        defaults.set(false, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
        defaults.set(true, forKey: lowPowerDefaultMigrationKey)
    }

    private static func ensureDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey) == nil else { return }
        if let legacyPiPOnly = defaults.object(forKey: ViewController.userDefaultsIOS26PiPOnlyKeepAliveKey) as? Bool {
            defaults.set(!legacyPiPOnly, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
        } else {
            defaults.set(false, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
        }
    }
}
