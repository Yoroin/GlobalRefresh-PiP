import Foundation

@main
struct UpgradePreferencesTests {
    static func main() {
        let suite = "pip.tests.upgrade.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preserved: [String: Any] = [
            "pip.home.engineRoute": "videoCall", "pip.home.rememberedPiPHeight": 0.1,
            "pip.keepAlive.policy": "pipOnly", "pip.home.scrollingEnabled": false,
            "pip.shortcut.featureEnabled.v1": true, "pip.experiment.visibilityRefresh": false,
            "pip.home.runtimeStoppedAtText": "retained"
        ]
        for (key, value) in preserved { defaults.set(value, forKey: key) }
        for (index, key) in PiPCoexistencePreferences.retiredKeys.enumerated() { defaults.set(index % 2 == 0, forKey: key) }
        precondition(PiPCoexistencePreferences.migrate(defaults).count == 5)
        for key in PiPCoexistencePreferences.retiredKeys { precondition(defaults.object(forKey: key) == nil) }
        for (key, value) in preserved {
            precondition((defaults.object(forKey: key) as? NSObject)?.isEqual(value) == true, "Must preserve \(key)")
        }
        precondition(PiPCoexistencePreferences.migrate(defaults).isEmpty)
        for major in 14...29 {
            precondition(PiPNativePostStartTrial.supportsSystemMajorVersion(major) == (15...27).contains(major))
        }
        print("PASS: upgrade removes only five retired flags, preserves settings/height/history, is idempotent, and native optimized-route availability covers iOS15-27")
    }
}
