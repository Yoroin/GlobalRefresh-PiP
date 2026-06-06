//
//  KeepAliveModeText.swift
//  pip_swift
//

import Foundation

enum KeepAliveModeText {
    static var current: String {
        ensureDefaultIfNeeded()
        return UserDefaults.standard.bool(forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey) ? "音频强保活" : "仅PiP保活"
    }

    private static func ensureDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey) == nil else { return }
        if let legacyPiPOnly = defaults.object(forKey: ViewController.userDefaultsIOS26PiPOnlyKeepAliveKey) as? Bool {
            defaults.set(!legacyPiPOnly, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
        } else {
            defaults.set(true, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
        }
    }
}
