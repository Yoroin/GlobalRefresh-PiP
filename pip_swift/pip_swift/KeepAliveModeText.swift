//
//  KeepAliveModeText.swift
//  pip_swift
//

import Foundation

enum KeepAlivePolicy: String, CaseIterable, Identifiable {
    case pipOnly
    case lockScreenAudio
    case audioAlways

    static let defaultsKey = "pip.keepAlive.experimentalPolicy.beta8g.v1"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pipOnly:
            return L10n.text("PiP保活-低功耗", "PiP Keep-alive")
        case .lockScreenAudio:
            return L10n.text("锁屏音频增强", "Lock-screen Audio Boost")
        case .audioAlways:
            return L10n.text("音频强保活", "Audio Keep-alive")
        }
    }

    var diagnosticsName: String {
        switch self {
        case .pipOnly: return "PiP保活-低功耗"
        case .lockScreenAudio: return "锁屏音频增强-BETA"
        case .audioAlways: return "音频强保活"
        }
    }

    var isExperimental: Bool {
        self == .lockScreenAudio
    }

    var detail: String {
        switch self {
        case .pipOnly:
            return L10n.text(
                "仅使用PiP保活，更省电并避免音频冲突，默认推荐。",
                "Uses PiP-only keep-alive to reduce power use and avoid audio conflicts. Recommended by default."
            )
        case .lockScreenAudio:
            return L10n.text(
                "beta：亮屏和未锁屏时仅PiP；收到系统锁屏事件后启用静音音频，解锁或亮屏后立即恢复仅PiP。",
                "beta: Uses PiP-only while unlocked, starts silent audio after the system reports a lock event, and immediately returns to PiP-only after unlock or foreground activation."
            )
        case .audioAlways:
            return L10n.text(
                "持续使用静音音频增强保活，耗电更高，部分场景可能影响音频，仅建议有超强保活需求时使用。",
                "Continuously uses silent audio for stronger keep-alive. It uses more power and may affect audio in some situations."
            )
        }
    }

    var usesAudioContinuously: Bool {
        self == .audioAlways
    }

    var usesAudioWhileLocked: Bool {
        self == .lockScreenAudio
    }

    static var current: KeepAlivePolicy {
        get {
            migrateLegacyPreferenceIfNeeded()
            let defaults = UserDefaults.standard
            let rawValue = defaults.string(forKey: defaultsKey) ?? KeepAlivePolicy.pipOnly.rawValue
            if rawValue == "pipOnlyEnhanced" {
                defaults.set(KeepAlivePolicy.pipOnly.rawValue, forKey: defaultsKey)
                defaults.set(false, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
                defaults.set(true, forKey: ViewController.userDefaultsIOS26PiPOnlyKeepAliveKey)
                return .pipOnly
            }
            return KeepAlivePolicy(rawValue: rawValue) ?? .pipOnly
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.rawValue, forKey: defaultsKey)
            defaults.set(newValue == .audioAlways, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
            defaults.set(newValue != .audioAlways, forKey: ViewController.userDefaultsIOS26PiPOnlyKeepAliveKey)
        }
    }

    static func migrateLegacyPreferenceIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: defaultsKey) == nil else { return }

        if let audioEnabled = defaults.object(forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey) as? Bool {
            current = audioEnabled ? .audioAlways : .pipOnly
        } else if let legacyPiPOnly = defaults.object(forKey: ViewController.userDefaultsIOS26PiPOnlyKeepAliveKey) as? Bool {
            current = legacyPiPOnly ? .pipOnly : .audioAlways
        } else {
            current = .pipOnly
        }
    }
}

enum KeepAliveModeText {
    private static let lowPowerDefaultMigrationKey = "pip.keepAlive.lowPowerDefaultMigration.1.0.7"

    static var current: String {
        KeepAlivePolicy.current.title
    }

    static var currentDescription: String {
        KeepAlivePolicy.current.detail
    }

    static func migrateDefaultToLowPowerPiPIfNeeded() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: lowPowerDefaultMigrationKey) {
            defaults.set(false, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
            defaults.set(true, forKey: ViewController.userDefaultsIOS26PiPOnlyKeepAliveKey)
            defaults.set(true, forKey: lowPowerDefaultMigrationKey)
        }
        KeepAlivePolicy.migrateLegacyPreferenceIfNeeded()
    }
}
