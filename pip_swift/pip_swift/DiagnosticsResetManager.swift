//
//  DiagnosticsResetManager.swift
//  pip_swift
//

import Foundation

enum DiagnosticsResetManager {
    private static let storedBuildKey = "pip.diagnostics.lastBuild"

    static func resetDiagnosticsIfBuildChanged() {
        let defaults = UserDefaults.standard
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let previousBuild = defaults.string(forKey: storedBuildKey)
        guard previousBuild != currentBuild else { return }

        AppDebugLogger.resetLogs()
        KeepAliveLogger.resetLogs()
        MetricKitLogger.shared.resetLogs()
        PowerUsageLogger.resetStatistics()
        defaults.set(currentBuild, forKey: storedBuildKey)
    }
}
