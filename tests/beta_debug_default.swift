import Foundation

// Execute the production reset logic with an isolated bundle and preferences store.
enum Bundle { static let main = TestBundle() }
final class TestBundle { var infoDictionary: [String: Any]? = [:] }
final class UserDefaults {
    static let standard = UserDefaults()
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func set(_ value: Any, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}
enum AppDebugLogger {
    static var isDebugModeEnabled = false
    static var transitions: [String] = []
    static func logRuntime(_ message: String) { transitions.append(message) }
}
enum DiagnosticsRuntimeState { static func stopAppStateTracking() {} }
final class MetricKitLogger {
    static let shared = MetricKitLogger()
    func stop() {}
    func resetLogs() {}
}
enum DebugDiagnosticsMonitor {
    static func stop() {}
    static func setEnabled(_ enabled: Bool) {}
}

func runTests() {
    let store = UserDefaults.standard
    Bundle.main.infoDictionary = ["CFBundleVersion": "test1", "DefaultDebugModeEnabled": true]
    DiagnosticsResetManager.applyDiagnosticsDefaultsIfBuildChanged()
    precondition(AppDebugLogger.isDebugModeEnabled && AppDebugLogger.transitions.isEmpty)
    AppDebugLogger.isDebugModeEnabled = false
    DiagnosticsResetManager.applyDiagnosticsDefaultsIfBuildChanged()
    precondition(!AppDebugLogger.isDebugModeEnabled && AppDebugLogger.transitions.isEmpty)
    store.set("seeded-exit", forKey: "previous-evidence")
    store.set("seeded-metrickit", forKey: "metrickit-history")
    store.set(true, forKey: "old-process-active")
    store.set(true, forKey: "keepalive-active")
    store.set(123.0, forKey: "old-checkpoint")
    store.set(123.0, forKey: "keepalive-background-start")
    Bundle.main.infoDictionary = ["CFBundleVersion": "test2", "DefaultDebugModeEnabled": true]
    DiagnosticsResetManager.applyDiagnosticsDefaultsIfBuildChanged()
    precondition(AppDebugLogger.isDebugModeEnabled && AppDebugLogger.transitions.count == 1)
    precondition(AppDebugLogger.transitions[0].contains("test1 → test2"))
    precondition(!store.bool(forKey: "old-process-active") && !store.bool(forKey: "keepalive-active"))
    precondition(store.double(forKey: "keepalive-background-start") == 0)
    Bundle.main.infoDictionary = ["CFBundleVersion": "release"]
    DiagnosticsResetManager.applyDiagnosticsDefaultsIfBuildChanged()
    DiagnosticsResetManager.stopDiagnosticsIfDebugModeDisabled()
    precondition(!AppDebugLogger.isDebugModeEnabled && AppDebugLogger.transitions.count == 2)
    precondition(store.string(forKey: "previous-evidence") == "seeded-exit")
    precondition(store.string(forKey: "metrickit-history") == "seeded-metrickit")
    print("PASS: beta defaults, same-build debug OFF, upgrade is not a crash, old exit/MetricKit evidence retained")
}
