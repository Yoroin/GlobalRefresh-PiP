import Foundation
import Combine

struct LightweightProcessSnapshot {
    let physicalFootprintMB: Double
    let threadCount: Int
}
enum UIApplication {
    enum State: Int { case active, background, inactive }
    final class App { var applicationState = State.active }
    static let shared = App()
    static let didBecomeActiveNotification = Notification.Name("TestAppDidBecomeActive")
    static let willResignActiveNotification = Notification.Name("TestAppWillResignActive")
    static let didEnterBackgroundNotification = Notification.Name("TestAppDidEnterBackground")
}
enum AppDebugLogger { static func logRuntime(_ message: String) {} }
enum PerformanceDiagnosticsLogger {
    static var samples = 0
    static func lightweightProcessSnapshot() -> LightweightProcessSnapshot {
        samples += 1
        return LightweightProcessSnapshot(physicalFootprintMB: 42.5, threadCount: 12)
    }
}

func runLiveStatsTests() {
    let monitor = PiPLiveProcessStatsMonitor()
    monitor.setVisible(false)
    precondition(PerformanceDiagnosticsLogger.samples == 0)
    UIApplication.shared.applicationState = .inactive
    monitor.setVisible(true)
    precondition(PerformanceDiagnosticsLogger.samples == 0)
    UIApplication.shared.applicationState = .active
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    precondition(monitor.snapshot?.physicalFootprintMB == 42.5 && monitor.snapshot?.threadCount == 12)
    monitor.setVisible(true)
    precondition(PerformanceDiagnosticsLogger.samples == 1, "Duplicate starts must not create another sampler")
    RunLoop.main.run(until: Date().addingTimeInterval(1.4))
    precondition(PerformanceDiagnosticsLogger.samples >= 2)
    monitor.setVisible(false)
    let hiddenCount = PerformanceDiagnosticsLogger.samples
    RunLoop.main.run(until: Date().addingTimeInterval(1.4))
    precondition(PerformanceDiagnosticsLogger.samples == hiddenCount)
    monitor.setVisible(true)
    let beforeBackground = PerformanceDiagnosticsLogger.samples
    NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
    UIApplication.shared.applicationState = .background
    NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    RunLoop.main.run(until: Date().addingTimeInterval(1.4))
    precondition(PerformanceDiagnosticsLogger.samples == beforeBackground, "A queued tick in background must stop without sampling")
    monitor.setVisible(true)
    precondition(PerformanceDiagnosticsLogger.samples == beforeBackground)
    UIApplication.shared.applicationState = .active
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    precondition(PerformanceDiagnosticsLogger.samples == beforeBackground + 1, "Visible UIKit host must resume without a scenePhase change")
    monitor.setVisible(false)
    let afterHide = PerformanceDiagnosticsLogger.samples
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    precondition(PerformanceDiagnosticsLogger.samples == afterHide, "Hidden monitor must remove its lifecycle observers")
    weak var released: PiPLiveProcessStatsMonitor?
    do {
        let temporary = PiPLiveProcessStatsMonitor()
        released = temporary
        temporary.setVisible(true)
    }
    precondition(released == nil, "Timer must not retain its owner")
    print("PASS: UIKit-hosted stats start after inactive->active, update once per second, resume without scenePhase, stop while hidden/background, remove observers and release their owner")
}
