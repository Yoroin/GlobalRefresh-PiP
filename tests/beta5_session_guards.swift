import Foundation

final class AVPictureInPictureController {
    var isPictureInPictureActive = false
    var isPictureInPictureSuspended = false
}
enum AppDebugLogger {
    static func log(_ msg: String) {}
    static func logCritical(_ msg: String) {}
    static func logRuntime(_ msg: String) {}
}
enum DiagnosticsRuntimeState { static func recordUserAction(_ msg: String) {} }
final class Trial { func checkpoint(_ msg: String) {} }
func run() {
    let vc = Harness(), old = AVPictureInPictureController()
    let current = vc.pipController!
    let e = CocoaError(.userCancelled)
    var completions: [Bool] = []
    vc.pictureInPictureControllerWillStartPictureInPicture(old)
    vc.pictureInPictureController(old, failedToStartPictureInPictureWithError: e)
    vc.pictureInPictureController(old) { completions.append($0) }
    precondition(vc.events == 0 && vc.wantsPiPActive && vc.isPiPActiveForUI && completions == [false])
    vc.pictureInPictureControllerWillStartPictureInPicture(current)
    vc.pictureInPictureController(current, failedToStartPictureInPictureWithError: e)
    vc.pictureInPictureController(current) { completions.append($0) }
    precondition(vc.events == 3 && !vc.wantsPiPActive && !vc.isPiPActiveForUI && completions == [false, false])
    current.isPictureInPictureSuspended = true
    vc.validateOwnPiPState(reason: "foreground")
    precondition(vc.invalidationReasons.isEmpty && vc.isOwnPiPConfirmedActive)
    current.isPictureInPictureSuspended = false
    vc.isPiPTransitioning = true
    vc.validateOwnPiPState(reason: "foreground")
    precondition(vc.invalidationReasons.isEmpty)
    vc.isPiPTransitioning = false
    current.isPictureInPictureActive = true
    vc.validateOwnPiPState(reason: "resumed")
    precondition(vc.invalidationReasons.isEmpty)
    current.isPictureInPictureActive = false
    vc.validateOwnPiPState(reason: "foreground")
    precondition(vc.invalidationReasons.count == 1 && vc.invalidationReasons[0].contains("未确认停止原因"))
    print("PASS: old willStart/failure/restore cannot reset the active session; current callbacks still execute")
    print("PASS: suspended, transitioning and resumed PiP keep their session; confirmed inactivity still invalidates")
}
final class Harness {
    var pipController: AVPictureInPictureController? = AVPictureInPictureController()
    let pipCoexistenceExperiment = Trial()
    var events = 0
    var wantsPiPActive = true
    var isPiPActiveForUI = true
    var shouldResignForegroundAfterPiPClose = false
    let isClosingPiPFromCustomContentTap = false
    let isStoppingPiP = false
    let pipTransitionExpectedActive: Bool? = nil
    var isPiPTransitioning = false
    var isOwnPiPConfirmedActive = true
    var invalidationReasons: [String] = []
    let shouldLogIOS15PiPStartup = false
    func logIOS15PiPStartupCheckpoint(_ msg: String, controller: AVPictureInPictureController) { events += 1 }
    func allApplicationWindows() -> [Int] { [] }
    func updateDiagnosticsPiPState() {}
    func updateHomeView() {}
    func handleOwnPiPInvalidated(reason: String) { invalidationReasons.append(reason) }
    func prepareCustomViewForPiPStart() {}
    func showPiPContentForOpening() {}
    func scheduleLegacyCustomViewAttachRetries() {}
    func updatePiPAutomaticStartPolicy() {}
    func restoreForegroundWindowsHiddenForPiPCloseIfNeeded() {}
    func resignForegroundAfterPiPCloseIfNeeded(reason: String) {}
    func retryPiPStartWithLegacyControlsStyleFallbackIfNeeded(reason: String) -> Bool { false }
    func retryLegacyPiPStartIfNeeded(reason: String) -> Bool { false }
    func scheduleShortcutPiPStartRetry(reason: String) -> Bool { false }
    func resetPiPStartStateAfterFailure(preservingShortcutRetry: Bool = false) { events += 1 }
    func releaseTransientPlayerLayerPiPAudioSession(reason: String) {}
