import Foundation

enum PiPShortcutAction: String {
    case startFloatingWindow, hideFloatingWindow, startAndHideFloatingWindow
}
enum AppDebugLogger {
    static func log(_ message: String) {}
    static func logCritical(_ message: String) {}
}
enum L10n {
    static func text(_ chinese: String, _ english: String) -> String { english }
}
enum DiagnosticsRuntimeState {
    static func recordUserAction(_ message: String) {}
}
final class PiPStub {
    var isPictureInPictureActive = false
}
final class ContentStub {
    var preferredContentSize = CGSize(width: 0, height: 0)
}
final class ShortcutHideHarness {
    var pipController: PiPStub? = PiPStub()
    var isHiddenReferenceRequested = false
    var isHiddenReferenceSession = false
    var isPiPTransitioning = false
    var wantsPiPActive = false
    var isPiPActiveForUI = true
    var shouldHidePiPAfterShortcutStart = false
    var shouldStopPiPAfterCurrentTransition = false
    var needsHiddenReferenceInfrastructureRefresh = false
    var shouldUsePlayerLayerPiPCompatibility = false
    var needsLegacyPiPCompatibility = true
    var didRetryLegacyPiPStart = false
    var pendingPiPStartWorkItem: DispatchWorkItem?
    var pipStartTimeoutWorkItem: DispatchWorkItem?
    var videoCallContentController: ContentStub? = ContentStub()
    var pipHeight: CGFloat = 44
    var clampedPiPHeight: CGFloat { pipHeight }
    let compactPiPHeight: CGFloat = 44
    var currentMinimumPiPHeight: CGFloat { shouldUsePlayerLayerPiPCompatibility ? 1 : 0.1 }
    var currentPiPSize: CGSize { CGSize(width: 300, height: pipHeight) }
    var isCompactPiPStyle = true
    var directStarts = 0
    var smoothStarts = 0
    var messages = 0
    var commits: [CGFloat] = []
    var promotions = 0
    var styleResets = 0
    var preparationSucceeds = true
    var retryCancellations = 0
    func startHiddenReferencePiP(atMinimumHeight: Bool, source: String, fromShortcut: Bool) {
        precondition(atMinimumHeight && fromShortcut)
        directStarts += 1
    }
    func formattedHeight(_ height: CGFloat) -> String { "\(height)pt" }
    func cancelDelayedPiPHideCountdown(reason: String) {}
    func showMessage(_ message: String) { messages += 1 }
    func commitPiPHeight(_ height: CGFloat) {
        commits.append(height)
        pipHeight = height
        videoCallContentController?.preferredContentSize = currentPiPSize
    }
    func applyPlayerLayerMinimumHeightImmediately(reason: String) { commitPiPHeight(1) }
    func updatePiPSourceGeometry() {}
    func reloadPlayerItemIfNeededForCurrentSize() {}
    func configureRunningText() {}
    func updateHomeView() {}
    func finishPiPTransition() { isPiPTransitioning = false }
    func startPiPSmoothly() { smoothStarts += 1 }
    func promotePlayerLayerMinimumHeightForNormalStartIfNeeded(reason: String) {
        promotions += 1
        if shouldUsePlayerLayerPiPCompatibility { pipHeight = 44 }
    }
    func resetPiPControlsStyleExperimentForNewStartIfNeeded(reason: String) { styleResets += 1 }
    func preparePiPInfrastructureIfNeeded() -> Bool { preparationSucceeds }
    func cancelShortcutPiPStartRetry() { retryCancellations += 1 }
    func recoverStalePiPTransitionIfNeeded(reason: String) {}
    func prepareShortcutPiPStartRetryIfNeeded() {}
    func updatePiPAutomaticStartPolicy() {}
}

@main
struct ShortcutHideTests {
    static func main() {
        precondition(PiPShortcutInstallLinks.installableActions == [.startAndHideFloatingWindow])
        precondition(PiPShortcutInstallLinks.fallbackURLString(for: .startAndHideFloatingWindow) == "globalrefresh://startandhide")
        precondition(PiPShortcutInstallLinks.iCloudURL(for: .startAndHideFloatingWindow)?.lastPathComponent == "5101796358454ce8a5fadc0c41cf51c7")
        for (url, expected) in [
            ("globalrefresh://startandhide", PiPShortcutAction.startAndHideFloatingWindow),
            ("globalrefresh://hide", .hideFloatingWindow),
            ("globalrefresh://start", .startFloatingWindow),
            ("globalrefresh://shortcut?intent=startAndHideFloatingWindow", .startAndHideFloatingWindow)
        ] {
            precondition(ShortcutURLParser.action(from: URL(string: url)!) == expected)
        }
        for playerLayer in [false, true] {
            let active = ShortcutHideHarness()
            active.shouldUsePlayerLayerPiPCompatibility = playerLayer
            active.pipController!.isPictureInPictureActive = true
            active.hidePiPFromShortcut()
            precondition(active.commits == [playerLayer ? 1 : 0.1])
            precondition(active.videoCallContentController!.preferredContentSize.height == active.currentMinimumPiPHeight)
            active.startPiPFromShortcut(shouldHideAfterStart: false)
            precondition(active.promotions == 0 && active.styleResets == 0)
            precondition(active.pipHeight == active.currentMinimumPiPHeight, "Open must not resize an already active PiP")

            let starting = ShortcutHideHarness()
            starting.shouldUsePlayerLayerPiPCompatibility = playerLayer
            starting.isPiPTransitioning = true
            starting.wantsPiPActive = true
            starting.hidePiPFromShortcut()
            precondition(starting.shouldHidePiPAfterShortcutStart && starting.commits.isEmpty && starting.messages == 0)
            starting.pipController!.isPictureInPictureActive = true
            starting.hidePiPAfterShortcutStartIfNeeded()
            starting.hidePiPAfterShortcutStartIfNeeded()
            precondition(starting.commits == [playerLayer ? 1 : 0.1], "Apply a pending hide once")

            let homeStarting = ShortcutHideHarness()
            homeStarting.isPiPTransitioning = true
            homeStarting.wantsPiPActive = true
            homeStarting.pipController!.isPictureInPictureActive = true
            homeStarting.applyOneTapMinimumHeight(source: "Home")
            precondition(homeStarting.shouldHidePiPAfterShortcutStart && homeStarting.commits.isEmpty)
        }
        let retry = ShortcutHideHarness()
        retry.isHiddenReferenceSession = true
        retry.pipHeight = 0.1
        retry.shouldHidePiPAfterShortcutStart = true
        retry.wantsPiPActive = true
        precondition(retry.retryLegacyPiPStartIfNeeded(reason: "simulated iOS17 startup failure"))
        precondition(retry.pipHeight == 44 && retry.shouldHidePiPAfterShortcutStart)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        precondition(retry.smoothStarts == 1)
        retry.pipController!.isPictureInPictureActive = true
        retry.hidePiPAfterShortcutStartIfNeeded()
        precondition(retry.pipHeight == 0.1 && !retry.shouldHidePiPAfterShortcutStart)

        let canceledRetry = ShortcutHideHarness()
        canceledRetry.shouldHidePiPAfterShortcutStart = true
        precondition(canceledRetry.retryLegacyPiPStartIfNeeded(reason: "test cancellation"))
        canceledRetry.pendingPiPStartWorkItem?.cancel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        precondition(canceledRetry.smoothStarts == 0, "Canceled legacy retry must not reopen PiP")

        let inactive = ShortcutHideHarness()
        inactive.hidePiPFromShortcut()
        precondition(inactive.commits.isEmpty && inactive.messages == 1)
        let stopping = ShortcutHideHarness()
        stopping.isPiPTransitioning = true
        stopping.hidePiPFromShortcut()
        precondition(!stopping.shouldHidePiPAfterShortcutStart && stopping.commits.isEmpty && stopping.messages == 0)
        stopping.startPiPFromShortcut(shouldHideAfterStart: true)
        precondition(!stopping.shouldHidePiPAfterShortcutStart && stopping.promotions == 0)
        stopping.pipController!.isPictureInPictureActive = true
        stopping.hidePiPFromShortcut()
        stopping.applyOneTapMinimumHeight(source: "Home")
        precondition(!stopping.shouldHidePiPAfterShortcutStart && stopping.commits.isEmpty)

        let preparationFailure = ShortcutHideHarness()
        preparationFailure.needsHiddenReferenceInfrastructureRefresh = true
        preparationFailure.preparationSucceeds = false
        preparationFailure.shouldHidePiPAfterShortcutStart = true
        preparationFailure.startPiPFromShortcut(shouldHideAfterStart: true)
        precondition(!preparationFailure.shouldHidePiPAfterShortcutStart && preparationFailure.retryCancellations == 1)

        let missingController = ShortcutHideHarness()
        missingController.pipController = nil
        missingController.shouldHidePiPAfterShortcutStart = true
        missingController.startPiPFromShortcut(shouldHideAfterStart: true)
        precondition(!missingController.shouldHidePiPAfterShortcutStart && missingController.retryCancellations == 1)

        let unconfirmed = ShortcutHideHarness()
        unconfirmed.shouldHidePiPAfterShortcutStart = true
        unconfirmed.wantsPiPActive = true
        unconfirmed.hidePiPAfterShortcutStartIfNeeded()
        precondition(unconfirmed.shouldHidePiPAfterShortcutStart && unconfirmed.commits.isEmpty)
        unconfirmed.pipController!.isPictureInPictureActive = true
        unconfirmed.shouldStopPiPAfterCurrentTransition = true
        unconfirmed.hidePiPAfterShortcutStartIfNeeded()
        precondition(unconfirmed.commits.isEmpty)
        let hiddenRoute = ShortcutHideHarness()
        hiddenRoute.isHiddenReferenceRequested = true
        hiddenRoute.hidePiPFromShortcut()
        precondition(hiddenRoute.directStarts == 1)
        print("PASS: imported URLs map to native actions; active and transitioning hides, legacy 44pt retry followed by 0.1pt confirmation, and compatibility isolation")
    }
}
