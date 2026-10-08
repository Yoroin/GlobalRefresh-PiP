import Foundation

enum FrameRatePreference {
    static let force120HzKey = "frameRateDemo.force120Hz"
    static var isHighRefreshEnabled: Bool { UserDefaults.standard.object(forKey: force120HzKey) as? Bool ?? true }
    static var targetFrameRate: Int { isHighRefreshEnabled ? 120 : 80 }
}

enum UIApplication {
    enum State { case active, background }
    final class Application { var applicationState = State.active }
    static let shared = Application()
}
enum UIScreen {
    final class Screen { var maximumFramesPerSecond = 120 }
    static let main = Screen()
}
struct CAFrameRateRange: Equatable {
    static let `default` = CAFrameRateRange(minimum: 0, maximum: 0, preferred: 0)
    var minimum: Float
    var maximum: Float
    var preferred: Float
}
final class CADisplayLink {
    var preferredFrameRateRange = CAFrameRateRange(minimum: 0, maximum: 0, preferred: 0)
    var preferredFramesPerSecond = 0
}
enum PiPHiddenReferenceMode {
    static var suppressesStrictRefreshRequest = true
    static var suppressesRefreshDriver = true
}

@main
struct PageRefreshIsolationTests {
    static func main() {
        let defaults = UserDefaults.standard
        let legacyKey = "frameRateDemo.force120Hz"
        let pageKey = DemoFrameRatePreference.force120HzKey
        let migrationKey = "frameRateDemo.pageOnlyControlMigrated.v1"
        let oldLegacyValue = defaults.object(forKey: legacyKey)
        let oldPageValue = defaults.object(forKey: pageKey)
        let oldMigrationValue = defaults.object(forKey: migrationKey)
        defer {
            defaults.set(oldLegacyValue, forKey: legacyKey)
            defaults.set(oldPageValue, forKey: pageKey)
            defaults.set(oldMigrationValue, forKey: migrationKey)
        }
        defaults.removeObject(forKey: pageKey)
        precondition(DemoFrameRatePreference.isHighRefreshEnabled)
        precondition(pageKey != legacyKey)
        var legacyNotifications = 0
        var pageNotifications = 0
        let center = NotificationCenter.default
        let legacyToken = center.addObserver(forName: Notification.Name("FrameRatePreferenceDidChange"), object: nil, queue: nil) { _ in legacyNotifications += 1 }
        let pageToken = center.addObserver(forName: DemoFrameRatePreference.didChangeNotification, object: nil, queue: nil) { _ in pageNotifications += 1 }
        defer { center.removeObserver(legacyToken); center.removeObserver(pageToken) }
        for legacyEnabled in [false, true] {
            defaults.set(legacyEnabled, forKey: legacyKey)
            for pageEnabled in [false, true] {
                DemoFrameRatePreference.setEnabled(pageEnabled)
                precondition(DemoFrameRatePreference.isHighRefreshEnabled == pageEnabled)
                precondition(DemoFrameRatePreference.targetFrameRate == (pageEnabled ? 120 : 80))
                precondition(defaults.bool(forKey: legacyKey) == legacyEnabled)
            }
        }
        precondition(legacyNotifications == 0 && pageNotifications == 4)
        for oldEnabled in [false, true] {
            defaults.removeObject(forKey: pageKey)
            defaults.removeObject(forKey: migrationKey)
            defaults.set(oldEnabled, forKey: legacyKey)
            DemoFrameRatePreference.migrateLegacySettingIfNeeded()
            precondition(DemoFrameRatePreference.isHighRefreshEnabled == oldEnabled)
            precondition(defaults.bool(forKey: legacyKey), "Compatibility PiP must not inherit a previous demo-OFF preference")
            DemoFrameRatePreference.setEnabled(!oldEnabled)
            DemoFrameRatePreference.migrateLegacySettingIfNeeded()
            precondition(DemoFrameRatePreference.isHighRefreshEnabled == !oldEnabled, "Migration is one-time")
        }
        for maximum in [60, 120] {
            UIScreen.main.maximumFramesPerSecond = maximum
            for enabled in [false, true] {
                DemoFrameRatePreference.setEnabled(enabled)
                UIApplication.shared.applicationState = .active
                let foreground = CADisplayLink()
                ForegroundRefreshHarness.configureRefreshDriver(foreground)
                let target = Float(min(maximum, 120))
                let offTarget = Float(min(maximum, 80))
                let expected = enabled
                    ? CAFrameRateRange(minimum: target, maximum: target, preferred: target)
                    : CAFrameRateRange(minimum: offTarget, maximum: offTarget, preferred: offTarget)
                precondition(foreground.preferredFrameRateRange == expected)
                UIApplication.shared.applicationState = .background
                let background = CADisplayLink()
                ForegroundRefreshHarness.configureRefreshDriver(background)
                precondition(background.preferredFrameRateRange == CAFrameRateRange(minimum: 0, maximum: 0, preferred: 0), "Content-only background must not inherit foreground refresh requests")
            }
        }
        for target in [60, 90, 120] {
            let reusedLink = CADisplayLink()
            DemoFrameRatePreference.setEnabled(true)
            DemoFrameRatePreference.configureForegroundRequest(reusedLink, targetFrameRate: target)
            DemoFrameRatePreference.setEnabled(false)
            DemoFrameRatePreference.configureForegroundRequest(reusedLink, targetFrameRate: target)
            let offTarget = Float(min(target, min(80, UIScreen.main.maximumFramesPerSecond)))
            precondition(reusedLink.preferredFrameRateRange == CAFrameRateRange(minimum: offTarget, maximum: offTarget, preferred: offTarget), "OFF must replace the prior request with the released capped policy")
            DemoFrameRatePreference.setEnabled(true)
            DemoFrameRatePreference.configureForegroundRequest(reusedLink, targetFrameRate: target)
            precondition(reusedLink.preferredFrameRateRange.preferred == Float(min(target, UIScreen.main.maximumFramesPerSecond)))
        }
        UIScreen.main.maximumFramesPerSecond = 120
        for maximum in [30, 60, 80, 90, 120] {
            UIScreen.main.maximumFramesPerSecond = maximum
            UIApplication.shared.applicationState = .active
            defaults.set(false, forKey: legacyKey)
            DemoFrameRatePreference.setEnabled(false)
            let foreground = CADisplayLink()
            ForegroundRefreshHarness.configureRefreshDriver(foreground)
            let old109 = CADisplayLink()
            Legacy109Main.configureRefreshDriver(old109)
            let old110Fix = CADisplayLink()
            Legacy110FixMain.configureRefreshDriver(old110Fix)
            precondition(foreground.preferredFrameRateRange == old109.preferredFrameRateRange)
            precondition(foreground.preferredFrameRateRange == old110Fix.preferredFrameRateRange)
            for requested in [60, 80, 90, 120] {
                let demo = CADisplayLink()
                DemoFrameRatePreference.configureForegroundRequest(demo, targetFrameRate: requested, minimumFrameRateWhenDisabled: 30)
                let old109Demo = CADisplayLink()
                Legacy109Page(targetFrameRate: requested).configure(old109Demo)
                let old110FixDemo = CADisplayLink()
                Legacy110FixPage(targetFrameRate: requested).configure(old110FixDemo)
                precondition(demo.preferredFrameRateRange == old109Demo.preferredFrameRateRange)
                precondition(demo.preferredFrameRateRange == old110FixDemo.preferredFrameRateRange)
                DemoFrameRatePreference.setEnabled(true)
                DemoFrameRatePreference.configureForegroundRequest(demo, targetFrameRate: requested, minimumFrameRateWhenDisabled: 30)
                let target = Float(min(requested, maximum))
                precondition(demo.preferredFrameRateRange == CAFrameRateRange(minimum: target, maximum: target, preferred: target), "ON must retain the current strict foreground request")
                DemoFrameRatePreference.setEnabled(false)
            }
        }
        UIScreen.main.maximumFramesPerSecond = 120
        UIApplication.shared.applicationState = .background
        PiPHiddenReferenceMode.suppressesStrictRefreshRequest = false
        PiPHiddenReferenceMode.suppressesRefreshDriver = false
        defaults.set(true, forKey: legacyKey)
        DemoFrameRatePreference.setEnabled(false)
        let compatibility = CADisplayLink()
        ForegroundRefreshHarness.configureRefreshDriver(compatibility)
        precondition(compatibility.preferredFrameRateRange.maximum == 120, "Foreground OFF must not change compatibility PiP's legacy request")
        print("PASS: page-only setting and notification never change the legacy PiP preference")
        print("PASS: foreground OFF matches v1.0.9 and v1.1.0fix production fields across hardware limits and idle/scroll targets")
        print("PASS: ON strict foreground requests and background PiP policies unchanged")
    }
}
