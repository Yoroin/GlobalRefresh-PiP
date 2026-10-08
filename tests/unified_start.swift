import Foundation

enum AppDebugLogger {
    static func log(_ value: String) {}
    static func logCritical(_ value: String) {}
}
enum DiagnosticsRuntimeState {
    static func recordUserAction(_ value: String) {}
}
enum L10n {
    static func text(_ chinese: String, _ english: String) -> String { english }
}
enum PiPCoexistenceExperiment {
    static let postStartTransitionDelay: TimeInterval = 1
}
final class StartController {
    var isPictureInPictureActive = false
}
final class UnifiedStartHarness {
    var pipController: StartController?
    var isHiddenReferenceSession = false
    var needsHiddenReferenceInfrastructureRefresh = false
    var isPiPTransitioning = false
    var wantsPiPActive = false
    var shouldHidePiPAfterShortcutStart = false
    var isPiPActiveForUI = false
    var hasPrimedPlayerLayerPiPStart = false
    var didRetryLegacyPiPStart = false
    var shortcutPiPStartRetryRemaining = 0
    var shortcutRetryPreservesMinimumHeight = false
    var pendingShortcutPiPStartRetry: DispatchWorkItem?
    var prepareSucceeds = true
    var height: Double = 44
    let currentMinimumPiPHeight = 0.1
    var currentPiPSize: String { "300x\(height)" }
    var starts: [Bool] = []
    var startHeights: [Double] = []
    var adjustments = 0
    var preparations = 0
    var messages = 0
    func recoverStalePiPTransitionIfNeeded(reason: String) {}
    func cancelDelayedPiPHideCountdown(reason: String) {}
    func commitPiPHeight(_ value: Double) { height = value }
    func applyOneTapMinimumHeight(source: String) {
        adjustments += 1
        height = currentMinimumPiPHeight
    }
    func preparePiPInfrastructureIfNeeded() -> Bool {
        preparations += 1
        if prepareSucceeds {
            pipController = StartController()
            isHiddenReferenceSession = true
        }
        return prepareSucceeds
    }
    func updatePiPAutomaticStartPolicy() {}
    func configureRunningText() {}
    func showMessage(_ message: String) { messages += 1 }
    func startPiPSmoothly(preservingMinimumHeight: Bool = false) {
        starts.append(preservingMinimumHeight)
        startHeights.append(height)
    }
}

@main
struct UnifiedStartTests {
    static func main() {
        for minimum in [false, true] {
            for shortcut in [false, true] {
                let cold = UnifiedStartHarness()
                cold.startHiddenReferencePiP(atMinimumHeight: minimum, source: "test", fromShortcut: shortcut)
                precondition(cold.preparations == 1 && cold.starts == [minimum])
                precondition(cold.height == (minimum ? 0.1 : 44))
                precondition(cold.startHeights == [minimum ? 0.1 : 44], "Direct hidden startup sets its height before requesting PiP")
                precondition(cold.wantsPiPActive && cold.isPiPActiveForUI)
                precondition(cold.shouldHidePiPAfterShortcutStart == minimum,
                             "Hidden startup must confirm the minimum height after legacy retries")
                precondition(cold.shortcutRetryPreservesMinimumHeight == (shortcut && minimum))
                cold.cancelShortcutPiPStartRetry()
            }
        }
        let active = UnifiedStartHarness()
        active.pipController = StartController()
        active.pipController!.isPictureInPictureActive = true
        active.startHiddenReferencePiP(atMinimumHeight: true, source: "test", fromShortcut: true)
        precondition(active.adjustments == 1 && active.starts.isEmpty && active.preparations == 0)
        active.startHiddenReferencePiP(atMinimumHeight: false, source: "test")
        precondition(active.messages == 1 && active.starts.isEmpty)

        let pending = UnifiedStartHarness()
        pending.isPiPTransitioning = true
        pending.isHiddenReferenceSession = true
        pending.wantsPiPActive = true
        pending.startHiddenReferencePiP(atMinimumHeight: true, source: "test", fromShortcut: true)
        precondition(pending.shouldHidePiPAfterShortcutStart && pending.starts.isEmpty && pending.preparations == 0)
        pending.pipController = StartController()
        pending.pipController!.isPictureInPictureActive = true
        pending.startHiddenReferencePiP(atMinimumHeight: true, source: "test", fromShortcut: true)
        precondition(pending.adjustments == 0 && pending.shouldHidePiPAfterShortcutStart,
                     "An active bit during startup must not consume the pending hide early")
        let stopping = UnifiedStartHarness()
        stopping.isPiPTransitioning = true
        stopping.isHiddenReferenceSession = true
        stopping.startHiddenReferencePiP(atMinimumHeight: true, source: "test")
        precondition(!stopping.shouldHidePiPAfterShortcutStart && stopping.starts.isEmpty)

        let failed = UnifiedStartHarness()
        failed.prepareSucceeds = false
        failed.startHiddenReferencePiP(atMinimumHeight: true, source: "test", fromShortcut: true)
        precondition(failed.starts.isEmpty && !failed.wantsPiPActive && !failed.isPiPActiveForUI)
        precondition(!failed.shouldHidePiPAfterShortcutStart && failed.shortcutPiPStartRetryRemaining == 0)

        let retry = UnifiedStartHarness()
        retry.startHiddenReferencePiP(atMinimumHeight: true, source: "test", fromShortcut: true)
        precondition(retry.scheduleShortcutPiPStartRetry(reason: "test failure"))
        RunLoop.main.run(until: Date().addingTimeInterval(1.4))
        precondition(retry.starts == [true, true], "Retries must not restore 44 pt")
        retry.cancelShortcutPiPStartRetry()
        precondition(!retry.shortcutRetryPreservesMinimumHeight && retry.shortcutPiPStartRetryRemaining == 0)
        let normal = UnifiedStartHarness()
        normal.pipController = StartController()
        normal.prepareShortcutPiPStartRetryIfNeeded()
        precondition(!normal.shortcutRetryPreservesMinimumHeight, "Original routes keep their retry sizing")
        normal.cancelShortcutPiPStartRetry()
        print("PASS: unified cold/active/transition/failure starts; minimum-height retry preservation; normal-route retry unchanged")
    }
}
