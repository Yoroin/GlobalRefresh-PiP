import Foundation
import ObjectiveC

enum AppDebugLogger {
    static let isDebugModeEnabled = true
    static var entries: [String] = []
    static func log(_ text: String) {}
    static func logCritical(_ text: String) { entries.append(text) }
}

private final class IntegerStyleController: AVPictureInPictureController {
    @objc var controlsStyle: Int = 2
}
private final class OtherStyleController: AVPictureInPictureController {
    @objc var controlsStyle: String = "original"
}

@main
struct NativePostStartTests {
    static func pump(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    static func main() {
        let provider = NSSelectorFromString("pictureInPictureProxyContentType:")
        let matching = IntegerStyleController(contentSource: .init())
        let different = OtherStyleController(contentSource: .init())
        precondition(PiPCoexistenceExperiment.setControlsStyleIfSupported(1, on: matching) && matching.controlsStyle == 1)
        precondition(!PiPCoexistenceExperiment.setControlsStyleIfSupported(1, on: different) && different.controlsStyle == "original")
        precondition(!PiPCoexistenceExperiment.setControlsStyleIfSupported(1, on: .init(contentSource: .init())))
        precondition(PiPHiddenReferenceControls.makeNativeController(source: .init(), systemMajorVersion: 16) != nil)
        precondition(!PiPHiddenReferenceControls.hidesDuringNativeConstruction(systemMajorVersion: 15))
        precondition(PiPHiddenReferenceControls.makeNativeController(source: .init(), systemMajorVersion: 15) != nil)
        for major in 15...27 {
            precondition(PiPNativeContentRefreshPolicy.supports(systemMajorVersion: major, isPlayerLayer: false, isPiPOnly: true))
            precondition(!PiPHiddenReferenceMode.supportsSystemMajorVersion(major))
            precondition(PiPHiddenReferenceControls.hidesDuringNativeConstruction(systemMajorVersion: major) == (major >= 16))
        }
        for nativeType in [4, 3] {
            let adapter = PCEMakeAdapter()!
            let proxy = PCEMakeProxy(nativeType)!
            PCESetDelegate(proxy, adapter)
            let controller = AVPictureInPictureController(contentSource: .init())
            controller.platformAdapter = adapter
            let trial = PiPCoexistenceExperiment()
            precondition(!trial.prepareForStartIfRequested(controller: controller, isVideoCall: true))
            trial.schedulePostStartUpdateIfRequested(controller: controller, useNativePostStart: true)
            precondition(!adapter.responds(to: provider) && PCESendCount(proxy) == 0)
            controller.isPictureInPictureActive = true
            trial.schedulePostStartUpdateIfRequested(controller: controller, useNativePostStart: true)
            trial.schedulePostStartUpdateIfRequested(controller: controller, useNativePostStart: true)
            precondition(PCEType(proxy) == nativeType && PCEProviderType(adapter, proxy) == nativeType)
            precondition(PCESendCount(proxy) == 0, "No initial playback-state write after attaching provider")
            pump(0.2)
            precondition(PCEType(proxy) == nativeType && PCESendCount(proxy) == 0)
            pump(1.0)
            precondition(PCEType(proxy) == 6 && PCESendCount(proxy) == 1)
            trial.restore()
            precondition(PCEType(proxy) == nativeType && !adapter.responds(to: provider))
        }
        let adapter = PCEMakeAdapter()!
        let proxy = PCEMakeProxy(4)!
        PCESetDelegate(proxy, adapter)
        let controller = AVPictureInPictureController(contentSource: .init())
        controller.platformAdapter = adapter
        controller.isPictureInPictureActive = true
        let canceled = PiPCoexistenceExperiment()
        canceled.schedulePostStartUpdateIfRequested(controller: controller, useNativePostStart: true)
        canceled.restore()
        pump(1.1)
        precondition(PCEType(proxy) == 4 && PCESendCount(proxy) == 0)
        let suspended = PiPCoexistenceExperiment()
        suspended.schedulePostStartUpdateIfRequested(controller: controller, useNativePostStart: true)
        controller.isPictureInPictureSuspended = true
        pump(1.1)
        precondition(PCEType(proxy) == 4 && PCESendCount(proxy) == 0)
        suspended.restore()
        let unknownProxy = PCEMakeProxy(7)!
        PCESetDelegate(unknownProxy, adapter)
        controller.isPictureInPictureSuspended = false
        let unknown = PiPCoexistenceExperiment()
        unknown.schedulePostStartUpdateIfRequested(controller: controller, useNativePostStart: true)
        pump(1.1)
        precondition(controller.isPictureInPictureActive && PCEType(unknownProxy) == 7 && PCESendCount(unknownProxy) == 0)
        precondition(!adapter.responds(to: provider))
        PCESetDelegate(proxy, adapter)
        let hardened = PiPCoexistenceExperiment()
        precondition(!hardened.maintainControlsHidden(controller: controller, systemMajorVersion: 15))
        precondition(PCEControlsStyle(adapter) == 2)
        controller.isPictureInPictureActive = false
        precondition(!hardened.maintainControlsHidden(controller: controller, systemMajorVersion: 27))
        precondition(PCEControlsStyle(adapter) == 2)
        controller.isPictureInPictureActive = true
        precondition(hardened.maintainControlsHidden(controller: controller, systemMajorVersion: 16))
        precondition(PCEControlsStyle(adapter) == 5)
        precondition(PCEProxyControlsStyle(proxy) == 5 && PCEControlsSendCount(proxy) == 1)
        precondition(!PCEControlsAnimated(proxy))
        precondition(hardened.maintainControlsHidden(controller: controller, systemMajorVersion: 16))
        precondition(PCEControlsSendCount(proxy) == 1, "Ordinary checks must not repeatedly send matching proxy style")
        precondition(hardened.maintainControlsHidden(controller: controller, systemMajorVersion: 16, resubmitAfterTransition: true))
        precondition(PCEControlsSendCount(proxy) == 2, "Post-transition submission targets the proxy even if outer/cache already match")
        PCESetProxyControlsStyle(proxy, 4)
        precondition(hardened.maintainControlsHidden(controller: controller, systemMajorVersion: 16))
        precondition(PCEProxyControlsStyle(proxy) == 5 && PCEControlsSendCount(proxy) == 3)
        let unrelated = PCEMakeAdapter()!
        precondition(PCEControlsStyle(unrelated) == 2)
        hardened.clearMaintainedControls()
        precondition(PCEControlsStyle(adapter) == 2)
        precondition(PCEControlsSendCount(proxy) == 3, "Cleanup must not send controls or rebuild PiP")

        let oldAdapter = PCEMakeAdapter()!
        let oldProxy = PCEMakeProxy(4)!
        PCESetDelegate(oldProxy, oldAdapter)
        let oldController = AVPictureInPictureController(contentSource: .init())
        oldController.platformAdapter = oldAdapter
        oldController.isPictureInPictureActive = true
        hardened.schedulePostStartUpdateIfRequested(controller: oldController, useNativePostStart: true)
        hardened.cancelPendingTransition()
        pump(1.1)
        precondition(PCESendCount(oldProxy) == 0 && PCEType(oldProxy) == 4)
        // Even if a stop callback is delayed, a replacement cannot reuse the old provider.
        let newAdapter = PCEMakeAdapter()!
        let newProxy = PCEMakeProxy(4)!
        PCESetDelegate(newProxy, newAdapter)
        let reopened = AVPictureInPictureController(contentSource: .init())
        reopened.platformAdapter = newAdapter
        reopened.isPictureInPictureActive = true
        hardened.schedulePostStartUpdateIfRequested(controller: reopened, useNativePostStart: true)
        precondition(!oldAdapter.responds(to: provider))
        pump(1.1)
        precondition(PCESendCount(oldProxy) == 0 && PCEType(oldProxy) == 4)
        precondition(PCESendCount(newProxy) == 1 && PCEType(newProxy) == 6)
        precondition(hardened.maintainControlsHidden(controller: reopened, systemMajorVersion: 27))
        hardened.restore()
        precondition(PCEControlsStyle(newAdapter) == 2 && !newAdapter.responds(to: provider))
        precondition(PCEType(newProxy) == 4)
        let unsupportedAdapter = PCEMakeAdapter()!
        controller.platformAdapter = unsupportedAdapter
        precondition(!hardened.maintainControlsHidden(controller: controller, systemMajorVersion: 27))
        precondition(PCEControlsStyle(unsupportedAdapter) == 2)
        precondition(PCEControlsSendCount(newProxy) == 1 && PCESendCount(newProxy) == 1)
        print("PASS: actual proxy receives hidden style, no playback-state write, no animation/repeated checks, explicit post-transition resubmission and unsupported-runtime guard")
        print("PASS: controls scoped to active iOS16+ adapters, restored on cleanup; canceled transition cannot change a replacement session")
        print("PASS: no pre-start provider/state mutation, preserves native 3/4, one delayed 6, cancellation/suspension guarded, unsupported runtime leaves native PiP active")
    }
}
