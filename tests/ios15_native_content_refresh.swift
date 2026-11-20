// The shell harness appends the actual production start/stop/tick methods below.
import CoreGraphics
struct CAFrameRateRange: Equatable {
    let minimum: Float
    let maximum: Float
    let preferred: Float
    static let `default` = CAFrameRateRange(minimum: 0, maximum: 0, preferred: 0)
}
final class CADisplayLink: NSObject {
    static var created = 0
    var preferredFramesPerSecond = 0
    var preferredFrameRateRange = CAFrameRateRange.default
    var timestamp: Double = 1
    var invalidated = false
    var added = false
    init(target: AnyObject, selector: Selector) { Self.created += 1 }
    func add(to: RunLoop, forMode: RunLoop.Mode) { added = true }
    func invalidate() { invalidated = true }
}
enum UIScreen {
    final class Screen { var maximumFramesPerSecond = 120 }
    static let main = Screen()
}
enum AppDebugLogger {
    static func log(_ text: String) {}
    static func logCritical(_ text: String) {}
    static func logRuntime(_ text: String) {}
}
final class ContentLayer {
    var redraws = 0
    func setNeedsDisplay() { redraws += 1 }
}
final class ContentView {
    var layer = ContentLayer()
    var bounds = CGRect(x: 0, y: 0, width: 300, height: 0.1)
    var window: NSObject? = NSObject()
    var redraws = 0
    func setNeedsDisplay() { redraws += 1 }
}
final class PiPController { var isPictureInPictureActive = true }
enum NativeContentTests {
    static func run() {
        let keys = [PiPRefreshRequestTrial.background120Key, PiPRefreshRequestTrial.content120Key, PiPRefreshRequestTrial.content60Key, PiPRefreshRequestTrial.baselineMigrationKey, PiPRefreshRequestTrial.backgroundModeKey]
        let defaults = UserDefaults.standard
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        precondition(!PiPRefreshRequestTrial.background120 && !PiPRefreshRequestTrial.content120)
        precondition(PiPRefreshRequestTrial.baselineContentFPS == 30)
        defaults.set(true, forKey: PiPRefreshRequestTrial.content60Key)
        PiPRefreshRequestTrial.migrateDefaultBaselineIfNeeded()
        precondition(PiPRefreshRequestTrial.baselineContentFPS == 30, "The beta4 upgrade restores baseline30 once")
        defaults.set(true, forKey: PiPRefreshRequestTrial.content60Key)
        PiPRefreshRequestTrial.migrateDefaultBaselineIfNeeded()
        precondition(PiPRefreshRequestTrial.baselineContentFPS == 60, "Later user selections must persist")
        keys.forEach { defaults.removeObject(forKey: $0) }
        for major in 14...29 {
            for player in [false, true] {
                for pipOnly in [false, true] {
                    precondition(PiPNativeContentRefreshPolicy.supports(systemMajorVersion: major, isPlayerLayer: player, isPiPOnly: pipOnly) == ((15...27).contains(major) && !player && pipOnly))
                }
            }
        }
        precondition(PiPNativeContentRefreshPolicy.framesPerSecond == 30)
        let controller = ViewController()
        controller.pipController?.isPictureInPictureActive = false
        controller.updateNativeContentRefresh()
        precondition(controller.nativeContentDisplayLink == nil, "No content link before actual native startup")
        controller.pipController?.isPictureInPictureActive = true
        controller.updateNativeContentRefresh()
        let link = controller.nativeContentDisplayLink!
        precondition(link.preferredFramesPerSecond == 30 && link.added)
        controller.updateNativeContentRefresh()
        precondition(controller.nativeContentDisplayLink === link && CADisplayLink.created == 1)
        for maximum in [60, 120] {
            UIScreen.main.maximumFramesPerSecond = maximum
            for background in [false, true] {
                defaults.set((background ? PiPRefreshRequestTrial.BackgroundMode.explicit120 : .systemDefault).rawValue,
                             forKey: PiPRefreshRequestTrial.backgroundModeKey)
                precondition(PiPRefreshRequestTrial.requestsBackground120(eligible: true) == background)
                precondition(!PiPRefreshRequestTrial.requestsBackground120(eligible: false))
                for content120 in [false, true] {
                    defaults.set(content120, forKey: PiPRefreshRequestTrial.content120Key)
                    for content60 in [false, true] {
                        defaults.set(content60, forKey: PiPRefreshRequestTrial.content60Key)
                        controller.updateNativeContentRefresh()
                        precondition(controller.nativeContentDisplayLink === link && CADisplayLink.created == 1)
                        if content120 {
                            let target = Float(min(120, maximum))
                            precondition(link.preferredFrameRateRange == CAFrameRateRange(minimum: target, maximum: target, preferred: target))
                        } else {
                            precondition(link.preferredFrameRateRange == .default, "Disabling content120 must clear the previous strict range")
                            precondition(link.preferredFramesPerSecond == min(content60 ? 60 : 30, maximum))
                        }
                    }
                }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        UIScreen.main.maximumFramesPerSecond = 120
        controller.updateNativeContentRefresh()
        precondition(link.preferredFramesPerSecond == 30 && link.preferredFrameRateRange == .default)
        print("PASS: independent background/content120 switches and 30/60 baseline; all combinations capped by hardware, live changes reuse one link, OFF clears strict120")
        controller.isPiPVisuallyHidden = true
        controller.isPiPSuspendedAtSide = true
        controller.isScrollingEnabled = false
        controller.updateNativeContent(link)
        precondition(controller.customView!.redraws == 1 && controller.customView!.layer.redraws == 1)
        precondition(!link.invalidated && controller.scrollUpdates == 0)
        controller.isPiPVisuallyHidden = false
        controller.isPiPSuspendedAtSide = false
        controller.updateNativeContent(link)
        precondition(controller.textView!.redraws == 1 && !link.invalidated)
        controller.isScrollingEnabled = true
        controller.updateNativeContent(link)
        precondition(controller.scrollUpdates == 1)
        controller.shouldRenderClockMode = true
        controller.updateNativeContent(link)
        precondition(controller.clockUpdates == 1 && controller.scrollUpdates == 1)
        controller.shouldPauseContentRefreshForVisibilityTrial = true
        let redrawsBeforePause = controller.customView!.redraws
        controller.updateNativeContent(link)
        precondition(link.invalidated && controller.nativeContentDisplayLink == nil)
        precondition(controller.customView!.redraws == redrawsBeforePause, "Paused content must not redraw on a queued tick")
        controller.updateNativeContentRefresh()
        precondition(controller.nativeContentDisplayLink == nil, "Hidden/locked state must not recreate the link")
        controller.shouldPauseContentRefreshForVisibilityTrial = false
        controller.updateNativeContentRefresh()
        let resumed = controller.nativeContentDisplayLink!
        precondition(resumed !== link && !resumed.invalidated, "Visible content resumes with one fresh link")
        controller.updateNativeContentRefresh()
        precondition(controller.nativeContentDisplayLink === resumed)
        controller.usesIOS15NativeContentRefresh = false
        controller.updateNativeContent(resumed)
        precondition(resumed.invalidated && controller.nativeContentDisplayLink == nil)
        controller.usesIOS15NativeContentRefresh = true
        controller.shouldRenderClockMode = false
        UIScreen.main.maximumFramesPerSecond = 20
        controller.updateNativeContentRefresh()
        let capped = controller.nativeContentDisplayLink!
        precondition(capped.preferredFramesPerSecond == 20)
        controller.wantsPiPActive = false
        controller.updateNativeContent(capped)
        precondition(capped.invalidated && controller.nativeContentDisplayLink == nil)
        controller.wantsPiPActive = true
        controller.isStoppingPiP = true
        controller.updateNativeContentRefresh()
        precondition(controller.nativeContentDisplayLink == nil)
        controller.isStoppingPiP = false
        controller.customView = nil
        controller.updateNativeContentRefresh()
        precondition(controller.nativeContentDisplayLink == nil)
        controller.stopNativeContentRefresh()
        print("PASS: actual native content methods request up to30fps, retain baseline behavior when trial is off, pause without queued redraw/restart, resume one link, and stop on route/policy/close/host loss")
    }
}
final class ViewController {
    var usesIOS15NativeContentRefresh = true
    var shouldPauseContentRefreshForVisibilityTrial = false
    var wantsPiPActive = true
    var isStoppingPiP = false
    var pipController: PiPController? = PiPController()
    var customView: ContentView? = ContentView()
    var textView: ContentView? = ContentView()
    var clockOverlayView: ContentView? = ContentView()
    var isPiPVisuallyHidden = false
    var isPiPSuspendedAtSide = false
    var shouldRenderClockMode = false
    var isScrollingEnabled = true
    var isContentExtremeModeEnabled = false
    var nativeContentDisplayLink: CADisplayLink?
    var nativeContentLastLogTimestamp: Double?
    var nativeContentTickCount = 0
    var scrollUpdates = 0
    var clockUpdates = 0
    final class NativeContentTarget: NSObject {
        @objc func tick(_ link: CADisplayLink) {}
    }
    let nativeContentTarget = NativeContentTarget()
    func stopDisplayLinks() {}
    func stopClockTimer() {}
    func updateScrollingText(_ link: CADisplayLink) { scrollUpdates += 1 }
    func updateClockOverlay(timestamp: Double, forceNetworkSample: Bool) { clockUpdates += 1 }
