//
//  ViewController.swift
//  pip_swift
//

import UIKit
import AVKit
import AVFoundation
import CoreMedia
import CoreVideo
import SnapKit
import SwiftUI
import Darwin

enum PiPEngineRoute: String, CaseIterable, Hashable {
    case videoCall
    case playerLayerGenerated
    case referenceIPA
    case referenceIPAPure

    var usesPlayerLayer: Bool {
        switch self {
        case .videoCall:
            return false
        case .playerLayerGenerated, .referenceIPA, .referenceIPAPure:
            return true
        }
    }

    var diagnosticsName: String {
        switch self {
        case .videoCall:
            return "VideoCallContentSource"
        case .playerLayerGenerated:
            return "PlayerLayerGeneratedLongH264"
        case .referenceIPA:
            return "PlayerLayerReferenceMOVComposition"
        case .referenceIPAPure:
            return "PlayerLayerReferencePure"
        }
    }
}

private struct ReferenceIPAVideoPreset {
    let resourceName: String
    let widthRatio: CGFloat
    let heightRatio: CGFloat

    var aspectRatio: CGFloat {
        widthRatio / max(heightRatio, 0.001)
    }
}

enum AppAppearancePreference {
    private static let darkModeForcedKey = "pip.home.darkModeForced"
    private static let lightModeForcedKey = "pip.home.lightModeForced"

    static var isDarkModeForced: Bool {
        get { UserDefaults.standard.bool(forKey: darkModeForcedKey) }
        set {
            setForced(newValue, animated: false)
        }
    }

    static var isLightModeForced: Bool {
        UserDefaults.standard.bool(forKey: lightModeForcedKey)
    }

    static var isStyleForced: Bool {
        isDarkModeForced || isLightModeForced
    }

    static var preferredStyle: UIUserInterfaceStyle {
        if isDarkModeForced {
            return .dark
        }
        if isLightModeForced {
            return .light
        }
        return .unspecified
    }

    static func apply(to window: UIWindow?) {
        window?.overrideUserInterfaceStyle = preferredStyle
        window?.rootViewController?.overrideUserInterfaceStyle = preferredStyle
    }

    static func setForced(_ isForced: Bool, animated: Bool) {
        UserDefaults.standard.set(isForced, forKey: darkModeForcedKey)
        UserDefaults.standard.set(false, forKey: lightModeForcedKey)
        applyCurrentPreference(animated: animated)
    }

    static func setPreferredStyle(_ style: UIUserInterfaceStyle, animated: Bool) {
        switch style {
        case .dark:
            UserDefaults.standard.set(true, forKey: darkModeForcedKey)
            UserDefaults.standard.set(false, forKey: lightModeForcedKey)
        case .light:
            UserDefaults.standard.set(false, forKey: darkModeForcedKey)
            UserDefaults.standard.set(true, forKey: lightModeForcedKey)
        default:
            UserDefaults.standard.set(false, forKey: darkModeForcedKey)
            UserDefaults.standard.set(false, forKey: lightModeForcedKey)
        }
        applyCurrentPreference(animated: animated)
    }

    static func clearForcedStyle(animated: Bool) {
        UserDefaults.standard.set(false, forKey: darkModeForcedKey)
        UserDefaults.standard.set(false, forKey: lightModeForcedKey)
        applyCurrentPreference(animated: animated)
    }

    static func applyCurrentPreference(animated: Bool = false) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        guard animated else {
            UIView.performWithoutAnimation {
                windows.forEach { apply(to: $0) }
            }
            return
        }

        UIView.performWithoutAnimation {
            windows.forEach { $0.layoutIfNeeded() }
        }

        let snapshots: [UIView] = windows.compactMap { window in
            guard let container = activeContentView(in: window),
                  let snapshot = container.snapshotView(afterScreenUpdates: false) else {
                return nil
            }
            snapshot.frame = container.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(snapshot)
            return snapshot
        }

        UIView.performWithoutAnimation {
            windows.forEach {
                apply(to: $0)
                $0.layoutIfNeeded()
                $0.rootViewController?.view.layoutIfNeeded()
            }
        }

        UIView.animate(
            withDuration: 0.14,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut]
        ) {
            snapshots.forEach { $0.alpha = 0 }
        } completion: { _ in
            snapshots.forEach { $0.removeFromSuperview() }
            windows.forEach { forceRedraw($0) }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            windows.forEach { forceRedraw($0) }
        }
    }

    private static func activeContentView(in window: UIWindow) -> UIView? {
        if let tabBarController = window.rootViewController as? UITabBarController,
           let selectedView = tabBarController.selectedViewController?.view {
            return selectedView
        }
        return window.rootViewController?.view
    }

    private static func forceRedraw(_ window: UIWindow) {
        window.setNeedsLayout()
        window.layoutIfNeeded()
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        window.layer.setNeedsDisplay()
        window.rootViewController?.view.layer.setNeedsDisplay()
        forceRedraw(view: window)
    }

    private static func forceRedraw(view: UIView) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        view.setNeedsDisplay()
        view.layer.setNeedsDisplay()
        view.subviews.forEach { forceRedraw(view: $0) }
    }
}

private enum PlayerLayerPiPStartAudioMode {
    case ambientCategoryOnly
    case playbackCategoryOnly
    case playbackActive

    static var defaultStartupMode: PlayerLayerPiPStartAudioMode {
        // 9:39 / beta5 anchor: start with active playback so PiP is possible immediately,
        // then release the audio session after PiP starts.
        .playbackActive
    }

    var category: AVAudioSession.Category {
        switch self {
        case .ambientCategoryOnly:
            return .ambient
        case .playbackCategoryOnly, .playbackActive:
            return .playback
        }
    }

    var options: AVAudioSession.CategoryOptions {
        switch self {
        case .ambientCategoryOnly, .playbackCategoryOnly, .playbackActive:
            return .mixWithOthers
        }
    }

    var shouldActivateSession: Bool {
        switch self {
        case .ambientCategoryOnly, .playbackCategoryOnly:
            return false
        case .playbackActive:
            return true
        }
    }

    var logName: String {
        switch self {
        case .ambientCategoryOnly:
            return "ambient category only"
        case .playbackCategoryOnly:
            return "playback category only"
        case .playbackActive:
            return "playback active"
        }
    }
}

private final class PiPDelegateProxy: NSObject, AVPictureInPictureControllerDelegate {
    weak var owner: ViewController?

    init(owner: ViewController) {
        self.owner = owner
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        owner?.pictureInPictureControllerWillStartPictureInPicture(pictureInPictureController)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        owner?.pictureInPictureControllerDidStartPictureInPicture(pictureInPictureController)
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        owner?.pictureInPictureControllerWillStopPictureInPicture(pictureInPictureController)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        owner?.pictureInPictureControllerDidStopPictureInPicture(pictureInPictureController)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        owner?.pictureInPictureController(pictureInPictureController, failedToStartPictureInPictureWithError: error)
    }
}

class ViewController: UIViewController, AVPictureInPictureControllerDelegate {

    private var playerLayer: AVPlayerLayer!
    private var pipController: AVPictureInPictureController!
    private lazy var pipDelegateProxy = PiPDelegateProxy(owner: self)
    private var pipSourceView: UIView!
    private var pipSourceWidthConstraint: Constraint?
    private var pipSourceHeightConstraint: Constraint?
    private var legacyCustomViewWidthConstraint: Constraint?
    private var legacyCustomViewHeightConstraint: Constraint?
    private var customView: UIView!
    private var textView: UITextView!
    private var clockLabel: UILabel!
    private var clockOverlayView: ClockOverlayView!
    private var pipContentTapGesture: UITapGestureRecognizer?
    private var videoCallContentController: UIViewController?
    private var hostingController: UIHostingController<PiPHomeView>?
    private var scrollDisplayLink: CADisplayLink?
    private var clockDisplayLink: CADisplayLink?
    private var fpsProbeDisplayLink: CADisplayLink?
    private var playerLayerActivityDisplayLink: CADisplayLink?
    private var clockRenderTimer: Timer?
    private var pipRuntimeTimer: Timer?
    private var lastScrollTimestamp: CFTimeInterval?
    private var lastFPSProbeTimestamp: CFTimeInterval?
    private var lastPlayerLayerActivityNudgeAt: CFTimeInterval = 0
    private var lastClockTimestamp: CFTimeInterval?
    private var lastClockNetworkTimestamp: CFTimeInterval?
    private var clockFrameCount = 0
    private var pendingMeasuredPiPFPS: Int?
    private var pendingMeasuredPiPFPSCount = 0
    private var pendingMeasuredPiPFPSStartedAt: CFTimeInterval?
    private var measuredPiPFPS: Int = 0
    private var lastNetworkSample: NetworkTrafficSample?
    private var currentNetworkSpeedText = "↑0B ↓0B"
    private var lastClockOverlayTimeText = ""
    private var lastClockOverlayFPSText = ""
    private var lastClockOverlayNetworkText = ""
    private var lastClockRenderTick = -1
    private var lastBackgroundClockDiagnosticsTimestamp: CFTimeInterval?
    private var lastLoggedPiPSuspendedAtSide: Bool?
    private var windowsBeforePiPStart: Set<ObjectIdentifier> = []
    private var playerEndObserver: NSObjectProtocol?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isPiPTransitioning = false
    private var isStoppingPiP = false
    private var pendingPiPStartWorkItem: DispatchWorkItem?
    private var pipStartTimeoutWorkItem: DispatchWorkItem?
    private var pipTransitionWatchdogWorkItem: DispatchWorkItem?
    private var pendingPlayerItemReloadWorkItem: DispatchWorkItem?
    private var pendingPlayerLayerAudioReleaseWorkItem: DispatchWorkItem?
    private var hasPrimedPlayerLayerPiPStart = false
    private var playerLayerPiPStartAudioMode: PlayerLayerPiPStartAudioMode = .defaultStartupMode
    private var pipTransitionStartedAt: Date?
    private var pipTransitionReason = "未知"
    private var pipTransitionExpectedActive: Bool?
    private var pipExpectedActiveBeforeStop: Bool?
    private var didRecoverStalePiPStop = false
    private var pendingShortcutPiPStartRetry: DispatchWorkItem?
    private var shortcutPiPStartRetryRemaining = 0
    private var pendingPiPEngineRouteAfterStop: PiPEngineRoute?
    private var pendingShortcutPiPStopRetry: DispatchWorkItem?
    private var pendingShortcutPiPStopRetryRemaining = 0
    private var shouldStopPiPAfterCurrentTransition = false
    private var shouldHidePiPAfterShortcutStart = false
    private var shouldResignForegroundAfterPiPClose = false
    private var isClosingPiPFromCustomContentTap = false
    private var windowsHiddenForPiPClose: [(window: UIWindow, alpha: CGFloat)] = []
    private weak var pipDirectCloseGestureHost: UIView?
    private var pipDirectCloseTapGesture: UITapGestureRecognizer?
    private var playerStallObserver: NSObjectProtocol?
    private var playerPauseObserver: NSKeyValueObservation?
    private var playerLayerTimeControlObserver: NSKeyValueObservation?
    private var systemAppearanceFollowTimer: Timer?
    private var lastObservedSystemAppearance: UIUserInterfaceStyle = .unspecified
    private var lastPlayerLayerPipelineRecoveryAt: CFTimeInterval = 0
    private var isAutoHiddenOverheadPaused = false
    private var isPreviewingPiPHeight = false
    private var didRetryLegacyPiPStart = false
    private var didFallbackLegacyPiPControlsStyle = false
    private var pipControlsStyleOverride: Int?
    private var isLegacyPlayerLayerFallbackActive = false
    private var isCompactPiPStyle = true
    private let clockFPSMeasureInterval: CFTimeInterval = 0.8
    private let clockNetworkMeasureInterval: CFTimeInterval = 1.0
    private var isLoadingHomePreferences = false
    private var hasPreparedPiPInfrastructure = false
    private var wantsPiPActive = false
    private var isOwnPiPConfirmedActive = false
    private var pipRuntimeStartedAt: Date?
    private var pipRuntimeDuration: TimeInterval = 0
    private var pipRuntimeStoppedAtText = "暂无"
    private var isPiPStatusInfoVisible = false {
        didSet {
            guard oldValue != isPiPStatusInfoVisible else { return }
            updateHomeView()
        }
    }
    private var overlayResetToken = 0
    private var isSettingsExpanded = false {
        didSet {
            guard oldValue != isSettingsExpanded else { return }
            updateHomeView()
        }
    }
    private var prefersTextScrolling = true
    private var isScrollingEnabled = true {
        didSet {
            guard oldValue != isScrollingEnabled else { return }
            if !isLoadingHomePreferences && !isClockModeEnabled {
                prefersTextScrolling = isScrollingEnabled
                UserDefaults.standard.set(isScrollingEnabled, forKey: userDefaultsScrollingEnabledKey)
            }
            updateHomeView()
        }
    }
    private var remembersPiPHeight = true {
        didSet {
            guard oldValue != remembersPiPHeight else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(remembersPiPHeight, forKey: userDefaultsRememberPiPHeightKey)
            }
            if remembersPiPHeight && !isLoadingHomePreferences {
                saveCurrentPiPHeightPreference()
            }
            updateHomeView()
        }
    }
    private var hidesPiPWhenDocked = false {
        didSet {
            guard oldValue != hidesPiPWhenDocked else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(hidesPiPWhenDocked, forKey: userDefaultsHidePiPWhenDockedKey)
            }
            updateHomeView()
        }
    }
    private var isClockModeEnabled = false {
        didSet {
            guard oldValue != isClockModeEnabled else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(isClockModeEnabled, forKey: userDefaultsClockModeEnabledKey)
            }
            configureRunningText()
            updateHomeView()
        }
    }
    private var isDarkModeForced = AppAppearancePreference.isDarkModeForced {
        didSet {
            guard oldValue != isDarkModeForced else { return }
            if !isLoadingHomePreferences && !isSyncingAppearancePreferenceState {
                AppAppearancePreference.setForced(
                    isDarkModeForced,
                    animated: shouldAnimateNextAppearancePreferenceChange
                )
            }
            updateHomeView()
        }
    }
    private var shouldAnimateNextAppearancePreferenceChange = false
    private var isSyncingAppearancePreferenceState = false
    private var isPiPStoppedNotificationEnabled = KeepAliveNotificationTester.isPiPStoppedNotificationEnabled {
        didSet {
            guard oldValue != isPiPStoppedNotificationEnabled else { return }
            if !isLoadingHomePreferences {
                KeepAliveNotificationTester.isPiPStoppedNotificationEnabled = isPiPStoppedNotificationEnabled
            }
            updateHomeView()
        }
    }
    private var isBackgroundInterruptionNotificationEnabled = KeepAliveNotificationTester.isBackgroundProbeEnabled {
        didSet {
            guard oldValue != isBackgroundInterruptionNotificationEnabled else { return }
            if !isLoadingHomePreferences {
                KeepAliveNotificationTester.isBackgroundProbeEnabled = isBackgroundInterruptionNotificationEnabled
            }
            updateHomeView()
        }
    }
    private var keepAliveNotificationFrequency = KeepAliveNotificationTester.probeFrequency {
        didSet {
            guard oldValue != keepAliveNotificationFrequency else { return }
            if !isLoadingHomePreferences {
                KeepAliveNotificationTester.probeFrequency = keepAliveNotificationFrequency
            }
            updateHomeView()
        }
    }
    private var keepsPiPStatusInfoPersistent = true {
        didSet {
            guard oldValue != keepsPiPStatusInfoPersistent else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(keepsPiPStatusInfoPersistent, forKey: userDefaultsPiPStatusInfoPersistentKey)
            }
            if keepsPiPStatusInfoPersistent {
                isPiPStatusInfoVisible = true
            } else {
                isPiPStatusInfoVisible = false
            }
            updateHomeView()
        }
    }
    private var pipEngineRoute: PiPEngineRoute = .videoCall {
        didSet {
            guard oldValue != pipEngineRoute else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(pipEngineRoute.rawValue, forKey: userDefaultsPiPEngineRouteKey)
                UserDefaults.standard.set(pipEngineRoute.usesPlayerLayer, forKey: userDefaultsPlayerLayerRouteEnabledKey)
            }
            NotificationCenter.default.post(name: Self.piPEngineRuntimeModeDidChangeNotification, object: nil)
            if !pipEngineRoute.usesPlayerLayer, isExtremeSilentModeEnabled {
                isExtremeSilentModeEnabled = false
            }
            applyExtremeSilentModeIfNeeded(reason: "底层切换")
            updateHomeView()
        }
    }
    private var isExtremeSilentModeEnabled = false {
        didSet {
            guard oldValue != isExtremeSilentModeEnabled else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(isExtremeSilentModeEnabled, forKey: userDefaultsExtremeSilentModeEnabledKey)
            }
            if isExtremeSilentModeEnabled, isContentExtremeModeEnabled {
                isContentExtremeModeEnabled = false
            }
            NotificationCenter.default.post(name: Self.piPEngineRuntimeModeDidChangeNotification, object: nil)
            applyExtremeSilentModeIfNeeded(reason: "纯净模式切换")
            updateHomeView()
        }
    }
    private var isContentExtremeModeEnabled = false {
        didSet {
            guard oldValue != isContentExtremeModeEnabled else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(isContentExtremeModeEnabled, forKey: userDefaultsContentExtremeModeEnabledKey)
            }
            if isContentExtremeModeEnabled, isExtremeSilentModeEnabled {
                isExtremeSilentModeEnabled = false
            }
            NotificationCenter.default.post(name: Self.piPEngineRuntimeModeDidChangeNotification, object: nil)
            applyContentExtremeModeIfNeeded(reason: "内容极限模式切换")
            updateHomeView()
        }
    }
    private lazy var pipHeight: CGFloat = compactPiPHeight
    private var isPiPActiveForUI = false {
        didSet {
            guard oldValue != isPiPActiveForUI else { return }
            updateHomeView()
        }
    }
    private lazy var clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.S"
        return formatter
    }()

    private let textPiPWidth: CGFloat = 300
    private let clockPiPWidth: CGFloat = 200
    private var isClockModeFeatureEnabled: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }
    private let defaultPiPHeight: CGFloat = 120
    private let compactPiPHeight: CGFloat = 44
    private let minPiPHeight: CGFloat = 0.1
    private let playerLayerHiddenSurfaceHeight: CGFloat = 1
    private let playerLayerDefaultPiPHeight: CGFloat = 22
    private let maxPiPHeight: CGFloat = 220
    private let playerLayerAudioReleaseDelay: TimeInterval = 0.25
    private let playerLayerActivePlaybackFallbackAttempt = 8
    private let referenceIPATimelineDuration = CMTime(seconds: 120, preferredTimescale: 600)
    private let referenceIPAVideoPresets: [ReferenceIPAVideoPreset] = [
        ReferenceIPAVideoPreset(resourceName: "fc_ref_1_2", widthRatio: 1, heightRatio: 2),
        ReferenceIPAVideoPreset(resourceName: "fc_ref_6_9", widthRatio: 6, heightRatio: 9),
        ReferenceIPAVideoPreset(resourceName: "fc_ref_1_1", widthRatio: 1, heightRatio: 1),
        ReferenceIPAVideoPreset(resourceName: "fc_ref_16_9", widthRatio: 16, heightRatio: 9),
        ReferenceIPAVideoPreset(resourceName: "fc_ref_2_1", widthRatio: 2, heightRatio: 1),
        ReferenceIPAVideoPreset(resourceName: "fc_ref_16_7", widthRatio: 16, heightRatio: 7),
        ReferenceIPAVideoPreset(resourceName: "fc_ref_10_1", widthRatio: 10, heightRatio: 1),
        ReferenceIPAVideoPreset(resourceName: "fc_ref_160_12", widthRatio: 160, heightRatio: 12),
        ReferenceIPAVideoPreset(resourceName: "fc_ref_20_1", widthRatio: 20, heightRatio: 1),
        ReferenceIPAVideoPreset(resourceName: "fc_ref_30_1", widthRatio: 30, heightRatio: 1),
        ReferenceIPAVideoPreset(resourceName: "fc_ref_50_1", widthRatio: 50, heightRatio: 1)
    ]
    private let userDefaultsScrollingEnabledKey = "pip.home.scrollingEnabled"
    private let userDefaultsRememberPiPHeightKey = "pip.home.rememberPiPHeight"
    private let userDefaultsClockModeEnabledKey = "pip.home.clockModeEnabled"
    private let userDefaultsClockModeDefaultMigrationKey = "pip.home.clockModeDefaultMigration.v1"
    private let userDefaultsClockModeDefaultTextMigrationKey = "pip.home.clockModeDefaultMigration.v2.textDefault"
    private let userDefaultsPiPHeightKey = "pip.home.rememberedPiPHeight"
    private let userDefaultsPiPRuntimeStartedAtKey = "pip.home.runtimeStartedAt"
    private let userDefaultsPiPRuntimeDurationKey = "pip.home.runtimeDuration"
    private let userDefaultsPiPRuntimeWasActiveKey = "pip.home.runtimeWasActive"
    private let userDefaultsPiPRuntimeStoppedAtTextKey = "pip.home.runtimeStoppedAtText"
    private let userDefaultsPiPStatusInfoPersistentKey = "pip.home.pipStatusInfoPersistent"
    private let userDefaultsPiPEngineRouteKey = "pip.home.engineRoute"
    private let userDefaultsPlayerLayerRouteEnabledKey = "pip.home.playerLayerRouteEnabled"
    private let userDefaultsExtremeSilentModeEnabledKey = "pip.home.extremeSilentModeEnabled"
    private let userDefaultsContentExtremeModeEnabledKey = "pip.home.contentExtremeModeEnabled"
    private let userDefaultsHidePiPWhenDockedKey = "pip.home.hideWhenDocked"
    static let userDefaultsIOS26AudioKeepAliveKey = "pip.keepAlive.iOS26AudioEnabled"
    static let userDefaultsIOS26PiPOnlyKeepAliveKey = "pip.keepAlive.iOS26PiPOnlyEnabled"
    static let iOS26KeepAliveModeDidChangeNotification = Notification.Name("pip.iOS26KeepAliveModeDidChange")
    static let piPEngineRuntimeModeDidChangeNotification = Notification.Name("pip.engineRuntimeModeDidChange")
    private var currentPiPSize: CGSize {
        CGSize(width: currentPiPWidth, height: effectivePiPSurfaceHeight)
    }
    private var currentPiPWidth: CGFloat {
        shouldRenderClockMode ? clockPiPWidth : textPiPWidth
    }
    private var clampedPiPHeight: CGFloat {
        clampedHeight(pipHeight)
    }
    private var currentMinimumPiPHeight: CGFloat {
        shouldUsePlayerLayerPiPCompatibility ? playerLayerHiddenSurfaceHeight : minPiPHeight
    }
    private var currentPiPHeightStep: CGFloat {
        shouldUsePlayerLayerPiPCompatibility ? 1 : 0.1
    }
    private var effectivePiPSurfaceHeight: CGFloat {
        guard shouldUsePlayerLayerPiPCompatibility, isPiPVisuallyHidden else {
            return clampedPiPHeight
        }
        return playerLayerHiddenSurfaceHeight
    }
    private var pipHeightForDisplay: String {
        formattedHeight(clampedPiPHeight)
    }
    private var pipStatusTitle: String {
        guard isPiPRuntimeActive else {
            return L10n.text("待启用", "Ready")
        }
        return clampedPiPHeight <= 0.15
            ? L10n.text("运行中-已隐藏", "Hidden")
            : L10n.text("运行中", "Running")
    }

    private var isPiPVisuallyHidden: Bool {
        !shouldUsePlayerLayerPiPCompatibility && clampedPiPHeight <= 0.15
    }
    private var isPiPSuspendedAtSide: Bool {
        guard pipController?.isPictureInPictureActive == true else { return false }
        return pipController.isPictureInPictureSuspended
    }
    private var shouldRenderClockMode: Bool {
        isClockModeFeatureEnabled && isClockModeEnabled && !shouldUsePlayerLayerPiPCompatibility && !isPiPVisuallyHidden
    }
    private var isClockModeAvailableForUI: Bool {
        isClockModeFeatureEnabled
    }
    private var pipStatusColor: UIColor {
        isPiPRuntimeActive ? .systemBlue : .secondaryLabel
    }
    private var isPiPRuntimeActive: Bool {
        pipRuntimeStartedAt != nil && isOwnPiPConfirmedActive && (pipController?.isPictureInPictureActive ?? false)
    }
    private var pipRuntimeDurationForDisplay: String {
        if let pipRuntimeStartedAt {
            return formattedRuntime(Date().timeIntervalSince(pipRuntimeStartedAt))
        }
        return formattedRuntime(pipRuntimeDuration)
    }
    private var needsLegacyPiPCompatibility: Bool {
        if #available(iOS 19.0, *) {
            return false
        }
        return true
    }
    private var shouldUsePlayerLayerPiPCompatibility: Bool {
        // 默认使用 beta3 修复后的 VideoCall contentSource 路线，保留 0.1pt 隐藏能力。
        // 高级设置可切到参考悬浮时钟逻辑的 PlayerLayer 路线，用于排查/规避 UIView 合成开销。
        return pipEngineRoute.usesPlayerLayer || isLegacyPlayerLayerFallbackActive
    }
    private var isPlayerLayerRouteEnabled: Bool {
        pipEngineRoute.usesPlayerLayer
    }
    private var isReferenceIPAPureRoute: Bool {
        pipEngineRoute == .referenceIPAPure
    }
    private var shouldAttachCustomViewInPlayerLayerPiP: Bool {
        false
    }

    private var isCurrentAppearanceDark: Bool {
        traitCollection.userInterfaceStyle == .dark
    }

    private var currentSystemAppearance: UIUserInterfaceStyle {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .traitCollection
            .userInterfaceStyle ?? traitCollection.userInterfaceStyle
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        print("画中画初始化前：\(UIApplication.shared.windows)")
        DiagnosticsRuntimeState.updateCurrentPage("悬浮窗")
        AppDebugLogger.trimOnLaunch()
        AppDebugLogger.registerBackgroundFlush()
        AppDebugLogger.log("Home viewDidLoad")
        PowerUsageLogger.markLaunch()
        KeepAliveNotificationTester.sanitizeOnLaunch()
        let keepAliveInterruptionNotice = KeepAliveLogger.markAppLaunch()

        loadHomePreferences()
        loadPiPRuntimeState()
        setupSwiftUI()
        lastObservedSystemAppearance = currentSystemAppearance
        startSystemAppearanceFollowTimerIfNeeded()
        if let keepAliveInterruptionNotice {
            KeepAliveNotificationTester.presentLaunchInterruptionAlert(keepAliveInterruptionNotice, from: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                KeepAliveNotificationTester.presentPendingLocalNotificationAlertIfNeeded(from: self)
            }
        } else {
            KeepAliveNotificationTester.presentPendingLocalNotificationAlertIfNeeded(from: self)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeepAliveModeDidChange), name: Self.iOS26KeepAliveModeDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFrameRatePreferenceDidChange), name: FrameRatePreference.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageDidChange), name: L10n.languageDidChangeNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !shouldResignForegroundAfterPiPClose {
            restoreForegroundWindowsHiddenForPiPCloseIfNeeded()
        }
        DiagnosticsRuntimeState.updateCurrentPage("悬浮窗")
        updateDiagnosticsPiPState()
        enableDefaultPiPStoppedNotificationIfNeeded()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        updateHomeView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard playerLayer != nil else { return }
        centerPlayerLayer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isSettingsExpanded {
            isSettingsExpanded = false
        }
    }

    deinit {
        if let playerEndObserver = playerEndObserver {
            NotificationCenter.default.removeObserver(playerEndObserver)
        }
        if let playerStallObserver = playerStallObserver {
            NotificationCenter.default.removeObserver(playerStallObserver)
        }
        playerPauseObserver?.invalidate()
        playerLayerTimeControlObserver?.invalidate()
        systemAppearanceFollowTimer?.invalidate()
        stopPiPRuntimeTimer()
        NotificationCenter.default.removeObserver(self)
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        pipTransitionWatchdogWorkItem?.cancel()
        pendingPlayerItemReloadWorkItem?.cancel()
        pendingPlayerLayerAudioReleaseWorkItem?.cancel()
        pendingShortcutPiPStartRetry?.cancel()
        cancelShortcutPiPStopRetry()
        hasPrimedPlayerLayerPiPStart = false
        stopDisplayLinks()
        stopClockTimer()
        endBackgroundTask()
    }

    private func setupSwiftUI() {
        let rootView = PiPHomeView(
            isPiPActive: Binding(
                get: { [weak self] in self?.isPiPActiveForUI ?? false },
                set: { [weak self] newValue in self?.isPiPActiveForUI = newValue }
            ),
            isPiPStatusInfoVisible: Binding(
                get: { [weak self] in self?.isPiPStatusInfoVisible ?? false },
                set: { [weak self] newValue in self?.isPiPStatusInfoVisible = newValue }
            ),
            pipHeight: pipHeightForDisplay,
            keepAliveMode: KeepAliveModeText.current,
            pipStatusTitle: pipStatusTitle,
            pipStatusColor: pipStatusColor,
            pipRunningDuration: pipRuntimeDurationForDisplay,
            pipStoppedAtText: pipRuntimeStoppedAtText,
            pipRuntimeStartedAt: pipRuntimeStartedAt,
            overlayResetToken: overlayResetToken,
            isScrollingEnabled: isScrollingEnabled,
            isClockModeEnabled: isClockModeEnabled,
            isClockModeAvailable: isClockModeAvailableForUI,
            isDarkModeForced: isDarkModeForced,
            isCurrentAppearanceDark: isCurrentAppearanceDark,
            isPiPStoppedNotificationEnabled: isPiPStoppedNotificationEnabled,
            isBackgroundInterruptionNotificationEnabled: isBackgroundInterruptionNotificationEnabled,
            keepAliveNotificationFrequency: keepAliveNotificationFrequency,
            keepsPiPStatusInfoPersistent: keepsPiPStatusInfoPersistent,
            remembersPiPHeight: remembersPiPHeight,
            hidesPiPWhenDocked: hidesPiPWhenDocked,
            pipEngineRoute: pipEngineRoute,
            isExtremeSilentModeEnabled: isExtremeSilentModeEnabled,
            isContentExtremeModeEnabled: isContentExtremeModeEnabled,
            isSettingsExpanded: isSettingsExpanded,
            onTogglePiP: { [weak self] in self?.togglePiP() },
            onStartAndHidePiP: { [weak self] in self?.startPiPAndHideFromHome() },
            onShowTutorial: { [weak self] in self?.presentTutorial() },
            onToggleStyle: { [weak self] in self?.togglePiPStyle() },
            onCustomizeHeight: { [weak self] in self?.presentPiPHeightEditor() },
            onToggleScrolling: { [weak self] in self?.toggleScrolling() },
            onSetClockMode: { [weak self] newValue in self?.setClockMode(newValue) },
            onToggleAppearanceMode: { [weak self] in self?.toggleAppearanceMode() },
            onSetPiPStoppedNotificationEnabled: { [weak self] newValue in self?.setPiPStoppedNotificationEnabled(newValue) },
            onSetBackgroundInterruptionNotificationEnabled: { [weak self] newValue in self?.setBackgroundInterruptionNotificationEnabled(newValue) },
            onSetKeepAliveNotificationFrequency: { [weak self] frequency in self?.setKeepAliveNotificationFrequency(frequency) },
            onSetPiPStatusInfoPersistent: { [weak self] newValue in self?.setPiPStatusInfoPersistent(newValue) },
            onToggleSettings: { [weak self] in self?.toggleSettingsPanel() },
            onDismissSettings: { [weak self] in self?.dismissSettingsPanel() },
            onSetRememberPiPHeight: { [weak self] newValue in self?.setRememberPiPHeight(newValue) },
            onSetHidePiPWhenDocked: { [weak self] newValue in self?.setHidePiPWhenDocked(newValue) },
            onSetPiPEngineRoute: { [weak self] route in self?.setPiPEngineRoute(route) },
            onSetExtremeSilentModeEnabled: { [weak self] newValue in self?.setExtremeSilentModeEnabled(newValue) },
            onSetContentExtremeModeEnabled: { [weak self] newValue in self?.setContentExtremeModeEnabled(newValue) }
        )
        let hostingController = UIHostingController(rootView: rootView)
        self.hostingController = hostingController

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.backgroundColor = .systemBackground
        hostingController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        hostingController.didMove(toParent: self)
    }

    private func updateHomeView() {
        recoverStalePiPStopTransitionIfNeeded(reason: "刷新首页")
        syncPiPRuntimeDisplayState()
        syncPiPRuntimeTimerState()
        hostingController?.rootView = PiPHomeView(
            isPiPActive: Binding(
                get: { [weak self] in self?.isPiPActiveForUI ?? false },
                set: { [weak self] newValue in self?.isPiPActiveForUI = newValue }
            ),
            isPiPStatusInfoVisible: Binding(
                get: { [weak self] in self?.isPiPStatusInfoVisible ?? false },
                set: { [weak self] newValue in self?.isPiPStatusInfoVisible = newValue }
            ),
            pipHeight: pipHeightForDisplay,
            keepAliveMode: KeepAliveModeText.current,
            pipStatusTitle: pipStatusTitle,
            pipStatusColor: pipStatusColor,
            pipRunningDuration: pipRuntimeDurationForDisplay,
            pipStoppedAtText: pipRuntimeStoppedAtText,
            pipRuntimeStartedAt: pipRuntimeStartedAt,
            overlayResetToken: overlayResetToken,
            isScrollingEnabled: isScrollingEnabled,
            isClockModeEnabled: isClockModeEnabled,
            isClockModeAvailable: isClockModeAvailableForUI,
            isDarkModeForced: isDarkModeForced,
            isCurrentAppearanceDark: isCurrentAppearanceDark,
            isPiPStoppedNotificationEnabled: isPiPStoppedNotificationEnabled,
            isBackgroundInterruptionNotificationEnabled: isBackgroundInterruptionNotificationEnabled,
            keepAliveNotificationFrequency: keepAliveNotificationFrequency,
            keepsPiPStatusInfoPersistent: keepsPiPStatusInfoPersistent,
            remembersPiPHeight: remembersPiPHeight,
            hidesPiPWhenDocked: hidesPiPWhenDocked,
            pipEngineRoute: pipEngineRoute,
            isExtremeSilentModeEnabled: isExtremeSilentModeEnabled,
            isContentExtremeModeEnabled: isContentExtremeModeEnabled,
            isSettingsExpanded: isSettingsExpanded,
            onTogglePiP: { [weak self] in self?.togglePiP() },
            onStartAndHidePiP: { [weak self] in self?.startPiPAndHideFromHome() },
            onShowTutorial: { [weak self] in self?.presentTutorial() },
            onToggleStyle: { [weak self] in self?.togglePiPStyle() },
            onCustomizeHeight: { [weak self] in self?.presentPiPHeightEditor() },
            onToggleScrolling: { [weak self] in self?.toggleScrolling() },
            onSetClockMode: { [weak self] newValue in self?.setClockMode(newValue) },
            onToggleAppearanceMode: { [weak self] in self?.toggleAppearanceMode() },
            onSetPiPStoppedNotificationEnabled: { [weak self] newValue in self?.setPiPStoppedNotificationEnabled(newValue) },
            onSetBackgroundInterruptionNotificationEnabled: { [weak self] newValue in self?.setBackgroundInterruptionNotificationEnabled(newValue) },
            onSetKeepAliveNotificationFrequency: { [weak self] frequency in self?.setKeepAliveNotificationFrequency(frequency) },
            onSetPiPStatusInfoPersistent: { [weak self] newValue in self?.setPiPStatusInfoPersistent(newValue) },
            onToggleSettings: { [weak self] in self?.toggleSettingsPanel() },
            onDismissSettings: { [weak self] in self?.dismissSettingsPanel() },
            onSetRememberPiPHeight: { [weak self] newValue in self?.setRememberPiPHeight(newValue) },
            onSetHidePiPWhenDocked: { [weak self] newValue in self?.setHidePiPWhenDocked(newValue) },
            onSetPiPEngineRoute: { [weak self] route in self?.setPiPEngineRoute(route) },
            onSetExtremeSilentModeEnabled: { [weak self] newValue in self?.setExtremeSilentModeEnabled(newValue) },
            onSetContentExtremeModeEnabled: { [weak self] newValue in self?.setContentExtremeModeEnabled(newValue) }
        )
    }

    private func loadHomePreferences() {
        isLoadingHomePreferences = true
        defer { isLoadingHomePreferences = false }

        if UserDefaults.standard.object(forKey: userDefaultsScrollingEnabledKey) != nil {
            prefersTextScrolling = UserDefaults.standard.bool(forKey: userDefaultsScrollingEnabledKey)
        }

        if isClockModeFeatureEnabled {
            if !UserDefaults.standard.bool(forKey: userDefaultsClockModeDefaultMigrationKey) {
                UserDefaults.standard.set(true, forKey: userDefaultsClockModeDefaultMigrationKey)
                UserDefaults.standard.set(false, forKey: userDefaultsClockModeEnabledKey)
                isClockModeEnabled = false
            } else if !UserDefaults.standard.bool(forKey: userDefaultsClockModeDefaultTextMigrationKey),
                      UserDefaults.standard.bool(forKey: userDefaultsClockModeEnabledKey) {
                UserDefaults.standard.set(true, forKey: userDefaultsClockModeDefaultTextMigrationKey)
                UserDefaults.standard.set(false, forKey: userDefaultsClockModeEnabledKey)
                isClockModeEnabled = false
            } else {
                UserDefaults.standard.set(true, forKey: userDefaultsClockModeDefaultTextMigrationKey)
                isClockModeEnabled = UserDefaults.standard.object(forKey: userDefaultsClockModeEnabledKey) == nil
                    ? false
                    : UserDefaults.standard.bool(forKey: userDefaultsClockModeEnabledKey)
            }
        } else {
            isClockModeEnabled = false
            UserDefaults.standard.set(false, forKey: userDefaultsClockModeEnabledKey)
        }
        isScrollingEnabled = isClockModeEnabled ? false : prefersTextScrolling
        isDarkModeForced = AppAppearancePreference.isDarkModeForced
        isPiPStoppedNotificationEnabled = KeepAliveNotificationTester.isPiPStoppedNotificationEnabled
        KeepAliveNotificationTester.isBackgroundProbeEnabled = false
        KeepAliveNotificationTester.cancelBackgroundProbeNotifications(reason: "后台中断通知已停用")
        isBackgroundInterruptionNotificationEnabled = false
        keepAliveNotificationFrequency = KeepAliveNotificationTester.probeFrequency
        keepsPiPStatusInfoPersistent = UserDefaults.standard.object(forKey: userDefaultsPiPStatusInfoPersistentKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: userDefaultsPiPStatusInfoPersistentKey)
        isPiPStatusInfoVisible = keepsPiPStatusInfoPersistent
        if let storedRoute = UserDefaults.standard.string(forKey: userDefaultsPiPEngineRouteKey) {
            switch storedRoute {
            case PiPEngineRoute.videoCall.rawValue:
                pipEngineRoute = .videoCall
            case PiPEngineRoute.playerLayerGenerated.rawValue, "playerLayer":
                pipEngineRoute = .playerLayerGenerated
            case PiPEngineRoute.referenceIPA.rawValue, PiPEngineRoute.referenceIPAPure.rawValue:
                pipEngineRoute = .playerLayerGenerated
            default:
                pipEngineRoute = .videoCall
            }
        } else {
            let legacyPlayerLayerEnabled = UserDefaults.standard.object(forKey: userDefaultsPlayerLayerRouteEnabledKey) == nil
                ? false
                : UserDefaults.standard.bool(forKey: userDefaultsPlayerLayerRouteEnabledKey)
            pipEngineRoute = legacyPlayerLayerEnabled ? .playerLayerGenerated : .videoCall
        }
        UserDefaults.standard.set(false, forKey: userDefaultsExtremeSilentModeEnabledKey)
        UserDefaults.standard.set(false, forKey: userDefaultsContentExtremeModeEnabledKey)
        isExtremeSilentModeEnabled = false
        isContentExtremeModeEnabled = false

        remembersPiPHeight = UserDefaults.standard.object(forKey: userDefaultsRememberPiPHeightKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: userDefaultsRememberPiPHeightKey)
        UserDefaults.standard.set(false, forKey: userDefaultsHidePiPWhenDockedKey)
        hidesPiPWhenDocked = false
        let hasRememberedPiPHeight = UserDefaults.standard.object(forKey: userDefaultsPiPHeightKey) != nil
        if remembersPiPHeight, hasRememberedPiPHeight {
            pipHeight = clampedHeight(CGFloat(UserDefaults.standard.double(forKey: userDefaultsPiPHeightKey)))
            isCompactPiPStyle = abs(clampedPiPHeight - compactPiPHeight) < 0.5
        } else if pipEngineRoute.usesPlayerLayer {
            pipHeight = playerLayerDefaultPiPHeight
            isCompactPiPStyle = false
        }
        if pipEngineRoute.usesPlayerLayer, abs(clampedPiPHeight - compactPiPHeight) < 0.5 {
            pipHeight = playerLayerDefaultPiPHeight
            isCompactPiPStyle = false
            if remembersPiPHeight {
                saveCurrentPiPHeightPreference()
            }
        }
        if pipEngineRoute.usesPlayerLayer, isClockModeEnabled {
            isClockModeEnabled = false
            UserDefaults.standard.set(false, forKey: userDefaultsClockModeEnabledKey)
            isScrollingEnabled = prefersTextScrolling
        }
    }

    private func loadPiPRuntimeState() {
        let defaults = UserDefaults.standard
        pipRuntimeStoppedAtText = normalizedStoredPiPRuntimeStoppedAtText()
        let lastDuration = defaults.double(forKey: userDefaultsPiPRuntimeDurationKey)
        if defaults.bool(forKey: userDefaultsPiPRuntimeWasActiveKey) {
            let timestamp = defaults.double(forKey: userDefaultsPiPRuntimeStartedAtKey)
            if timestamp > 0 {
                let detectedStopDate = Date()
                pipRuntimeDuration = max(Date().timeIntervalSince1970 - timestamp, lastDuration)
                pipRuntimeStoppedAtText = formattedStopTime(detectedStopDate)
                defaults.set(pipRuntimeStoppedAtText, forKey: userDefaultsPiPRuntimeStoppedAtTextKey)
                defaults.set(pipRuntimeDuration, forKey: userDefaultsPiPRuntimeDurationKey)
                defaults.set(false, forKey: userDefaultsPiPRuntimeWasActiveKey)
                AppDebugLogger.log("PiP runtime recovered after abnormal interruption, stoppedAt=\(pipRuntimeStoppedAtText), duration=\(formattedRuntime(pipRuntimeDuration))")
                return
            }
        }
        pipRuntimeDuration = lastDuration
    }

    private func syncPiPRuntimeDisplayState() {
        if let pipRuntimeStartedAt {
            pipRuntimeDuration = max(0, Date().timeIntervalSince(pipRuntimeStartedAt))
        } else {
            pipRuntimeStoppedAtText = normalizedStoredPiPRuntimeStoppedAtText()
        }
    }

    private func normalizedStoredPiPRuntimeStoppedAtText() -> String {
        let storedText = UserDefaults.standard.string(forKey: userDefaultsPiPRuntimeStoppedAtTextKey) ?? "暂无"
        guard !storedText.isEmpty, storedText != "暂无" else {
            return L10n.text("暂无", "None")
        }
        return storedText
    }

    private func setRememberPiPHeight(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启记忆悬浮窗高度" : "关闭记忆悬浮窗高度")
        remembersPiPHeight = isEnabled
    }

    private func setHidePiPWhenDocked(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启检测吸附后隐藏" : "关闭检测吸附后隐藏")
        // Disabled for now: dock detection is not stable enough for automatic height changes.
        hidesPiPWhenDocked = false
        UserDefaults.standard.set(false, forKey: userDefaultsHidePiPWhenDockedKey)
    }

    private func setDarkModeForced(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启深色模式" : "关闭深色模式")
        shouldAnimateNextAppearancePreferenceChange = true
        isDarkModeForced = isEnabled
        shouldAnimateNextAppearancePreferenceChange = false
    }

    private func toggleAppearanceMode() {
        let targetStyle: UIUserInterfaceStyle
        if AppAppearancePreference.isDarkModeForced {
            targetStyle = .light
        } else if AppAppearancePreference.isLightModeForced {
            targetStyle = .dark
        } else {
            targetStyle = isCurrentAppearanceDark ? .light : .dark
        }
        DiagnosticsRuntimeState.recordUserAction(targetStyle == .dark ? "切换深色模式" : "切换浅色模式")
        lastObservedSystemAppearance = currentSystemAppearance
        AppAppearancePreference.setPreferredStyle(targetStyle, animated: true)
        isSyncingAppearancePreferenceState = true
        isDarkModeForced = AppAppearancePreference.isDarkModeForced
        isSyncingAppearancePreferenceState = false
        startSystemAppearanceFollowTimerIfNeeded()
        updateHomeView()
    }

    private func startSystemAppearanceFollowTimerIfNeeded() {
        systemAppearanceFollowTimer?.invalidate()
        systemAppearanceFollowTimer = nil
        guard AppAppearancePreference.isStyleForced else { return }
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.handleSystemAppearanceFollowTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        systemAppearanceFollowTimer = timer
    }

    private func handleSystemAppearanceFollowTick() {
        guard AppAppearancePreference.isStyleForced else {
            systemAppearanceFollowTimer?.invalidate()
            systemAppearanceFollowTimer = nil
            lastObservedSystemAppearance = currentSystemAppearance
            return
        }

        let systemAppearance = currentSystemAppearance
        guard systemAppearance != .unspecified else { return }
        if lastObservedSystemAppearance == .unspecified {
            lastObservedSystemAppearance = systemAppearance
            return
        }
        guard systemAppearance != lastObservedSystemAppearance else { return }

        lastObservedSystemAppearance = systemAppearance
        DiagnosticsRuntimeState.recordUserAction("系统外观变化，恢复跟随系统")
        AppAppearancePreference.clearForcedStyle(animated: true)
        isDarkModeForced = AppAppearancePreference.isDarkModeForced
        systemAppearanceFollowTimer?.invalidate()
        systemAppearanceFollowTimer = nil
        updateHomeView()
    }

    private func setPiPStoppedNotificationEnabled(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启悬浮窗被挤通知" : "关闭悬浮窗被挤通知")
        if isEnabled {
            KeepAliveNotificationTester.prepareForPiPStoppedToggle(from: self) { [weak self] granted in
                guard let self else { return }
                self.isPiPStoppedNotificationEnabled = granted
            }
        } else {
            isPiPStoppedNotificationEnabled = false
            KeepAliveNotificationTester.cancelPiPStoppedNotifications(reason: "首页关闭悬浮窗被挤通知")
        }
    }

    private func enableDefaultPiPStoppedNotificationIfNeeded() {
        guard presentedViewController == nil else { return }
        KeepAliveNotificationTester.enablePiPStoppedNotificationByDefaultIfNeeded(from: nil) { [weak self] granted in
            guard let self else { return }
            self.isPiPStoppedNotificationEnabled = granted
        }
    }

    private func setBackgroundInterruptionNotificationEnabled(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启后台中断提醒beta" : "关闭后台中断提醒beta")
        isBackgroundInterruptionNotificationEnabled = false
        KeepAliveNotificationTester.isBackgroundProbeEnabled = false
        KeepAliveNotificationTester.cancelBackgroundProbeNotifications(reason: "后台中断通知已停用")
    }

    private func setKeepAliveNotificationFrequency(_ frequency: KeepAliveNotificationProbeFrequency) {
        DiagnosticsRuntimeState.recordUserAction("切换后台中断提醒频率：\(frequency.title)")
        keepAliveNotificationFrequency = frequency
    }

    private func setPiPStatusInfoPersistent(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启悬浮窗状态常驻" : "关闭悬浮窗状态常驻")
        keepsPiPStatusInfoPersistent = isEnabled
    }

    private func setPlayerLayerRouteEnabled(_ isEnabled: Bool) {
        setPiPEngineRoute(isEnabled ? .playerLayerGenerated : .videoCall)
    }

    private func setPiPEngineRoute(_ requestedRoute: PiPEngineRoute) {
        let route: PiPEngineRoute = requestedRoute.usesPlayerLayer ? .playerLayerGenerated : .videoCall
        guard route != pipEngineRoute else { return }
        if route.usesPlayerLayer, !pipEngineRoute.usesPlayerLayer {
            presentPlayerLayerRouteConfirmation {
                self.applyPiPEngineRoute(route)
            }
            return
        }
        applyPiPEngineRoute(route)
    }

    private func applyPiPEngineRoute(_ route: PiPEngineRoute) {
        if stopActivePiPForEngineRouteSwitchIfNeeded(route) {
            return
        }

        isLegacyPlayerLayerFallbackActive = false
        cancelDelayedPiPHideCountdown(reason: "切换悬浮窗底层")
        if !route.usesPlayerLayer {
            isExtremeSilentModeEnabled = false
        } else {
            isClockModeEnabled = false
            UserDefaults.standard.set(false, forKey: userDefaultsClockModeEnabledKey)
            isScrollingEnabled = prefersTextScrolling
        }
        pipHeight = route.usesPlayerLayer ? playerLayerDefaultPiPHeight : compactPiPHeight
        isCompactPiPStyle = !route.usesPlayerLayer
        if remembersPiPHeight {
            saveCurrentPiPHeightPreference()
        }
        UIView.performWithoutAnimation {
            videoCallContentController?.preferredContentSize = currentPiPSize
            updatePiPSourceGeometry()
            view.layoutIfNeeded()
            CATransaction.flush()
        }

        DiagnosticsRuntimeState.recordUserAction("切换悬浮窗底层：\(route.diagnosticsName)")
        if hasPreparedPiPInfrastructure {
            teardownPiPInfrastructure()
        }
        hasPrimedPlayerLayerPiPStart = false
        didRetryLegacyPiPStart = false
        isLegacyPlayerLayerFallbackActive = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        pipEngineRoute = route
        AppDebugLogger.log("PiP route changed: \(route.diagnosticsName)")
        updateDiagnosticsPiPState()
        updateHomeView()
        showMessage(L10n.text("悬浮窗底层启用方式已切换成功，请重新打开悬浮窗", "Floating window engine changed successfully. Please reopen the floating window."))
    }

    @discardableResult
    private func stopActivePiPForEngineRouteSwitchIfNeeded(_ route: PiPEngineRoute) -> Bool {
        guard pipController?.isPictureInPictureActive == true || isPiPTransitioning else { return false }
        pendingPiPEngineRouteAfterStop = route
        AppDebugLogger.log("PiP route change deferred until current PiP stops: \(route.diagnosticsName)")
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        cancelDelayedPiPHideCountdown(reason: "切换悬浮窗底层")
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        cancelShortcutPiPStartRetry()
        shouldHidePiPAfterShortcutStart = false

        if isPiPTransitioning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.pendingPiPEngineRouteAfterStop == route else { return }
                if self.pipController?.isPictureInPictureActive == true {
                    self.stopPiPSmoothly()
                } else if !self.isPiPTransitioning {
                    self.pendingPiPEngineRouteAfterStop = nil
                    self.applyPiPEngineRoute(route)
                }
            }
        } else {
            stopPiPSmoothly()
        }
        return true
    }

    private var shouldUseVideoCallOffscreenCloseAnimation: Bool {
        !shouldUsePlayerLayerPiPCompatibility
    }

    private func presentPlayerLayerRouteConfirmation(onConfirm: @escaping () -> Void) {
        let message = L10n.text(
            "请确认默认方案解锁120后会导致你日常的b站弹幕以及锁60hz的游戏一顿一顿，可以通过切换新方案解决，但是无法完全隐藏悬浮窗，没有这两个需求就使用默认方案即可",
            "Please confirm that the default route causes your usual Bilibili danmaku or games locked to 60 Hz to stutter after unlocking 120 Hz. Switching to the new route may solve this, but it cannot fully hide the floating window. If you do not need these fixes, keep using the default route."
        )
        let alert = UIAlertController(
            title: L10n.text("确认切换新方案", "Confirm New Route"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.text("确认切换", "Switch"), style: .default) { _ in
            onConfirm()
        })
        present(alert, animated: true)
    }

    private func setExtremeSilentModeEnabled(_ isEnabled: Bool) {
        guard isEnabled != isExtremeSilentModeEnabled else { return }
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启极限静默模式" : "关闭极限静默模式")
        if isEnabled && !isPlayerLayerRouteEnabled {
            setPlayerLayerRouteEnabled(true)
        }
        if isEnabled {
            isContentExtremeModeEnabled = false
        }
        isExtremeSilentModeEnabled = isEnabled
        let message = isEnabled
            ? L10n.text("已开启极限静默模式，并切换为新方案。请重新打开悬浮窗测试。", "Extreme silent mode is on and the new route is active. Reopen PiP to test.")
            : L10n.text("已关闭极限静默模式", "Extreme silent mode is off.")
        showMessage(message)
    }

    private func setContentExtremeModeEnabled(_ isEnabled: Bool) {
        guard isEnabled != isContentExtremeModeEnabled else { return }
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启内容极限模式" : "关闭内容极限模式")
        if isEnabled {
            if isPlayerLayerRouteEnabled {
                setPlayerLayerRouteEnabled(false)
            }
            isExtremeSilentModeEnabled = false
        }
        isContentExtremeModeEnabled = isEnabled
        let message = isEnabled
            ? L10n.text("已开启内容极限模式，请重新打开悬浮窗测试", "Content extreme mode is on. Reopen PiP to test.")
            : L10n.text("已关闭内容极限模式", "Content extreme mode is off.")
        showMessage(message)
    }

    private func applyExtremeSilentModeIfNeeded(reason: String) {
        guard isExtremeSilentModeEnabled else { return }
        stopDisplayLinks()
        stopClockTimer()
        BackgroundTaskManager.shared.forceStopAndDeactivate()
        PowerUsageLogger.markKeepAliveStop()
        DebugDiagnosticsMonitor.setEnabled(false)
        if isClockModeEnabled {
            isClockModeEnabled = false
        }
        if isScrollingEnabled {
            isScrollingEnabled = false
        }
        currentNetworkSpeedText = ""
        AppDebugLogger.log("Extreme silent mode applied: \(reason)")
    }

    private func applyContentExtremeModeIfNeeded(reason: String) {
        guard isContentExtremeModeEnabled else { return }
        stopDisplayLinks()
        stopClockTimer()
        BackgroundTaskManager.shared.forceStopAndDeactivate()
        PowerUsageLogger.markKeepAliveStop()
        DebugDiagnosticsMonitor.setEnabled(false)
        currentNetworkSpeedText = ""
        measuredPiPFPS = 0
        AppDebugLogger.log("Content extreme mode applied: \(reason)")
        guard pipController?.isPictureInPictureActive == true || isPiPTransitioning else { return }
        configureRunningText()
    }

    private func toggleSettingsPanel() {
        DiagnosticsRuntimeState.recordUserAction(isSettingsExpanded ? "首页关闭二级菜单" : "首页打开二级菜单")
        isSettingsExpanded.toggle()
    }

    private func dismissSettingsPanel() {
        guard isSettingsExpanded else { return }
        DiagnosticsRuntimeState.recordUserAction("首页关闭二级菜单")
        isSettingsExpanded = false
    }

    func dismissTransientOverlays() {
        overlayResetToken += 1
        if isSettingsExpanded {
            isSettingsExpanded = false
        } else {
            updateHomeView()
        }
    }

    private func saveCurrentPiPHeightPreference() {
        UserDefaults.standard.set(Double(clampedPiPHeight), forKey: userDefaultsPiPHeightKey)
    }

    private func clampedHeight(_ height: CGFloat) -> CGFloat {
        let steppedHeight = shouldUsePlayerLayerPiPCompatibility
            ? currentMinimumPiPHeight + ((height - currentMinimumPiPHeight) / currentPiPHeightStep).rounded() * currentPiPHeightStep
            : (height / currentPiPHeightStep).rounded() * currentPiPHeightStep
        return min(max(steppedHeight, currentMinimumPiPHeight), maxPiPHeight)
    }

    private func promotePlayerLayerMinimumHeightForNormalStartIfNeeded(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard clampedPiPHeight <= currentMinimumPiPHeight + 0.01 else { return }

        pipHeight = playerLayerDefaultPiPHeight
        isCompactPiPStyle = false
        if remembersPiPHeight {
            saveCurrentPiPHeightPreference()
        }
        videoCallContentController?.preferredContentSize = currentPiPSize
        updatePiPSourceGeometry()
        reloadPlayerItemIfNeededForCurrentSize()
        configureRunningText()
        updateHomeView()
        AppDebugLogger.log("PlayerLayer normal start promoted minimum height to \(formattedHeight(playerLayerDefaultPiPHeight)): \(reason)")
    }

    private func beginPiPRuntimeSession() {
        let start = Date()
        pipRuntimeStartedAt = start
        pipRuntimeDuration = 0
        pipRuntimeStoppedAtText = normalizedStoredPiPRuntimeStoppedAtText()
        let defaults = UserDefaults.standard
        defaults.set(start.timeIntervalSince1970, forKey: userDefaultsPiPRuntimeStartedAtKey)
        defaults.set(0, forKey: userDefaultsPiPRuntimeDurationKey)
        defaults.set(true, forKey: userDefaultsPiPRuntimeWasActiveKey)
        startPiPRuntimeTimerIfNeeded()
        updateDiagnosticsPiPState()
        updateHomeView()
    }

    private func finishPiPRuntimeSession() {
        stopPiPRuntimeTimer()
        if let pipRuntimeStartedAt {
            pipRuntimeDuration = max(0, Date().timeIntervalSince(pipRuntimeStartedAt))
        }
        pipRuntimeStartedAt = nil
        pipRuntimeStoppedAtText = formattedStopTime(Date())
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: userDefaultsPiPRuntimeWasActiveKey)
        defaults.set(pipRuntimeDuration, forKey: userDefaultsPiPRuntimeDurationKey)
        defaults.set(pipRuntimeStoppedAtText, forKey: userDefaultsPiPRuntimeStoppedAtTextKey)
        updateDiagnosticsPiPState()
        AppDebugLogger.log("PiP runtime stopped at \(pipRuntimeStoppedAtText)")
        updateHomeView()
    }

    private func syncPiPRuntimeTimerState() {
        if pipRuntimeStartedAt != nil {
            startPiPRuntimeTimerIfNeeded()
        } else {
            stopPiPRuntimeTimer()
        }
    }

    private func startPiPRuntimeTimerIfNeeded() {
        guard pipRuntimeTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickPiPRuntimeTimer()
        }
        RunLoop.main.add(timer, forMode: .common)
        pipRuntimeTimer = timer
    }

    private func stopPiPRuntimeTimer() {
        pipRuntimeTimer?.invalidate()
        pipRuntimeTimer = nil
    }

    private func tickPiPRuntimeTimer() {
        guard let pipRuntimeStartedAt else {
            stopPiPRuntimeTimer()
            return
        }
        pipRuntimeDuration = max(0, Date().timeIntervalSince(pipRuntimeStartedAt))
        updateHomeView()
    }

    private func updateDiagnosticsPiPState() {
        let state = [
            "active=\(pipController?.isPictureInPictureActive ?? false)",
            "suspended=\(isPiPSuspendedAtSide)",
            "own=\(isOwnPiPConfirmedActive)",
            "ui=\(isPiPActiveForUI)",
            "wants=\(wantsPiPActive)",
            "transition=\(isPiPTransitioning)",
            "height=\(formattedHeight(clampedPiPHeight))",
            "width=\(Int(currentPiPWidth))pt",
            "scroll=\(isScrollingEnabled)",
            "clock=\(isClockModeEnabled)",
            "silent=\(isExtremeSilentModeEnabled)",
            "hideDocked=\(hidesPiPWhenDocked)",
            "render=\(shouldRenderClockMode ? "clock" : "text")",
            "route=\(pipEngineRoute.diagnosticsName)",
            "mode=\(shouldUsePiPOnlyKeepAlive ? "PiP保活-低功耗" : "音频强保活")"
        ].joined(separator: ",")
        DiagnosticsRuntimeState.updatePiPState(state)
        DiagnosticsRuntimeState.updatePiPSurfaceState(pipSurfaceDiagnosticsText)
        updateDisplaySleepDiagnostics()
    }

    private var pipSurfaceDiagnosticsText: String {
        let contentView = videoCallContentController?.view
        let parts = [
            "size=\(formatSize(currentPiPSize))",
            "path=\(pipContentSourceDiagnosticsText)",
            "source=\(viewDiagnosticsText(pipSourceView))",
            "content=\(viewDiagnosticsText(contentView))",
            "custom=\(viewDiagnosticsText(customView))",
            "text=\(viewDiagnosticsText(textView))",
            "clock=\(viewDiagnosticsText(clockLabel))",
            "playerLayer=\(layerDiagnosticsText(playerLayer))"
        ]
        return "surface{\(parts.joined(separator: ";"))}"
    }

    private var pipContentSourceDiagnosticsText: String {
        if shouldUsePlayerLayerPiPCompatibility {
            return "playerLayer"
        }
        return "videoCall"
    }

    private func logPiPSurfaceDiagnostics(_ reason: String) {
        AppDebugLogger.log("PiP surface diagnostics (\(reason)): \(pipSurfaceDiagnosticsText)")
    }

    private func updateDisplaySleepDiagnostics(reason: String? = nil, shouldLog: Bool = false) {
        let text = displaySleepDiagnosticsText
        DiagnosticsRuntimeState.updateDisplaySleepState(text)
        guard shouldLog else { return }
        let reasonText = reason.map { "（\($0)）" } ?? ""
        AppDebugLogger.log("熄屏检测\(reasonText)：\(text)")
    }

    private var displaySleepDiagnosticsText: String {
        let player = playerLayer?.player
        let item = player?.currentItem
        let playerState = [
            "idleDisabled=\(UIApplication.shared.isIdleTimerDisabled)",
            "mode=\(shouldUsePiPOnlyKeepAlive ? "PiP低功耗" : "音频强保活")",
            "keepAlive=\(shouldKeepPiPPlaybackAlive)",
            "requiresPlayerLayer=\(requiresPlayerLayerForPiP)",
            "backingPlayer=\(shouldPrepareBackingPlayerForPlayback)",
            "shouldPlayBacking=\(shouldPlayBackingPlayerForKeepAlive)",
            "pipActive=\(pipController?.isPictureInPictureActive ?? false)",
            "pipPossible=\(pipController?.isPictureInPicturePossible ?? false)",
            "wants=\(wantsPiPActive)",
            "transition=\(isPiPTransitioning)",
            "playerRate=\(String(format: "%.2f", player?.rate ?? 0))",
            "playerControl=\(timeControlStatusText(player?.timeControlStatus))",
            "playerSleepPrevent=\(player?.preventsDisplaySleepDuringVideoPlayback.description ?? "nil")",
            "item=\(playerItemStatusText(item?.status))"
        ]
        return playerState.joined(separator: ",")
    }

    private func timeControlStatusText(_ status: AVPlayer.TimeControlStatus?) -> String {
        guard let status else { return "nil" }
        switch status {
        case .paused:
            return "paused"
        case .waitingToPlayAtSpecifiedRate:
            return "waiting"
        case .playing:
            return "playing"
        @unknown default:
            return "unknown"
        }
    }

    private func playerItemStatusText(_ status: AVPlayerItem.Status?) -> String {
        guard let status else { return "nil" }
        switch status {
        case .unknown:
            return "unknown"
        case .readyToPlay:
            return "ready"
        case .failed:
            return "failed"
        @unknown default:
            return "unknown"
        }
    }

    private func viewDiagnosticsText(_ view: UIView?) -> String {
        guard let view else { return "nil" }
        let layerColor = view.layer.backgroundColor.flatMap { UIColor(cgColor: $0).debugRGBAString } ?? "nil"
        let borderColor = view.layer.borderColor.flatMap { UIColor(cgColor: $0).debugRGBAString } ?? "nil"
        return [
            "frame=\(formatRect(view.frame))",
            "bounds=\(formatRect(view.bounds))",
            "hidden=\(view.isHidden)",
            "alpha=\(formatNumber(view.alpha))",
            "opaque=\(view.isOpaque)",
            "bg=\(view.backgroundColor?.debugRGBAString ?? "nil")",
            "layerBg=\(layerColor)",
            "layerOpacity=\(formatNumber(CGFloat(view.layer.opacity)))",
            "layerOpaque=\(view.layer.isOpaque)",
            "corner=\(formatNumber(view.layer.cornerRadius))",
            "border=\(formatNumber(view.layer.borderWidth))",
            "borderColor=\(borderColor)"
        ].joined(separator: ",")
    }

    private func layerDiagnosticsText(_ layer: CALayer?) -> String {
        guard let layer else { return "nil" }
        let layerColor = layer.backgroundColor.flatMap { UIColor(cgColor: $0).debugRGBAString } ?? "nil"
        let borderColor = layer.borderColor.flatMap { UIColor(cgColor: $0).debugRGBAString } ?? "nil"
        return [
            "frame=\(formatRect(layer.frame))",
            "bounds=\(formatRect(layer.bounds))",
            "hidden=\(layer.isHidden)",
            "opacity=\(formatNumber(CGFloat(layer.opacity)))",
            "opaque=\(layer.isOpaque)",
            "bg=\(layerColor)",
            "corner=\(formatNumber(layer.cornerRadius))",
            "border=\(formatNumber(layer.borderWidth))",
            "borderColor=\(borderColor)"
        ].joined(separator: ",")
    }

    private func formatSize(_ size: CGSize) -> String {
        "\(formatNumber(size.width))x\(formatNumber(size.height))"
    }

    private func formatRect(_ rect: CGRect) -> String {
        "\(formatNumber(rect.origin.x)),\(formatNumber(rect.origin.y)),\(formatNumber(rect.width)),\(formatNumber(rect.height))"
    }

    private func formatNumber(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    private func formattedRuntime(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func formattedStopTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M/d HH:mm:ss"
        return formatter.string(from: date)
    }

    private func preparePiPInfrastructureIfNeeded() -> Bool {
        guard !hasPreparedPiPInfrastructure else {
            return pipController != nil
        }

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("不支持画中画")
            AppDebugLogger.log("PiP unsupported")
            return false
        }

        AppDebugLogger.log("Prepare PiP infrastructure begin")
        setupPiPSourceView()
        setupCustomView()
        if shouldUsePlayerLayerPiPCompatibility {
            preparePlayerLayerVideoOnlyAudioState(reason: "准备PlayerLayer参考素材PiP")
        } else if !shouldUsePiPOnlyKeepAlive {
            configurePiPAudioSession()
        } else {
            releaseMediaAudioSessionForPiPOnly(reason: "准备低功耗PiP")
        }
        if shouldPrepareBackingPlayerForPlayback {
            setupPlayer()
            guard playerLayer != nil else {
                AppDebugLogger.log("Prepare PiP failed: playerLayer nil")
                teardownPiPInfrastructure()
                return false
            }
        }
        setupPip()
        guard pipController != nil else {
            AppDebugLogger.log("Prepare PiP failed: pipController nil")
            teardownPiPInfrastructure()
            return false
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
        hasPreparedPiPInfrastructure = true
        AppDebugLogger.log("Prepare PiP infrastructure success")
        return true
    }

    private func teardownPiPInfrastructure() {
        stopClockTimer()
        stopPlayerLayerActivityDisplayLink(reason: "拆除悬浮窗底层")
        cancelDelayedPiPHideCountdown(reason: "拆除悬浮窗底层")
        pendingPlayerLayerAudioReleaseWorkItem?.cancel()
        pendingPlayerLayerAudioReleaseWorkItem = nil
        if let playerEndObserver {
            NotificationCenter.default.removeObserver(playerEndObserver)
            self.playerEndObserver = nil
        }
        if let playerStallObserver {
            NotificationCenter.default.removeObserver(playerStallObserver)
            self.playerStallObserver = nil
        }
        playerPauseObserver?.invalidate()
        playerPauseObserver = nil
        playerLayerTimeControlObserver?.invalidate()
        playerLayerTimeControlObserver = nil
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        pipController?.removeObserver(self, forKeyPath: "isPictureInPictureSuspended")
        pipController = nil
        videoCallContentController = nil
        customView?.removeFromSuperview()
        customView = nil
        textView = nil
        clockLabel = nil
        pipSourceView?.removeFromSuperview()
        pipSourceView = nil
        pipSourceWidthConstraint = nil
        pipSourceHeightConstraint = nil
        legacyCustomViewWidthConstraint = nil
        legacyCustomViewHeightConstraint = nil
        hasPreparedPiPInfrastructure = false
    }

    private func setupPiPSourceView() {
        pipSourceView = UIView()
        pipSourceView.backgroundColor = .clear
        pipSourceView.isOpaque = false
        pipSourceView.isUserInteractionEnabled = false
        pipSourceView.layer.cornerRadius = 18
        pipSourceView.layer.cornerCurve = .continuous
        pipSourceView.clipsToBounds = true
        view.addSubview(pipSourceView)
        pipSourceView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            pipSourceWidthConstraint = make.width.equalTo(currentPiPSize.width).constraint
            pipSourceHeightConstraint = make.height.equalTo(currentPiPSize.height).constraint
        }
    }

    private func setupPlayer() {
        guard let playerItem = makePlayerItem() else {
            print("未能生成画中画占位视频")
            AppDebugLogger.log("makePlayerItem failed")
            return
        }

        playerLayer = AVPlayerLayer()
        playerLayer.frame = centeredPreviewFrame()
        playerLayer.backgroundColor = UIColor.clear.cgColor
        playerLayer.isOpaque = false
        playerLayer.opacity = shouldUsePlayerLayerPiPCompatibility ? 1 : 0
        playerLayer.videoGravity = .resizeAspect
        playerLayer.needsDisplayOnBoundsChange = false

        let player = AVPlayer(playerItem: playerItem)
        configureBackingPlayerForPiP(player)
        player.actionAtItemEnd = .none
        player.isMuted = true
        player.volume = 0
        player.allowsExternalPlayback = shouldUsePlayerLayerPiPCompatibility
        playerLayer.player = player
        observeLooping(for: playerItem)
        observePlaybackHealth(for: player, item: playerItem)
        if shouldUsePlayerLayerPiPCompatibility {
            if FrameRatePreference.isHighRefreshEnabled {
                player.play()
                scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer按原作者方式创建后播放")
            } else {
                player.pause()
            }
        }

        view.layer.insertSublayer(playerLayer, at: 0)
    }

    private func configureBackingPlayerForPiP(_ player: AVPlayer) {
        player.preventsDisplaySleepDuringVideoPlayback = false
        if #available(iOS 14.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
    }

    private func setupPip() {
        if shouldUsePlayerLayerPiPCompatibility {
            guard let playerLayer else { return }
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
        } else if #available(iOS 15.0, *) {
            let contentController = AVPictureInPictureVideoCallViewController()
            contentController.preferredContentSize = currentPiPSize
            contentController.view.backgroundColor = .clear
            contentController.view.isOpaque = false
            contentController.view.layer.backgroundColor = UIColor.clear.cgColor
            contentController.view.layer.isOpaque = false
            contentController.view.clipsToBounds = true
            videoCallContentController = contentController
            attachCustomViewToPiPContent()

            let contentSource = AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: pipSourceView,
                contentViewController: contentController
            )
            pipController = AVPictureInPictureController(contentSource: contentSource)
            AppDebugLogger.log("PiP content source: videoCall")
        } else {
            guard let playerLayer else { return }
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
            AppDebugLogger.log("PiP content source: legacy playerLayer")
        }
        guard pipController != nil else { return }
        pipController.delegate = pipDelegateProxy
        applyPiPControlsStyle()
        pipController.requiresLinearPlayback = true
        updatePiPAutomaticStartPolicy()
        // 监听侧边吸附状态变化，吸附时停掉所有活动，恢复时重启
        pipController.addObserver(self, forKeyPath: "isPictureInPictureSuspended", options: [.new], context: nil)
    }

    private var shouldExperimentWithLegacyPiPControlsStyle2: Bool {
        false
    }

    private var preferredPiPControlsStyle: Int {
        if let pipControlsStyleOverride {
            return pipControlsStyleOverride
        }
        if #available(iOS 16.0, *) {
            return 2
        }
        return 1
    }

    private func applyPiPControlsStyle() {
        let style = preferredPiPControlsStyle
        pipController.setValue(style, forKey: "controlsStyle")
        AppDebugLogger.log("PiP controlsStyle applied: \(style), legacyExperiment=\(shouldExperimentWithLegacyPiPControlsStyle2)")
    }

    private func resetPiPControlsStyleExperimentForNewStartIfNeeded(reason: String) {
        guard shouldExperimentWithLegacyPiPControlsStyle2 else { return }
        let hadFallbackState = didFallbackLegacyPiPControlsStyle || pipControlsStyleOverride != nil
        didFallbackLegacyPiPControlsStyle = false
        pipControlsStyleOverride = nil
        guard hadFallbackState,
              hasPreparedPiPInfrastructure,
              pipController?.isPictureInPictureActive != true,
              !isPiPTransitioning
        else {
            return
        }
        AppDebugLogger.log("Reset iOS15 PiP controlsStyle experiment for new start: \(reason)")
        teardownPiPInfrastructure()
    }

    private func setupCustomView() {
        customView = UIView()
        customView.backgroundColor = .white
        customView.isOpaque = true
        customView.isUserInteractionEnabled = true
        customView.clipsToBounds = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handlePiPContentTap(_:)))
        tapGesture.cancelsTouchesInView = false
        customView.addGestureRecognizer(tapGesture)
        pipContentTapGesture = tapGesture

        textView = UITextView()
        textView.text = originalPiPText
        textView.backgroundColor = .black
        textView.textColor = .white
        textView.isUserInteractionEnabled = false
        customView.addSubview(textView)
        textView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        clockLabel = UILabel()
        clockLabel.textAlignment = .center
        clockLabel.textColor = .black
        clockLabel.backgroundColor = .white
        clockLabel.isOpaque = false
        clockLabel.layer.backgroundColor = UIColor.white.cgColor
        clockLabel.layer.isOpaque = false
        clockLabel.adjustsFontSizeToFitWidth = true
        clockLabel.minimumScaleFactor = 0.45
        clockLabel.baselineAdjustment = .alignCenters
        clockLabel.isHidden = true
        customView.addSubview(clockLabel)
        clockLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        clockOverlayView = ClockOverlayView()
        clockOverlayView.isHidden = true
        clockOverlayView.alpha = 0
        customView.addSubview(clockOverlayView)
        clockOverlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        configureRunningText()
    }

    private func attachCustomViewToPiPContent() {
        guard !shouldUsePlayerLayerPiPCompatibility else { return }
        guard let hostView = videoCallContentController?.view, let customView else { return }
        if customView.superview !== hostView {
            customView.removeFromSuperview()
            hostView.addSubview(customView)
            customView.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
        hostView.layoutIfNeeded()
    }

    private var originalPiPText: String {
        let line = L10n.text("悬浮窗运行中", "Floating window running")
        return Array(repeating: line, count: 10).joined(separator: "\n")
    }

    private func togglePiP() {
        DiagnosticsRuntimeState.recordUserAction((pipController?.isPictureInPictureActive ?? false) ? "点击关闭悬浮窗" : "点击开启悬浮窗")
        updateDiagnosticsPiPState()
        AppDebugLogger.log("Toggle PiP tapped, active=\(pipController?.isPictureInPictureActive ?? false), prepared=\(hasPreparedPiPInfrastructure), wants=\(wantsPiPActive)")
        if pipController?.isPictureInPictureActive != true {
            promotePlayerLayerMinimumHeightForNormalStartIfNeeded(reason: "首页普通开启")
            resetPiPControlsStyleExperimentForNewStartIfNeeded(reason: "首页普通开启")
        }
        if pipController == nil, !preparePiPInfrastructureIfNeeded() {
            isPiPActiveForUI = false
            showMessage(L10n.text("当前环境不支持悬浮窗", "Floating window is not supported here."))
            return
        }

        guard let pipController else {
            isPiPActiveForUI = false
            showMessage(L10n.text("当前环境不支持悬浮窗", "Floating window is not supported here."))
            return
        }

        recoverStalePiPTransitionIfNeeded(reason: "用户点击悬浮窗按钮")

        if isPiPTransitioning {
            AppDebugLogger.log("Toggle PiP ignored while transitioning")
            return
        }

        if pipController.isPictureInPictureActive {
            AppDebugLogger.log("Stop PiP requested")
            wantsPiPActive = false
            cancelDelayedPiPHideCountdown(reason: "首页关闭悬浮窗")
            updatePiPAutomaticStartPolicy()
            pendingPiPStartWorkItem?.cancel()
            pipStartTimeoutWorkItem?.cancel()
            isPiPActiveForUI = false
            stopPiPSmoothly()
        } else {
            AppDebugLogger.log("Start PiP requested")
            cancelDelayedPiPHideCountdown(reason: "首页普通开启悬浮窗")
            wantsPiPActive = true
            hasPrimedPlayerLayerPiPStart = false
            updatePiPAutomaticStartPolicy()
            didRetryLegacyPiPStart = false
            isPiPActiveForUI = true
            configureRunningText()
            startPiPSmoothly()
        }
    }

    private func startPiPAndHideFromHome() {
        applyOneTapMinimumHeight(source: "首页")
    }

    @discardableResult
    func performPendingShortcutActionIfNeeded(reason: String) -> Bool {
        guard let action = PiPShortcutActionCenter.consumePendingAction() else { return false }
        DiagnosticsRuntimeState.recordUserAction("快捷方式：\(shortcutActionTitle(action))")
        AppDebugLogger.log("Shortcut action requested: \(action.rawValue), reason=\(reason)")

        switch action {
        case .startFloatingWindow:
            startPiPFromShortcut(shouldHideAfterStart: false)
        case .hideFloatingWindow:
            hidePiPFromShortcut()
        case .startAndHideFloatingWindow:
            startPiPFromShortcut(shouldHideAfterStart: true)
        }
        return true
    }

    private func applyOneTapMinimumHeight(source: String) {
        let actionTitle = shouldUsePlayerLayerPiPCompatibility ? "一键1pt" : "一键0.1pt"
        DiagnosticsRuntimeState.recordUserAction("\(source)：\(actionTitle)")
        AppDebugLogger.log("\(source) \(actionTitle) requested")

        guard let pipController, pipController.isPictureInPictureActive else {
            shouldHidePiPAfterShortcutStart = false
            cancelDelayedPiPHideCountdown(reason: "\(source)\(actionTitle)但悬浮窗未开启")
            showMessage(L10n.text(
                "请先开启悬浮窗并拖到侧边吸附",
                "Enable PiP and dock it to the edge first."
            ))
            return
        }

        shouldHidePiPAfterShortcutStart = false
        cancelDelayedPiPHideCountdown(reason: "\(source)\(actionTitle)")
        commitPiPHeight(currentMinimumPiPHeight)
        showMessage(shouldUsePlayerLayerPiPCompatibility
            ? L10n.text("已调整到1pt", "Set to 1 pt.")
            : L10n.text("已调整到0.1pt", "Set to 0.1 pt."))
    }

    private func startPiPFromShortcut(shouldHideAfterStart: Bool) {
        // BETA5_ANCHOR_SHORTCUT_START_AND_HIDE:
        // 快捷指令“打开悬浮窗”只负责打开；“打开并隐藏悬浮窗”在 PiP 真正启动后缩到当前方案最小高度。
        if !shouldHideAfterStart || shouldUsePlayerLayerPiPCompatibility {
            promotePlayerLayerMinimumHeightForNormalStartIfNeeded(reason: "快捷指令普通开启")
        }
        resetPiPControlsStyleExperimentForNewStartIfNeeded(reason: shouldHideAfterStart ? "快捷指令启用并隐藏" : "快捷指令普通开启")
        if !shouldHideAfterStart {
            cancelDelayedPiPHideCountdown(reason: "普通开启悬浮窗")
        }
        if pipController == nil, !preparePiPInfrastructureIfNeeded() {
            isPiPActiveForUI = false
            shouldHidePiPAfterShortcutStart = false
            cancelDelayedPiPHideCountdown(reason: "悬浮窗启动失败")
            showMessage(L10n.text("当前环境不支持悬浮窗", "Floating window is not supported here."))
            return
        }

        guard let pipController else {
            isPiPActiveForUI = false
            shouldHidePiPAfterShortcutStart = false
            cancelDelayedPiPHideCountdown(reason: "悬浮窗控制器为空")
            showMessage(L10n.text("当前环境不支持悬浮窗", "Floating window is not supported here."))
            return
        }

        recoverStalePiPTransitionIfNeeded(reason: "快捷方式打开悬浮窗")

        guard !isPiPTransitioning else {
            shouldHidePiPAfterShortcutStart = shouldHidePiPAfterShortcutStart || shouldHideAfterStart
            AppDebugLogger.log("Shortcut start ignored: PiP transitioning")
            return
        }

        if pipController.isPictureInPictureActive {
            shouldHidePiPAfterShortcutStart = false
            if shouldHideAfterStart {
                if shouldUsePlayerLayerPiPCompatibility {
                    applyPlayerLayerMinimumHeightImmediately(reason: "悬浮窗已开启")
                } else {
                    hidePiPFromShortcut()
                }
            } else {
                showMessage(L10n.text("悬浮窗已开启", "Floating window is already on."))
            }
            return
        }

        shouldHidePiPAfterShortcutStart = shouldHideAfterStart
        AppDebugLogger.log("Shortcut start: inactive PiP -> start, hideAfterStart=\(shouldHideAfterStart)")
        prepareShortcutPiPStartRetryIfNeeded()
        AppDebugLogger.log("Start PiP requested by shortcut")
        wantsPiPActive = true
        updatePiPAutomaticStartPolicy()
        didRetryLegacyPiPStart = false
        isPiPActiveForUI = true
        configureRunningText()
        startPiPSmoothly()
    }

    private func prepareShortcutPiPStartRetryIfNeeded() {
        guard pipController?.isPictureInPictureActive != true else {
            cancelShortcutPiPStartRetry()
            return
        }
        shortcutPiPStartRetryRemaining = 2
        pendingShortcutPiPStartRetry?.cancel()
    }

    private func cancelShortcutPiPStartRetry() {
        pendingShortcutPiPStartRetry?.cancel()
        pendingShortcutPiPStartRetry = nil
        shortcutPiPStartRetryRemaining = 0
    }

    private func scheduleShortcutPiPStartRetry(reason: String) -> Bool {
        guard shortcutPiPStartRetryRemaining > 0 else { return false }
        shortcutPiPStartRetryRemaining -= 1
        pendingShortcutPiPStartRetry?.cancel()

        let delay: TimeInterval = shortcutPiPStartRetryRemaining == 1 ? 1.2 : 2.5
        AppDebugLogger.log("Shortcut PiP start retry scheduled: \(reason), delay=\(delay)s, remaining=\(shortcutPiPStartRetryRemaining)")
        let workItem = DispatchWorkItem { [weak self] in
            guard
                let self,
                self.pipController?.isPictureInPictureActive != true,
                !self.isPiPTransitioning
            else {
                return
            }
            AppDebugLogger.log("Shortcut PiP start retry fired: \(reason)")
            self.wantsPiPActive = true
            self.updatePiPAutomaticStartPolicy()
            self.isPiPActiveForUI = true
            self.configureRunningText()
            self.startPiPSmoothly()
        }
        pendingShortcutPiPStartRetry = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return true
    }

    private func hidePiPFromShortcut() {
        guard let pipController, pipController.isPictureInPictureActive else {
            shouldHidePiPAfterShortcutStart = false
            cancelDelayedPiPHideCountdown(reason: "手动隐藏但悬浮窗未开启")
            showMessage(L10n.text("请先开启悬浮窗并吸附到侧边", "Enable PiP and dock it to the edge first."))
            return
        }

        cancelDelayedPiPHideCountdown(reason: "立即隐藏悬浮窗")
        commitPiPHeight(currentMinimumPiPHeight)
        showMessage(shouldUsePlayerLayerPiPCompatibility
            ? L10n.text("已调整到新方案最小尺寸", "Set to the minimum size for the new route.")
            : L10n.text("已隐藏悬浮窗", "Floating window hidden."))
    }

    private func hidePiPAfterShortcutStartIfNeeded() {
        guard shouldHidePiPAfterShortcutStart else { return }
        shouldHidePiPAfterShortcutStart = false
        if shouldUsePlayerLayerPiPCompatibility {
            applyPlayerLayerMinimumHeightImmediately(reason: "新方案启动完成")
            return
        }
        commitPiPHeight(currentMinimumPiPHeight)
        showMessage(shouldUsePlayerLayerPiPCompatibility
            ? L10n.text("已打开并调整到新方案最小尺寸", "Floating window opened at the new route minimum size.")
            : L10n.text("已打开并隐藏悬浮窗", "Floating window opened and hidden."))
    }

    private func applyPlayerLayerMinimumHeightImmediately(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else {
            hidePiPFromShortcut()
            return
        }
        guard pipController?.isPictureInPictureActive == true else { return }

        shouldHidePiPAfterShortcutStart = false
        commitPiPHeight(currentMinimumPiPHeight)
        AppDebugLogger.log("PlayerLayer one-tap shrink applied: \(reason), height=\(formattedHeight(currentMinimumPiPHeight))")
    }

    private func cancelDelayedPiPHideCountdown(reason: String) {
        _ = reason
    }

    private func stopPiPFromShortcut() {
        recoverStalePiPTransitionIfNeeded(reason: "快捷方式关闭悬浮窗")

        let hadKnownPiPSession = pipController != nil && (
            pipController?.isPictureInPictureActive == true
                || isOwnPiPConfirmedActive
                || isPiPActiveForUI
                || pipRuntimeStartedAt != nil
                || wantsPiPActive
                || isPiPTransitioning
        )

        wantsPiPActive = false
        shouldHidePiPAfterShortcutStart = false
        cancelDelayedPiPHideCountdown(reason: "快捷方式关闭悬浮窗")
        updatePiPAutomaticStartPolicy()
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        cancelShortcutPiPStartRetry()
        isPiPActiveForUI = false

        guard !isPiPTransitioning else {
            deferShortcutPiPStopUntilTransitionFinishes(reason: "快捷方式关闭悬浮窗")
            AppDebugLogger.log("Shortcut stop deferred: PiP transitioning")
            return
        }

        guard pipController != nil, hadKnownPiPSession else {
            showMessage(L10n.text("悬浮窗未开启", "Floating window is not on."))
            return
        }

        AppDebugLogger.log("Shortcut stop PiP requested, active=\(pipController?.isPictureInPictureActive ?? false), own=\(isOwnPiPConfirmedActive), runtime=\(pipRuntimeStartedAt != nil)")
        cancelShortcutPiPStopRetry()
        stopPiPSmoothly()
    }

    private func deferShortcutPiPStopUntilTransitionFinishes(reason: String) {
        shouldStopPiPAfterCurrentTransition = true
        pendingShortcutPiPStopRetryRemaining = max(pendingShortcutPiPStopRetryRemaining, 8)
        scheduleShortcutPiPStopRetry(reason: reason)
    }

    private func scheduleShortcutPiPStopRetry(reason: String) {
        pendingShortcutPiPStopRetry?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performDeferredShortcutPiPStopIfNeeded(reason: reason)
        }
        pendingShortcutPiPStopRetry = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func performDeferredShortcutPiPStopIfNeeded(reason: String) {
        guard shouldStopPiPAfterCurrentTransition else { return }
        if isPiPTransitioning, pendingShortcutPiPStopRetryRemaining > 0 {
            pendingShortcutPiPStopRetryRemaining -= 1
            scheduleShortcutPiPStopRetry(reason: reason)
            return
        }

        shouldStopPiPAfterCurrentTransition = false
        pendingShortcutPiPStopRetryRemaining = 0
        pendingShortcutPiPStopRetry?.cancel()
        pendingShortcutPiPStopRetry = nil
        AppDebugLogger.log("Shortcut deferred stop fired: \(reason)")
        stopPiPFromShortcut()
    }

    private func cancelShortcutPiPStopRetry() {
        shouldStopPiPAfterCurrentTransition = false
        pendingShortcutPiPStopRetryRemaining = 0
        pendingShortcutPiPStopRetry?.cancel()
        pendingShortcutPiPStopRetry = nil
    }

    private func shortcutActionTitle(_ action: PiPShortcutAction) -> String {
        switch action {
        case .startFloatingWindow:
            return L10n.text("打开悬浮窗", "Open Floating Window")
        case .hideFloatingWindow:
            return L10n.text("隐藏悬浮窗", "Hide Floating Window")
        case .startAndHideFloatingWindow:
            return L10n.text("打开并隐藏悬浮窗", "Open and Hide")
        }
    }

    private func observeLooping(for playerItem: AVPlayerItem) {
        if let playerEndObserver = playerEndObserver {
            NotificationCenter.default.removeObserver(playerEndObserver)
        }
        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.restartPlaybackFromBeginning()
        }
    }

    private func observePlaybackHealth(for player: AVPlayer, item: AVPlayerItem) {
        guard shouldPrepareBackingPlayerForPlayback else { return }
        if shouldUsePlayerLayerPiPCompatibility {
            // Keep the PlayerLayer route close to the original app: one playing
            // video layer plus PiP, without KVO self-healing loops competing with
            // foreground apps.
            playerStallObserver.map(NotificationCenter.default.removeObserver)
            playerStallObserver = nil
            playerPauseObserver?.invalidate()
            playerPauseObserver = nil
            playerLayerTimeControlObserver?.invalidate()
            playerLayerTimeControlObserver = nil
            return
        }
        guard !shouldUsePlayerLayerPiPCompatibility else { return }

        if let playerStallObserver = playerStallObserver {
            NotificationCenter.default.removeObserver(playerStallObserver)
        }
        playerPauseObserver?.invalidate()

        playerStallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.keepPlaybackAlive()
        }

        playerPauseObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard
                let self,
                self.shouldKeepPiPPlaybackAlive,
                player.timeControlStatus == .paused
            else {
                return
            }
            DispatchQueue.main.async {
                self.keepPlaybackAlive()
            }
        }
    }

    private func observePlayerLayerPipelineHealth(for player: AVPlayer, item: AVPlayerItem) {
        if let playerStallObserver = playerStallObserver {
            NotificationCenter.default.removeObserver(playerStallObserver)
        }
        playerPauseObserver?.invalidate()
        playerPauseObserver = nil
        playerLayerTimeControlObserver?.invalidate()

        playerStallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.recoverPlayerLayerPipelineIfNeeded(reason: "PlayerLayer播放停滞")
        }

        playerLayerTimeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self, self.shouldUsePlayerLayerPiPCompatibility else { return }
            guard self.shouldKeepPiPPlaybackAlive else { return }
            guard player.timeControlStatus != .playing else { return }
            DispatchQueue.main.async {
                self.recoverPlayerLayerPipelineIfNeeded(reason: "PlayerLayer状态=\(player.timeControlStatus.rawValue)")
            }
        }
    }

    private func recoverPlayerLayerPipelineIfNeeded(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility, shouldKeepPiPPlaybackAlive else { return }
        guard let player = playerLayer?.player else { return }
        guard FrameRatePreference.isHighRefreshEnabled else {
            player.pause()
            stopPlayerLayerActivityDisplayLink(reason: "强制120关闭，跳过PlayerLayer自愈")
            resetPlayerLayerTransientStateForHighRefreshOff(reason: "强制120关闭，跳过PlayerLayer自愈")
            return
        }
        let now = CACurrentMediaTime()
        guard now - lastPlayerLayerPipelineRecoveryAt > 0.75 else { return }
        lastPlayerLayerPipelineRecoveryAt = now

        configureBackingPlayerForPiP(player)
        if player.currentItem?.status == .readyToPlay {
            player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] _ in
                guard let self, self.shouldUsePlayerLayerPiPCompatibility, self.shouldKeepPiPPlaybackAlive else { return }
                player?.play()
                self.scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer管线自愈：\(reason)")
                AppDebugLogger.log("PlayerLayer pipeline recovered: \(reason)")
            }
        } else {
            player.play()
            scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer管线自愈：\(reason)")
            AppDebugLogger.log("PlayerLayer pipeline recovered without ready item: \(reason)")
        }
    }

    private func restartPlaybackFromBeginning() {
        guard let player = playerLayer?.player else { return }
        if shouldUsePlayerLayerPiPCompatibility {
            guard FrameRatePreference.isHighRefreshEnabled else {
                player.pause()
                stopPlayerLayerActivityDisplayLink(reason: "强制120关闭，跳过PlayerLayer循环续播")
                resetPlayerLayerTransientStateForHighRefreshOff(reason: "强制120关闭，跳过PlayerLayer循环续播")
                return
            }
            player.seek(to: .zero) { [weak self, weak player] _ in
                guard let self, self.shouldKeepPiPPlaybackAlive else {
                    player?.pause()
                    return
                }
                player?.play()
                self.scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer视频循环续播")
            }
            return
        }
        // 单帧视频（duration ≈ 0.1s）播完后保持暂停，不循环
        // PiP 保活不需要 player 实际播放，只需 player 对象存在
        guard let item = player.currentItem, item.duration.seconds > 0.15 else {
            player.pause()  // 明确暂停，避免「播完-暂停-play()-播完」的每秒 10 次循环
            return
        }
        player.seek(to: .zero) { [weak self, weak player] _ in
            guard let self else { return }
            guard self.shouldKeepPiPPlaybackAlive else {
                player?.pause()
                return
            }
            self.updateBackingPlayerPlaybackForCurrentMode()
        }
    }

    private func keepPlaybackAlive() {
        guard shouldKeepPiPPlaybackAlive else {
            updateDisplaySleepDiagnostics(reason: "保活刷新未保活", shouldLog: true)
            return
        }
        UIApplication.shared.isIdleTimerDisabled = false
        if shouldUsePlayerLayerPiPCompatibility {
            BackgroundTaskManager.shared.forceStopAndDeactivate()
            PowerUsageLogger.markKeepAliveStop()
            KeepAliveLogger.heartbeat()
            if isPiPTransitioning && wantsPiPActive && !isOwnPiPConfirmedActive {
                primePlayerLayerPiPStartIfNeeded(reason: "PlayerLayer视频型PiP启动保活")
            } else {
                updateBackingPlayerPlaybackForCurrentMode()
                scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer视频型PiP保活")
            }
            updateDisplaySleepDiagnostics(reason: "PlayerLayer视频型PiP保活", shouldLog: true)
            AppDebugLogger.log(isPiPTransitioning && !isOwnPiPConfirmedActive ? "PlayerLayer PiP startup is primed with video pipeline" : "PlayerLayer PiP keeps video pipeline alive")
            return
        }
        if shouldUsePiPOnlyKeepAlive {
            BackgroundTaskManager.shared.forceStopAndDeactivate()
            PowerUsageLogger.markKeepAliveStop()
            KeepAliveLogger.heartbeat()
            releaseMediaAudioSessionForPiPOnly(reason: "低功耗保活")
            updateBackingPlayerPlaybackForCurrentMode()
            updateDisplaySleepDiagnostics(reason: "低功耗保活", shouldLog: true)
            AppDebugLogger.log(shouldPlayBackingPlayerForKeepAlive ? "PiP-only keepAlive uses backing player for playerLayer compatibility" : "PiP-only keepAlive without backing player")
            return
        } else {
            configurePiPAudioSession()
            PowerUsageLogger.markKeepAliveStart()
            BackgroundTaskManager.shared.startPlay()
            KeepAliveLogger.heartbeat()
        }
        updateBackingPlayerPlaybackForCurrentMode()
        updateDisplaySleepDiagnostics(reason: "音频强保活", shouldLog: true)
    }

    private func pauseBackingPlayerIfIdle() {
        guard !shouldKeepPiPPlaybackAlive else { return }
        playerLayer?.player?.pause()
    }

    private var shouldPlayBackingPlayerForKeepAlive: Bool {
        if shouldUsePlayerLayerPiPCompatibility {
            return (isOwnPiPConfirmedActive || isPiPTransitioning) && wantsPiPActive
        }
        return !shouldUsePiPOnlyKeepAlive || shouldPrepareBackingPlayerForPlayback
    }

    private func updateBackingPlayerPlaybackForCurrentMode() {
        guard let player = playerLayer?.player else { return }
        configureBackingPlayerForPiP(player)
        if shouldUsePlayerLayerPiPCompatibility {
            guard FrameRatePreference.isHighRefreshEnabled else {
                player.pause()
                stopPlayerLayerActivityDisplayLink(reason: "强制120关闭")
                resetPlayerLayerTransientStateForHighRefreshOff(reason: "强制120关闭")
                updateDisplaySleepDiagnostics()
                return
            }
            // 仿原作者路线：PlayerLayer 持续播放，并配合 30fps 默认 RunLoop 活性驱动。
            player.play()
            startPlayerLayerActivityDisplayLinkIfNeeded(reason: "PlayerLayer视频管线续播")
            scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer视频管线续播")
        } else if shouldPlayBackingPlayerForKeepAlive {
            player.play()
        } else {
            player.pause()
        }
        updateDisplaySleepDiagnostics()
    }

    private func configurePiPAudioSession() {
        do {
            if shouldUsePlayerLayerPiPCompatibility {
                configureTransientPlayerLayerPiPStartAudioSession(reason: "PlayerLayer PiP启动")
                return
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
        }
    }

    private func configureTransientPlayerLayerPiPStartAudioSession(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard shouldUsePlayerLayerPiPStartupAudioSession else {
            AppDebugLogger.log("PlayerLayer PiP startup audio session skipped to preserve system volume keys: \(reason)")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            let mode = playerLayerPiPStartAudioMode
            try session.setCategory(mode.category, mode: isReferenceIPAPureRoute ? .moviePlayback : .default, options: mode.options)
            if mode.shouldActivateSession {
                try session.setActive(true)
            }
            AppDebugLogger.log("PlayerLayer PiP transient \(mode.logName) audio session prepared: \(reason)")
        } catch {
            AppDebugLogger.log("PlayerLayer PiP transient audio prepare failed: \(reason), \(error.localizedDescription)")
        }
    }

    private func preparePlayerLayerVideoOnlyAudioState(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        pendingPlayerLayerAudioReleaseWorkItem?.cancel()
        pendingPlayerLayerAudioReleaseWorkItem = nil
        BackgroundTaskManager.shared.forceStopAndDeactivate()
        AppDebugLogger.log("PlayerLayer video-only audio state prepared: \(reason)")
    }

    private func primePlayerLayerPiPStartIfNeeded(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard !hasPrimedPlayerLayerPiPStart else { return }
        hasPrimedPlayerLayerPiPStart = true
        pendingPlayerLayerAudioReleaseWorkItem?.cancel()
        pendingPlayerLayerAudioReleaseWorkItem = nil
        BackgroundTaskManager.shared.forceStopAndDeactivate()
        configureTransientPlayerLayerPiPStartAudioSession(reason: reason)

        guard let player = playerLayer?.player else {
            AppDebugLogger.log("PlayerLayer PiP prime skipped: player nil, reason=\(reason)")
            return
        }
        configureBackingPlayerForPiP(player)
        player.isMuted = true
        player.volume = 0
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] _ in
            guard
                let self,
                self.shouldUsePlayerLayerPiPCompatibility,
                self.isPiPTransitioning,
                self.wantsPiPActive,
                !self.isOwnPiPConfirmedActive
            else {
                player?.pause()
                return
            }
            // 仿原作者：启动阶段就让 PlayerLayer 视频管线跑起来，避免额外空 DisplayLink。
            player?.play()
            self.updateDisplaySleepDiagnostics(reason: "PlayerLayer PiP启动预热", shouldLog: true)
            AppDebugLogger.log("PlayerLayer PiP primed video pipeline: \(reason)")
        }
    }

    private func activatePlayerLayerPiPStartAudioIfNeeded(attempt: Int) -> Bool {
        guard shouldUsePlayerLayerPiPCompatibility else { return false }
        guard shouldUsePlayerLayerPiPStartupAudioSession else {
            if attempt == playerLayerActivePlaybackFallbackAttempt {
                AppDebugLogger.log("PlayerLayer PiP playback fallback suppressed to preserve system volume keys: attempt=\(attempt)")
            }
            return false
        }
        guard playerLayerPiPStartAudioMode != .playbackActive else { return false }
        guard attempt >= playerLayerActivePlaybackFallbackAttempt else { return false }
        // 从 ambient 升级到 playback category-only，不 setActive，不劫持音量键
        playerLayerPiPStartAudioMode = .playbackCategoryOnly
        hasPrimedPlayerLayerPiPStart = false
        AppDebugLogger.log("PlayerLayer PiP fallback to active playback audio session after \(PlayerLayerPiPStartAudioMode.defaultStartupMode.logName) attempts: attempt=\(attempt)")
        primePlayerLayerPiPStartIfNeeded(reason: "PlayerLayer PiP启动兜底")
        return true
    }

    private func deactivatePiPAudioSessionIfPossible() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppDebugLogger.log("Deactivate audio session skipped: \(error.localizedDescription)")
        }
    }

    private func releaseMediaAudioSessionForPiPOnly(reason: String) {
        guard shouldUsePiPOnlyKeepAlive else { return }
        guard !shouldUsePlayerLayerPiPCompatibility else {
            AppDebugLogger.log("PiP-only audio release skipped for PlayerLayer route: \(reason)")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.soloAmbient, mode: .default)
            AppDebugLogger.log("PiP-only released media audio session: \(reason)")
        } catch {
            AppDebugLogger.log("PiP-only audio release skipped: \(reason), \(error.localizedDescription)")
        }
    }

    private func releaseTransientPlayerLayerPiPAudioSession(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        pendingPlayerLayerAudioReleaseWorkItem?.cancel()
        pendingPlayerLayerAudioReleaseWorkItem = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.soloAmbient, mode: .default)
            AppDebugLogger.log("PlayerLayer PiP released transient audio session: \(reason)")
        } catch {
            AppDebugLogger.log("PlayerLayer PiP audio release skipped: \(reason), \(error.localizedDescription)")
        }
    }

    private func scheduleTransientPlayerLayerPiPAudioRelease(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard shouldSettlePlayerLayerAudioAfterStart else {
            keepTransientPlayerLayerPiPAudioSession(reason: reason)
            return
        }
        guard pipController?.isPictureInPictureActive == true, !isPiPTransitioning, wantsPiPActive else { return }
        pendingPlayerLayerAudioReleaseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard
                let self,
                self.shouldUsePlayerLayerPiPCompatibility,
                self.shouldSettlePlayerLayerAudioAfterStart,
                self.pipController?.isPictureInPictureActive == true,
                !self.isPiPTransitioning,
                self.wantsPiPActive
            else {
                return
            }
            self.settleTransientPlayerLayerPiPAudioSession(reason: reason)
            self.updateDisplaySleepDiagnostics(reason: "PlayerLayer延迟切换音频类别", shouldLog: true)
        }
        pendingPlayerLayerAudioReleaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + playerLayerAudioReleaseDelay, execute: workItem)
        AppDebugLogger.log("PlayerLayer PiP scheduled transient audio settle: \(reason), delay=\(String(format: "%.1f", playerLayerAudioReleaseDelay))s")
    }

    private var shouldSettlePlayerLayerAudioAfterStart: Bool {
        // PiP 启动成功后只做 setActive(false)，不改 category
        // 目标：音量键归还给系统（Ringtone），同时 PiP 仍存活
        true
    }

    private var shouldUsePlayerLayerPiPStartupAudioSession: Bool {
        // PlayerLayer PiP 需要 .playback 才能让 pipPossible=true
        true
    }

    private func keepTransientPlayerLayerPiPAudioSession(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        pendingPlayerLayerAudioReleaseWorkItem?.cancel()
        pendingPlayerLayerAudioReleaseWorkItem = nil
        AppDebugLogger.log("PlayerLayer PiP keeps \(playerLayerPiPStartAudioMode.logName) audio session to avoid auto stop: \(reason)")
    }

    private func settleTransientPlayerLayerPiPAudioSession(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        pendingPlayerLayerAudioReleaseWorkItem?.cancel()
        pendingPlayerLayerAudioReleaseWorkItem = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            AppDebugLogger.log("PlayerLayer PiP deactivated audio session (kept category): \(reason)")
        } catch {
            AppDebugLogger.log("PlayerLayer PiP audio deactivation skipped: \(reason), \(error.localizedDescription)")
        }
    }

    private func resetPlayerLayerTransientStateForHighRefreshOff(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        pendingPlayerLayerAudioReleaseWorkItem?.cancel()
        pendingPlayerLayerAudioReleaseWorkItem = nil
        hasPrimedPlayerLayerPiPStart = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            AppDebugLogger.log("PlayerLayer transient state reset for high refresh off: \(reason)")
        } catch {
            AppDebugLogger.log("PlayerLayer high refresh off audio deactivate skipped: \(reason), \(error.localizedDescription)")
        }
    }

    private func settlePlayerLayerPiPAfterStart() {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard let player = playerLayer?.player else {
            preparePlayerLayerVideoOnlyAudioState(reason: "PiP启动完成但播放器不存在")
            return
        }
        guard FrameRatePreference.isHighRefreshEnabled else {
            player.pause()
            stopPlayerLayerActivityDisplayLink(reason: "PiP启动完成但强制120关闭")
            resetPlayerLayerTransientStateForHighRefreshOff(reason: "PiP启动完成但强制120关闭")
            updateDisplaySleepDiagnostics(reason: "PlayerLayer PiP启动后强制120关闭", shouldLog: true)
            return
        }
        player.play()
        scheduleTransientPlayerLayerPiPAudioRelease(reason: "PiP启动完成")
        updateDisplaySleepDiagnostics(reason: "PlayerLayer PiP启动后保持视频管线", shouldLog: true)
    }

    private var shouldKeepPiPPlaybackAlive: Bool {
        wantsPiPActive && (isOwnPiPConfirmedActive || isPiPTransitioning)
    }

    private var shouldUsePiPOnlyKeepAlive: Bool {
        if UserDefaults.standard.object(forKey: Self.userDefaultsIOS26AudioKeepAliveKey) == nil {
            if let legacyPiPOnly = UserDefaults.standard.object(forKey: Self.userDefaultsIOS26PiPOnlyKeepAliveKey) as? Bool {
                UserDefaults.standard.set(!legacyPiPOnly, forKey: Self.userDefaultsIOS26AudioKeepAliveKey)
            } else {
                UserDefaults.standard.set(true, forKey: Self.userDefaultsIOS26AudioKeepAliveKey)
            }
        }
        return !UserDefaults.standard.bool(forKey: Self.userDefaultsIOS26AudioKeepAliveKey)
    }

    private func updatePiPAutomaticStartPolicy() {
        if #available(iOS 14.2, *) {
            pipController?.canStartPictureInPictureAutomaticallyFromInline = wantsPiPActive
        }
    }

    private func beginPiPTransition(expectedActive: Bool, reason: String) {
        didRecoverStalePiPStop = false
        if shouldUsePlayerLayerPiPCompatibility, expectedActive {
            hasPrimedPlayerLayerPiPStart = false
            playerLayerPiPStartAudioMode = .defaultStartupMode
        }
        isPiPTransitioning = true
        pipTransitionStartedAt = Date()
        pipTransitionReason = reason
        pipTransitionExpectedActive = expectedActive
        schedulePiPTransitionWatchdog(reason: reason)
    }

    private func finishPiPTransition() {
        pipTransitionWatchdogWorkItem?.cancel()
        pipTransitionWatchdogWorkItem = nil
        pipTransitionStartedAt = nil
        pipTransitionReason = "未知"
        pipTransitionExpectedActive = nil
        isPiPTransitioning = false
    }

    private func schedulePiPTransitionWatchdog(reason: String) {
        pipTransitionWatchdogWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.recoverStalePiPTransition(reason: "watchdog: \(reason)")
        }
        pipTransitionWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + piPTransitionWatchdogDelay, execute: workItem)
    }

    private var piPTransitionWatchdogDelay: TimeInterval {
        pipTransitionExpectedActive == false ? 6.0 : 4.0
    }

    private var piPStopTransitionGraceDelay: TimeInterval {
        1.5
    }

    private func recoverStalePiPTransition(reason: String) {
        guard isPiPTransitioning else { return }

        let active = pipController?.isPictureInPictureActive ?? false
        let elapsed = pipTransitionStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let expectedText = pipTransitionExpectedActive.map(String.init(describing:)) ?? "nil"
        AppDebugLogger.log(
            "PiP transition watchdog recovered: reason=\(reason), startedReason=\(pipTransitionReason), elapsed=\(String(format: "%.1f", elapsed))s, active=\(active), wants=\(wantsPiPActive), ui=\(isPiPActiveForUI), stopping=\(isStoppingPiP), expectedActive=\(expectedText)"
        )

        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        pipTransitionWatchdogWorkItem?.cancel()
        pendingPlayerLayerAudioReleaseWorkItem?.cancel()
        pendingPlayerLayerAudioReleaseWorkItem = nil
        pendingPiPStartWorkItem = nil
        pipStartTimeoutWorkItem = nil
        hasPrimedPlayerLayerPiPStart = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        let recoveredExpectedStop = pipTransitionExpectedActive == false
        finishPiPTransition()
        isStoppingPiP = false
        didRetryLegacyPiPStart = false
        didRecoverStalePiPStop = recoveredExpectedStop

        if active {
            wantsPiPActive = true
            isOwnPiPConfirmedActive = true
            isPiPActiveForUI = true
            updatePiPAutomaticStartPolicy()
            prepareCustomViewForPiPStart()
            configureRunningText()
            showPiPContentForOpening()
            if pipRuntimeStartedAt == nil {
                beginPiPRuntimeSession()
            }
            if isScrollingEnabled, !shouldRenderClockMode {
                startDisplayLinks()
            }
            keepPlaybackAlive()
            KeepAliveLogger.heartbeat()
        } else {
            releaseTransientPlayerLayerPiPAudioSession(reason: "PiP过渡状态恢复未启动")
            handleOwnPiPInvalidated(reason: "PiP过渡状态恢复：\(reason)")
        }

        updateDiagnosticsPiPState()
        updateDisplaySleepDiagnostics(reason: "PiP过渡状态恢复", shouldLog: true)
        updateHomeView()
    }

    @discardableResult
    private func recoverStalePiPTransitionIfNeeded(reason: String) -> Bool {
        if recoverStalePiPStopTransitionIfNeeded(reason: reason) {
            return true
        }
        guard isPiPTransitioning, let pipTransitionStartedAt else { return false }
        guard Date().timeIntervalSince(pipTransitionStartedAt) >= piPTransitionWatchdogDelay else { return false }
        recoverStalePiPTransition(reason: reason)
        return true
    }

    @discardableResult
    private func recoverStalePiPStopTransitionIfNeeded(reason: String) -> Bool {
        guard isPiPTransitioning, !wantsPiPActive else { return false }
        guard let pipTransitionStartedAt else {
            recoverStalePiPTransition(reason: "\(reason)：停止转场缺少开始时间")
            return true
        }
        guard Date().timeIntervalSince(pipTransitionStartedAt) >= piPStopTransitionGraceDelay else { return false }
        recoverStalePiPTransition(reason: "\(reason)：停止转场超时")
        return true
    }

    private var shouldPreviewPiPHeightLive: Bool {
        (isOwnPiPConfirmedActive || isPiPTransitioning) && !isPiPSuspendedAtSide
    }

    private var shouldRunPiPContentUpdates: Bool {
        guard !isExtremeSilentModeEnabled else { return false }
        return (isOwnPiPConfirmedActive || isPiPTransitioning) && !isPiPSuspendedAtSide && !isPiPVisuallyHidden
    }

    private var shouldRunLowCostPiPContentUpdates: Bool {
        (isOwnPiPConfirmedActive || isPiPTransitioning) && !isPiPSuspendedAtSide && !isPiPVisuallyHidden
    }

    private func updateAutoHiddenOverheadState(reason: String) {
        guard !shouldUsePlayerLayerPiPCompatibility else { return }
        guard isOwnPiPConfirmedActive || isPiPTransitioning else { return }
        if isPiPVisuallyHidden {
            pauseAutoHiddenOverheadIfNeeded(reason: reason)
        } else {
            resumeAutoHiddenOverheadIfNeeded(reason: reason)
        }
    }

    private func pauseAutoHiddenOverheadIfNeeded(reason: String) {
        guard !isAutoHiddenOverheadPaused else { return }
        isAutoHiddenOverheadPaused = true
        stopDisplayLinks()
        stopClockTimer()
        textView?.isHidden = true
        textView?.alpha = 0
        textView?.layer.opacity = 0
        clockLabel?.isHidden = true
        clockLabel?.alpha = 0
        clockLabel?.layer.opacity = 0
        clockOverlayView?.isHidden = true
        clockOverlayView?.alpha = 0
        clockOverlayView?.layer.opacity = 0
        AppDebugLogger.log("PiP 0.1pt hidden mode paused extra overhead: \(reason)")
    }

    private func resumeAutoHiddenOverheadIfNeeded(reason: String) {
        guard isAutoHiddenOverheadPaused else { return }
        isAutoHiddenOverheadPaused = false
        configureRunningText()
        if shouldRenderClockMode {
            startClockTimerIfNeeded()
        } else if isScrollingEnabled, !isContentExtremeModeEnabled {
            startDisplayLinks()
        }
        AppDebugLogger.log("PiP hidden mode resumed content overhead: \(reason)")
    }

    private func handleOwnPiPInvalidated(reason: String) {
        let hadOwnSession = isOwnPiPConfirmedActive || pipRuntimeStartedAt != nil
        let shouldNotifyStopped = hadOwnSession
            && !isStoppingPiP
            && !isClosingPiPFromCustomContentTap
            && !KeepAliveNotificationTester.shouldSuppressPiPStoppedNotification(reason: reason)
        let stoppedMode = shouldUsePiPOnlyKeepAlive ? "PiP保活-低功耗" : "音频强保活"
        pipExpectedActiveBeforeStop = nil
        resumeAutoHiddenOverheadIfNeeded(reason: "PiP失效")
        cancelDelayedPiPHideCountdown(reason: "悬浮窗失效")
        wantsPiPActive = false
        isOwnPiPConfirmedActive = false
        isPiPActiveForUI = false
        isStoppingPiP = false
        didRetryLegacyPiPStart = false
        didRecoverStalePiPStop = false
        hasPrimedPlayerLayerPiPStart = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        updatePiPAutomaticStartPolicy()
        detachLegacyCustomViewIfNeeded()
        stopDisplayLinks()
        stopClockTimer()
        stopPlayerLayerActivityDisplayLink(reason: reason)
        BackgroundTaskManager.shared.stopPlay()
        releaseTransientPlayerLayerPiPAudioSession(reason: reason)
        PowerUsageLogger.markKeepAliveStop()
        pauseBackingPlayerIfIdle()
        endBackgroundTask()
        if pipRuntimeStartedAt != nil || pipRuntimeDuration > 0 {
            finishPiPRuntimeSession()
        }
        if hadOwnSession {
            KeepAliveLogger.markPiPStopped(reason: reason)
        }
        if shouldNotifyStopped {
            KeepAliveNotificationTester.schedulePiPStoppedNotification(mode: stoppedMode, reason: reason)
        }
        AppDebugLogger.log("Own PiP invalidated: \(reason)")
    }

    private func validateOwnPiPState(reason: String) {
        guard isOwnPiPConfirmedActive, pipController?.isPictureInPictureActive != true else { return }
        handleOwnPiPInvalidated(reason: "\(reason)：本App悬浮窗已失效，可能被其他PiP挤掉")
        updateDiagnosticsPiPState()
        updateHomeView()
    }

    private var isPlayerReadyForPiP: Bool {
        guard requiresPlayerLayerForPiP else {
            return true
        }
        guard
            let player = playerLayer?.player,
            let item = player.currentItem,
            item.status == .readyToPlay
        else {
            return false
        }
        return player.status != .failed
    }

    private var requiresPlayerLayerForPiP: Bool {
        if shouldUsePlayerLayerPiPCompatibility {
            return true
        }
        if #available(iOS 15.0, *) {
            return false
        }
        return true
    }

    private var shouldPrepareBackingPlayerForPlayback: Bool {
        // BETA4_ANCHOR_BILIBILI_DANMAKU_FIX:
        // 回归 beta3：iOS 15+ VideoCall contentSource 不额外准备 PlayerLayer backing player。
        return requiresPlayerLayerForPiP
    }

    private func makePlayerItem() -> AVPlayerItem? {
        if shouldUsePlayerLayerPiPCompatibility {
            switch pipEngineRoute {
            case .playerLayerGenerated:
                return makeGeneratedPlayerLayerLongVideoItem()
            case .referenceIPA, .referenceIPAPure:
                AppDebugLogger.log("Reference experiment route normalized to beta5 generated PlayerLayer item")
                return makeGeneratedPlayerLayerLongVideoItem()
            case .videoCall:
                break
            }
        }

        let videoScale = max(UIScreen.main.scale, 1)
        let backingVideoSize = CGSize(
            width: evenVideoDimension(max(currentPiPSize.width * videoScale, 2)),
            height: evenVideoDimension(max(currentPiPSize.height * videoScale, 2))
        )
        let videoText = shouldRenderClockMode ? "" : L10n.text("悬浮窗运行中", "Floating window running")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pip-static-h264-clear-v3-\(Int(backingVideoSize.width))x\(Int(backingVideoSize.height))-\(videoText.isEmpty ? "blank" : "text").mov")
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try PlaceholderVideoFactory.makeBackingVideo(
                    at: url,
                    size: backingVideoSize,
                    text: videoText
                )
            } catch {
                print(error)
                AppDebugLogger.log("Placeholder video failed: \(error.localizedDescription)")
                return nil
            }
        }
        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        return item
    }

    private func makeGeneratedPlayerLayerLongVideoItem() -> AVPlayerItem? {
        let videoScale = max(UIScreen.main.scale, 1)
        let backingVideoSize = CGSize(
            width: evenVideoDimension(max(currentPiPSize.width * videoScale, 2)),
            height: evenVideoDimension(max(currentPiPSize.height * videoScale, 2))
        )
        let videoText = L10n.text("悬浮窗运行中", "Floating window running")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pip-playerlayer-long-h264-v1-\(Int(backingVideoSize.width))x\(Int(backingVideoSize.height))-\(videoText.isEmpty ? "blank" : "text").mov")

        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try PlaceholderVideoFactory.makeLongBackingVideo(
                    at: url,
                    size: backingVideoSize,
                    text: videoText
                )
            } catch {
                AppDebugLogger.log("PlayerLayer long video failed: \(error.localizedDescription)")
                return nil
            }
        }

        return AVPlayerItem(asset: AVAsset(url: url))
    }

    private func makePlayerLayerReferencePlayerItem() -> AVPlayerItem? {
        if let item = makeReferenceIPAPresetPlayerItem() {
            return item
        }
        if let item = makePlayerLayerStatusVideoItem() {
            return item
        }
        if let fallbackURL = playerLayerReferenceVideoURL() {
            AppDebugLogger.log("PlayerLayer reference preset missing; using static bundled fallback")
            return AVPlayerItem(asset: AVAsset(url: fallbackURL))
        }
        return nil
    }

    private func makePlayerLayerStatusVideoItem() -> AVPlayerItem? {
        let videoScale = max(UIScreen.main.scale, 1)
        let backingVideoSize = CGSize(
            width: evenVideoDimension(max(currentPiPSize.width * videoScale, 2)),
            height: evenVideoDimensionFloor(max(currentPiPSize.height * videoScale, 2))
        )
        let statusText = L10n.text("悬浮窗运行中", "Floating window running")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pip-playerlayer-status-v2-\(Int(backingVideoSize.width))x\(Int(backingVideoSize.height)).mov")

        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try PlaceholderVideoFactory.makeBackingVideo(
                    at: url,
                    size: backingVideoSize,
                    text: statusText
                )
            } catch {
                AppDebugLogger.log("PlayerLayer status video failed: \(error.localizedDescription)")
                return nil
            }
        }

        let sourceAsset = AVAsset(url: url)
        guard let timelineAsset = makeReferenceIPATimelineAsset(from: sourceAsset) else {
            AppDebugLogger.log("PlayerLayer status video uses direct asset, size=\(formatSize(currentPiPSize))")
            return AVPlayerItem(asset: sourceAsset)
        }

        let item = AVPlayerItem(asset: timelineAsset)
        let videoComposition = AVMutableVideoComposition(propertiesOf: timelineAsset)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        item.videoComposition = videoComposition
        item.preferredForwardBufferDuration = 0
        AppDebugLogger.log("PlayerLayer status video material, target=\(formatSize(currentPiPSize))pt, pixels=\(formatSize(backingVideoSize))px, scale=\(formatNumber(videoScale)), duration=\(String(format: "%.1f", referenceIPATimelineDuration.seconds))s")
        return item
    }

    private func makeReferenceIPAPresetPlayerItem() -> AVPlayerItem? {
        guard let preset = referenceIPAPreset(for: currentPiPSize),
              let url = Bundle.main.url(forResource: preset.resourceName, withExtension: "mov") else {
            AppDebugLogger.log("Reference IPA route missing preset for size=\(formatSize(currentPiPSize)); fallback generated video")
            return nil
        }

        let sourceAsset = AVAsset(url: url)
        guard let timelineAsset = makeReferenceIPATimelineAsset(from: sourceAsset) else {
            AppDebugLogger.log("Reference IPA route uses direct asset: \(preset.resourceName)")
            return AVPlayerItem(asset: sourceAsset)
        }

        let item = AVPlayerItem(asset: timelineAsset)
        let videoComposition = AVMutableVideoComposition(propertiesOf: timelineAsset)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        item.videoComposition = videoComposition
        item.audioMix = mutedAudioMix(for: timelineAsset)
        item.preferredForwardBufferDuration = 0
        AppDebugLogger.log("Reference IPA route uses \(preset.resourceName), target=\(formatSize(currentPiPSize)), duration=\(String(format: "%.1f", referenceIPATimelineDuration.seconds))s")
        return item
    }

    private func makeReferenceIPAPurePlayerItem() -> AVPlayerItem? {
        guard let preset = referenceIPAPreset(for: currentPiPSize),
              let url = Bundle.main.url(forResource: preset.resourceName, withExtension: "mov") else {
            AppDebugLogger.log("Reference pure route missing preset for size=\(formatSize(currentPiPSize))")
            return nil
        }

        let sourceAsset = AVAsset(url: url)
        guard let timelineAsset = makeReferenceIPATimelineAsset(from: sourceAsset) else {
            AppDebugLogger.log("Reference pure route failed to build repeated timeline: \(preset.resourceName)")
            return nil
        }
        let item = AVPlayerItem(asset: timelineAsset)
        if let videoComposition = makeReferenceStyleTimeVideoComposition(
            asset: timelineAsset,
            renderSize: referenceRenderSize(for: timelineAsset),
            duration: referenceIPATimelineDuration
        ) {
            item.videoComposition = videoComposition
        }
        item.preferredForwardBufferDuration = 0
        AppDebugLogger.log("Reference pure route uses repeated \(preset.resourceName), target=\(formatSize(currentPiPSize)), render=\(formatSize(referenceRenderSize(for: timelineAsset))), duration=\(String(format: "%.1f", referenceIPATimelineDuration.seconds))s")
        return item
    }

    private func referenceIPAPreset(for size: CGSize) -> ReferenceIPAVideoPreset? {
        guard !referenceIPAVideoPresets.isEmpty else { return nil }
        let targetAspectRatio = max(size.width, 1) / max(size.height, 1)
        return referenceIPAVideoPresets.min { lhs, rhs in
            abs(log(Double(lhs.aspectRatio / targetAspectRatio))) < abs(log(Double(rhs.aspectRatio / targetAspectRatio)))
        }
    }

    private func makeReferenceIPATimelineAsset(from sourceAsset: AVAsset) -> AVMutableComposition? {
        guard let sourceTrack = sourceAsset.tracks(withMediaType: .video).first else { return nil }
        let sourceDuration = sourceAsset.duration.seconds > 0
            ? sourceAsset.duration
            : CMTime(value: 1, timescale: 10)
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return nil
        }

        do {
            var insertionTime = CMTime.zero
            while CMTimeCompare(insertionTime, referenceIPATimelineDuration) < 0 {
                let remaining = CMTimeSubtract(referenceIPATimelineDuration, insertionTime)
                let insertDuration = CMTimeMinimum(sourceDuration, remaining)
                try compositionTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: insertDuration),
                    of: sourceTrack,
                    at: insertionTime
                )
                insertionTime = CMTimeAdd(insertionTime, insertDuration)
            }
            compositionTrack.preferredTransform = sourceTrack.preferredTransform
            return composition
        } catch {
            AppDebugLogger.log("Reference IPA timeline failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func mutedAudioMix(for asset: AVAsset) -> AVAudioMix? {
        let parameters = asset.tracks(withMediaType: .audio).map { track -> AVMutableAudioMixInputParameters in
            let inputParameters = AVMutableAudioMixInputParameters(track: track)
            inputParameters.setVolume(0, at: .zero)
            return inputParameters
        }
        guard !parameters.isEmpty else { return nil }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        return audioMix
    }

    private func playerLayerReferenceVideoURL() -> URL? {
        Bundle.main.url(forResource: "pip_reference_10_1", withExtension: "mov")
            ?? Bundle.main.url(forResource: "playerlayer_video_noaudio", withExtension: "mp4")
            ?? Bundle.main.url(forResource: "竖向视频", withExtension: "mp4")
    }

    private func referenceRenderSize(for asset: AVAsset) -> CGSize {
        guard let track = asset.tracks(withMediaType: .video).first else {
            let scale = max(UIScreen.main.scale, 1)
            return CGSize(
                width: evenVideoDimension(max(currentPiPSize.width * scale, 2)),
                height: evenVideoDimension(max(currentPiPSize.height * scale, 2))
            )
        }
        let transformedSize = track.naturalSize.applying(track.preferredTransform)
        return CGSize(
            width: evenVideoDimension(max(abs(transformedSize.width), 2)),
            height: evenVideoDimension(max(abs(transformedSize.height), 2))
        )
    }


    private func makeReferenceStyleTimeVideoComposition(
        asset: AVAsset,
        renderSize: CGSize,
        duration: CMTime? = nil
    ) -> AVVideoComposition? {
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let instruction = ReferenceStyleTimeVideoCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: duration ?? asset.duration),
            sourceTrackID: track.trackID
        )
        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = ReferenceStyleTimeVideoComposition.self
        composition.instructions = [instruction]
        composition.renderSize = renderSize
        let targetFPS = max(60, UIScreen.main.maximumFramesPerSecond)
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        return composition
    }

    private func evenVideoDimension(_ value: CGFloat) -> CGFloat {
        max(2, ceil(value / 2) * 2)
    }

    private func evenVideoDimensionFloor(_ value: CGFloat) -> CGFloat {
        max(2, floor(value / 2) * 2)
    }

    private func beginBackgroundTaskIfNeeded() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PiPKeepAlive") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func startDisplayLinks() {
        guard !shouldUsePlayerLayerPiPCompatibility || shouldAttachCustomViewInPlayerLayerPiP else { return }
        guard !isContentExtremeModeEnabled else {
            stopDisplayLinks()
            return
        }
        guard UIApplication.shared.applicationState == .active else { return }
        guard isScrollingEnabled, !shouldRenderClockMode, shouldRunPiPContentUpdates else { return }
        guard scrollDisplayLink == nil else { return }

        let scrollDisplayLink = CADisplayLink(target: self, selector: #selector(updateScrollingText(_:)))
        scrollDisplayLink.add(to: .main, forMode: .default)
        lastScrollTimestamp = nil
        self.scrollDisplayLink = scrollDisplayLink
        AppDebugLogger.log("PiP scrolling displayLink started")
    }

    private func stopDisplayLinks() {
        let hadDisplayLink = scrollDisplayLink != nil
        scrollDisplayLink?.invalidate()
        scrollDisplayLink = nil
        lastScrollTimestamp = nil
        if hadDisplayLink {
            AppDebugLogger.log("PiP scrolling displayLink stopped")
        }
    }

    private func startPlayerLayerActivityDisplayLinkIfNeeded(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard FrameRatePreference.isHighRefreshEnabled else {
            stopPlayerLayerActivityDisplayLink(reason: "强制120关闭")
            return
        }
        guard pipController?.isPictureInPictureActive == true || isPiPTransitioning else { return }
        guard playerLayerActivityDisplayLink == nil else { return }

        let displayLink = CADisplayLink(target: self, selector: #selector(stepPlayerLayerActivityDriver(_:)))
        displayLink.preferredFramesPerSecond = 30
        displayLink.add(to: .main, forMode: .default)
        playerLayerActivityDisplayLink = displayLink
        lastPlayerLayerActivityNudgeAt = 0
        AppDebugLogger.log("PlayerLayer original-style activity displayLink started: \(reason)")
    }

    private func stopPlayerLayerActivityDisplayLink(reason: String) {
        let hadDisplayLink = playerLayerActivityDisplayLink != nil
        playerLayerActivityDisplayLink?.invalidate()
        playerLayerActivityDisplayLink = nil
        lastPlayerLayerActivityNudgeAt = 0
        if hadDisplayLink {
            AppDebugLogger.log("PlayerLayer original-style activity displayLink stopped: \(reason)")
        }
    }

    @objc private func stepPlayerLayerActivityDriver(_ displayLink: CADisplayLink) {
        guard shouldUsePlayerLayerPiPCompatibility,
              FrameRatePreference.isHighRefreshEnabled,
              pipController?.isPictureInPictureActive == true,
              wantsPiPActive
        else {
            stopPlayerLayerActivityDisplayLink(reason: "状态变化")
            return
        }

        guard displayLink.timestamp - lastPlayerLayerActivityNudgeAt >= 1.0 else { return }
        lastPlayerLayerActivityNudgeAt = displayLink.timestamp
        guard let player = playerLayer?.player else { return }
        if player.timeControlStatus != .playing {
            player.play()
            scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer原作者式活性驱动恢复播放")
        }
    }

    private func startClockTimerIfNeeded() {
        guard !shouldUsePlayerLayerPiPCompatibility || shouldAttachCustomViewInPlayerLayerPiP else { return }
        let shouldRun = isContentExtremeModeEnabled ? shouldRunLowCostPiPContentUpdates : shouldRunPiPContentUpdates
        guard isClockModeEnabled, shouldRun else {
            stopClockTimer()
            return
        }
        stopClockTimer()
        resetClockMetrics(preservingNetworkText: true)
        updateClockOverlay(timestamp: CACurrentMediaTime(), forceNetworkSample: !isContentExtremeModeEnabled)
        if isContentExtremeModeEnabled {
            let timer = Timer(timeInterval: 1.0, target: self, selector: #selector(updateClockLabel), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .default)
            clockRenderTimer = timer
            AppDebugLogger.log("PiP clock low-cost timer started, suspended=\(isPiPSuspendedAtSide), appState=\(UIApplication.shared.applicationState.rawValue)")
            return
        }
        let displayLink = CADisplayLink(target: self, selector: #selector(updateClockDisplay(_:)))
        configureForClockRefreshRate(displayLink)
        // Keep the clock/FPS overlay alive while the app is scrolling; .default pauses in tracking mode.
        displayLink.add(to: .main, forMode: .common)
        clockDisplayLink = displayLink
        AppDebugLogger.log("PiP clock displayLink started, suspended=\(isPiPSuspendedAtSide), appState=\(UIApplication.shared.applicationState.rawValue)")
    }

    private func stopClockTimer() {
        let hadClockTimer = clockDisplayLink != nil || fpsProbeDisplayLink != nil || clockRenderTimer != nil
        clockDisplayLink?.invalidate()
        clockDisplayLink = nil
        fpsProbeDisplayLink?.invalidate()
        fpsProbeDisplayLink = nil
        clockRenderTimer?.invalidate()
        clockRenderTimer = nil
        lastClockTimestamp = nil
        lastClockNetworkTimestamp = nil
        clockFrameCount = 0
        pendingMeasuredPiPFPS = nil
        pendingMeasuredPiPFPSCount = 0
        pendingMeasuredPiPFPSStartedAt = nil
        lastClockOverlayTimeText = ""
        lastClockOverlayFPSText = ""
        lastClockOverlayNetworkText = ""
        lastClockRenderTick = -1
        lastBackgroundClockDiagnosticsTimestamp = nil
        if hadClockTimer {
            AppDebugLogger.log("PiP clock timers stopped")
        }
    }

	    private func resetClockMetrics(preservingNetworkText: Bool = false) {
        let preservedNetworkText = currentNetworkSpeedText
	        lastClockTimestamp = nil
	        lastClockNetworkTimestamp = nil
	        clockFrameCount = 0
        pendingMeasuredPiPFPS = nil
        pendingMeasuredPiPFPSCount = 0
	        pendingMeasuredPiPFPSStartedAt = nil
	        measuredPiPFPS = 0
	        lastNetworkSample = nil
	        currentNetworkSpeedText = preservingNetworkText ? preservedNetworkText : "↑0B ↓0B"
        lastClockOverlayTimeText = ""
        lastClockOverlayFPSText = ""
        lastClockOverlayNetworkText = ""
        lastClockRenderTick = -1
        lastBackgroundClockDiagnosticsTimestamp = nil
    }

    @objc private func updateScrollingText(_ displayLink: CADisplayLink) {
        guard !isContentExtremeModeEnabled, let textView, isScrollingEnabled, !shouldRenderClockMode, shouldRunPiPContentUpdates else {
            stopDisplayLinks()
            return
        }
        lastScrollTimestamp = displayLink.timestamp

        let offsetY = textView.contentOffset.y
        textView.contentOffset = CGPoint(x: 0, y: offsetY + 1)
        if textView.contentOffset.y > textView.contentSize.height {
            textView.contentOffset = .zero
        }
    }

    private func configureForClockRefreshRate(_ displayLink: CADisplayLink) {
        let maximumFramesPerSecond = UIScreen.main.maximumFramesPerSecond
        let targetFramesPerSecond = max(60, maximumFramesPerSecond)

        if #available(iOS 15.0, *) {
            let target = Float(targetFramesPerSecond)
            // 开启时强拉到 target；关闭时释放 minimum，让系统自适应，避免继续全局解锁 120。
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: FrameRatePreference.isHighRefreshEnabled ? target : 30,
                maximum: target,
                preferred: FrameRatePreference.preferredFrameRateValue(target: target)
            )
        } else {
            displayLink.preferredFramesPerSecond = targetFramesPerSecond
        }
    }

    @objc private func handleFrameRatePreferenceDidChange() {
        if let clockDisplayLink {
            configureForClockRefreshRate(clockDisplayLink)
            pendingMeasuredPiPFPS = nil
            pendingMeasuredPiPFPSCount = 0
            pendingMeasuredPiPFPSStartedAt = nil
            lastClockOverlayFPSText = ""
            if !FrameRatePreference.isHighRefreshEnabled, measuredPiPFPS > FrameRatePreference.targetFrameRate {
                measuredPiPFPS = FrameRatePreference.targetFrameRate
                updateClockOverlay(timestamp: CACurrentMediaTime(), forceNetworkSample: true)
            }
        }
        if !FrameRatePreference.isHighRefreshEnabled {
            stopPlayerLayerActivityDisplayLink(reason: "强制120关闭")
            playerLayer?.player?.pause()
            resetPlayerLayerTransientStateForHighRefreshOff(reason: "强制120开关关闭")
        }
    }

    @objc private func handlePiPContentTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard pipController?.isPictureInPictureActive == true else { return }
        DiagnosticsRuntimeState.recordUserAction("点击悬浮窗内容关闭PiP")
        AppDebugLogger.log("PiP content tapped, stop requested")
        closePiPFromFloatingContent(reason: "点击悬浮窗内容")
    }

    @objc private func handlePiPDirectCloseTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard pipController?.isPictureInPictureActive == true else { return }
        DiagnosticsRuntimeState.recordUserAction("点击透明悬浮窗关闭层")
        AppDebugLogger.log("PiP direct close gesture tapped")
        closePiPFromFloatingContent(reason: "透明关闭层")
    }

    private func closePiPFromFloatingContent(reason: String) {
        isClosingPiPFromCustomContentTap = true
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        stopPiPSmoothly()
    }

    @objc private func updateClockLabel() {
        let shouldRun = isContentExtremeModeEnabled ? shouldRunLowCostPiPContentUpdates : shouldRunPiPContentUpdates
        guard shouldRenderClockMode, shouldRun else {
            stopClockTimer()
            return
        }
        updateClockOverlay(timestamp: CACurrentMediaTime(), forceNetworkSample: !isContentExtremeModeEnabled)
    }

    @objc private func updateClockDisplay(_ displayLink: CADisplayLink) {
        guard shouldRenderClockMode, shouldRunPiPContentUpdates else {
            stopClockTimer()
            return
        }
        logBackgroundClockDiagnosticsIfNeeded(displayLink)
        updateMeasuredFPS(from: displayLink)
        updateClockOverlay(timestamp: displayLink.timestamp, forceNetworkSample: false)
    }

    // FPS 探针：只读时间戳，不修改任何 CALayer/UIView，不触发合成器
    // 强制 120 开启时保留低频采样，关闭时改回 clockDisplayLink 实测。
    @objc private func updateFPSProbe(_ displayLink: CADisplayLink) {
        guard shouldRenderClockMode, shouldRunPiPContentUpdates else {
            fpsProbeDisplayLink?.invalidate()
            fpsProbeDisplayLink = nil
            return
        }
        updateMeasuredFPS(from: displayLink)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "isPictureInPictureSuspended" {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let isSuspended = self.pipController?.isPictureInPictureSuspended ?? false
                AppDebugLogger.log("PiP suspend state changed: \(isSuspended), height=\(self.formattedHeight(self.clampedPiPHeight)), clock=\(self.shouldRenderClockMode), scroll=\(self.isScrollingEnabled)")
                if self.shouldUsePlayerLayerPiPCompatibility {
                    self.updateDiagnosticsPiPState()
                    return
                }
                if isSuspended {
                    self.stopDisplayLinks()
                    self.stopClockTimer()
                    self.updateBackingPlayerPlaybackForCurrentMode()
                    self.recoverPlayerLayerPipelineIfNeeded(reason: "PiP侧边吸附")
                    self.releaseMediaAudioSessionForPiPOnly(reason: "侧边吸附静默")
                    // Auto-hide on dock is temporarily disabled.
                } else {
                    if self.shouldRenderClockMode {
                        self.startClockTimerIfNeeded()
                    } else if self.isScrollingEnabled {
                        self.startDisplayLinks()
                    }
                    self.updateBackingPlayerPlaybackForCurrentMode()
                    self.recoverPlayerLayerPipelineIfNeeded(reason: "PiP离开侧边吸附")
                }
                self.updateDiagnosticsPiPState()
            }
        }
    }

    private func hidePiPForCurrentSuspendedStateIfNeeded(reason: String) {
        // Auto-hide on dock is temporarily disabled.
    }

    private func hidePiPForDockedStateIfNeeded(reason: String) {
        // Auto-hide on dock is temporarily disabled.
    }

    private func hidePiPForDockedState(reason: String) {
        guard pipController?.isPictureInPictureActive == true else { return }
        guard clampedPiPHeight > currentMinimumPiPHeight + 0.01 else { return }

        AppDebugLogger.log("Auto hide PiP when docked: \(reason), target=\(formattedHeight(currentMinimumPiPHeight))")
        DiagnosticsRuntimeState.recordUserAction("吸附后自动隐藏悬浮窗")
        commitPiPHeight(currentMinimumPiPHeight)
    }

    private func logBackgroundClockDiagnosticsIfNeeded(_ displayLink: CADisplayLink) {
        let isSuspended = isPiPSuspendedAtSide
        if lastLoggedPiPSuspendedAtSide != isSuspended {
            lastLoggedPiPSuspendedAtSide = isSuspended
            if let clockDisplayLink {
                configureForClockRefreshRate(clockDisplayLink)
            }
            AppDebugLogger.log("PiP suspended state changed: \(isSuspended)")
        }
        guard UIApplication.shared.applicationState == .background else {
            lastBackgroundClockDiagnosticsTimestamp = nil
            return
        }
        if let lastBackgroundClockDiagnosticsTimestamp,
           displayLink.timestamp - lastBackgroundClockDiagnosticsTimestamp < 5.0 {
            return
        }
        lastBackgroundClockDiagnosticsTimestamp = displayLink.timestamp
        let interval = displayLink.targetTimestamp - displayLink.timestamp
        let instantFPS = interval > 0.001 ? Int((1.0 / interval).rounded()) : 0
        AppDebugLogger.log(
            "后台时间悬浮窗采样：suspended=\(isSuspended),height=\(formattedHeight(clampedPiPHeight)),instantFPS=\(instantFPS),measuredFPS=\(measuredPiPFPS),timestamp=\(String(format: "%.3f", displayLink.timestamp))"
        )
    }

    private func updateMeasuredFPS(from displayLink: CADisplayLink) {
        let frameInterval = displayLink.targetTimestamp - displayLink.timestamp
        guard frameInterval > 0.001 else { return }

        let instantFPS = Int((1.0 / frameInterval).rounded())
        let normalizedFPS = normalizedMeasuredFPS(instantFPS)

        // 调试日志：查看 DisplayLink 实际读到的刷新率
        if measuredPiPFPS != normalizedFPS {
            AppDebugLogger.log("FPS probe: instant=\(instantFPS), normalized=\(normalizedFPS), current=\(measuredPiPFPS), force120Hz=\(FrameRatePreference.isHighRefreshEnabled)")
        }

        if measuredPiPFPS == 0 {
            measuredPiPFPS = normalizedFPS
            pendingMeasuredPiPFPS = nil
            pendingMeasuredPiPFPSCount = 0
            pendingMeasuredPiPFPSStartedAt = nil
            return
        }

        guard normalizedFPS != measuredPiPFPS else {
            pendingMeasuredPiPFPS = nil
            pendingMeasuredPiPFPSCount = 0
            pendingMeasuredPiPFPSStartedAt = nil
            return
        }

        if pendingMeasuredPiPFPS == normalizedFPS {
            pendingMeasuredPiPFPSCount += 1
        } else {
            pendingMeasuredPiPFPS = normalizedFPS
            pendingMeasuredPiPFPSCount = 1
            pendingMeasuredPiPFPSStartedAt = displayLink.timestamp
        }

        let confirmation = fpsConfirmationRequirement(
            from: measuredPiPFPS,
            to: normalizedFPS,
            forceHighRefreshEnabled: FrameRatePreference.isHighRefreshEnabled
        )
        let pendingDuration = displayLink.timestamp - (pendingMeasuredPiPFPSStartedAt ?? displayLink.timestamp)
        if pendingMeasuredPiPFPSCount >= confirmation.count && pendingDuration >= confirmation.duration {
            measuredPiPFPS = normalizedFPS
            pendingMeasuredPiPFPS = nil
            pendingMeasuredPiPFPSCount = 0
            pendingMeasuredPiPFPSStartedAt = nil
        }
    }

    private func fpsConfirmationRequirement(
        from currentFPS: Int,
        to candidateFPS: Int,
        forceHighRefreshEnabled: Bool
    ) -> (count: Int, duration: CFTimeInterval) {
        guard candidateFPS > currentFPS else { return (3, 0) }

        if forceHighRefreshEnabled, candidateFPS >= 120 {
            return (3, 0.02)
        }

        if candidateFPS >= 120 {
            if currentFPS <= 60 {
                return (8, 0.18)
            }
            return (24, 0.9)
        }
        return (5, 0.12)
    }

    private var displayedFPS: Int {
        return measuredPiPFPS
    }

    private func updateClockOverlay(timestamp: CFTimeInterval, forceNetworkSample: Bool) {
        guard let clockOverlayView else { return }
        if !isContentExtremeModeEnabled {
            updateClockMetrics(timestamp: timestamp, forceNetworkSample: forceNetworkSample)
        }
        let now = Date()
        let renderTick = isContentExtremeModeEnabled
            ? Int(now.timeIntervalSince1970.rounded(.down))
            : Int((now.timeIntervalSince1970 * 10).rounded(.down))
        let fpsText = isContentExtremeModeEnabled ? "" : "\(displayedFPS)Hz"
        let networkText = isContentExtremeModeEnabled ? "" : currentNetworkSpeedText
        guard forceNetworkSample
            || renderTick != lastClockRenderTick
            || fpsText != lastClockOverlayFPSText
            || networkText != lastClockOverlayNetworkText else {
            return
        }

        let timeText = clockFormatter.string(from: now)
        guard timeText != lastClockOverlayTimeText
            || fpsText != lastClockOverlayFPSText
            || networkText != lastClockOverlayNetworkText else {
            return
        }
        lastClockRenderTick = renderTick
        lastClockOverlayTimeText = timeText
        lastClockOverlayFPSText = fpsText
        lastClockOverlayNetworkText = networkText
        clockLabel?.text = timeText
        clockOverlayView.update(time: timeText, fps: fpsText, network: networkText)
    }

    private func updateClockMetrics(timestamp: CFTimeInterval, forceNetworkSample: Bool) {
        guard !isExtremeSilentModeEnabled else { return }
        if forceNetworkSample {
            updateNetworkSpeed(force: true)
            lastClockNetworkTimestamp = timestamp
        } else if let lastClockNetworkTimestamp {
            let networkElapsed = timestamp - lastClockNetworkTimestamp
            if networkElapsed >= clockNetworkMeasureInterval {
                updateNetworkSpeed(force: true)
                self.lastClockNetworkTimestamp = timestamp
            }
        } else {
            lastClockNetworkTimestamp = timestamp
        }
    }

    private func normalizedMeasuredFPS(_ rawFPS: Int) -> Int {
        let hardwareMaximum = max(60, UIScreen.main.maximumFramesPerSecond)
        let clampedFPS = min(max(30, rawFPS), hardwareMaximum)
        let standardRates = [30, 45, 60, 75, 80, 90, 100, 120].filter { $0 <= hardwareMaximum }
        guard let nearest = standardRates.min(by: { abs($0 - clampedFPS) < abs($1 - clampedFPS) }) else {
            return clampedFPS
        }
        let distance = abs(nearest - clampedFPS)
        if distance <= 5 {
            return nearest
        }
        return Int((Double(clampedFPS) / 5.0).rounded() * 5.0)
    }

    private func updateNetworkSpeed(force: Bool) {
        guard let sample = NetworkTrafficSample.current() else { return }
        guard let lastNetworkSample else {
            self.lastNetworkSample = sample
            return
        }
        let elapsed = sample.timestamp.timeIntervalSince(lastNetworkSample.timestamp)
        guard force || elapsed >= 1 else { return }
        guard elapsed > 0 else {
            self.lastNetworkSample = sample
            return
        }
        let upload = Double(sample.sentBytes.subtractingReportingOverflow(lastNetworkSample.sentBytes).partialValue) / elapsed
        let download = Double(sample.receivedBytes.subtractingReportingOverflow(lastNetworkSample.receivedBytes).partialValue) / elapsed
        guard upload < 100 * 1024 * 1024, download < 100 * 1024 * 1024 else {
            self.lastNetworkSample = sample
            return
        }
        currentNetworkSpeedText = "↑\(formatNetworkSpeed(max(0, upload))) ↓\(formatNetworkSpeed(max(0, download)))"
        self.lastNetworkSample = sample
    }

    private func formatNetworkSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 100 * 1024 * 1024 {
            return "\(Int((bytesPerSecond / 1024 / 1024).rounded()))MB"
        }
        if bytesPerSecond >= 1024 * 1024 {
            return String(format: "%.1fMB", bytesPerSecond / 1024 / 1024)
        }
        if bytesPerSecond >= 100 * 1024 {
            return "\(Int((bytesPerSecond / 1024).rounded()))KB"
        }
        if bytesPerSecond >= 1024 {
            return String(format: "%.0fKB", bytesPerSecond / 1024)
        }
        return "\(Int(bytesPerSecond.rounded()))B"
    }

    private func startPiPSmoothly() {
        guard pipController != nil else {
            isPiPActiveForUI = false
            return
        }
        if shouldUsePlayerLayerPiPCompatibility {
            startLegacyPlayerLayerPiP()
            return
        }

        guard !isPiPTransitioning else {
            isPiPActiveForUI = pipController.isPictureInPictureActive
            return
        }
        restoreMinimumRememberedHeightIfNeeded()
        beginPiPTransition(expectedActive: true, reason: "start smooth")
        isStoppingPiP = false
        AppDebugLogger.log("Start PiP smoothly, legacy=\(needsLegacyPiPCompatibility), size=\(Int(currentPiPSize.width))x\(Int(currentPiPSize.height))")
        prepareCustomViewForPiPStart()
        restorePiPVisualSurfaces()
        showPiPContentForOpening()
        prepareSourceLayerForPiP()
        keepPlaybackAlive()
        if needsLegacyPiPCompatibility {
            schedulePiPStartTimeout()
        }
        requestPiPStartWhenReady()
    }

    private func startLegacyPlayerLayerPiP() {
        guard pipController != nil else {
            isPiPActiveForUI = false
            return
        }
        guard !isPiPTransitioning else {
            isPiPActiveForUI = pipController.isPictureInPictureActive
            return
        }
        restoreMinimumRememberedHeightIfNeeded()
        captureWindowsBeforePiPStart()
        beginPiPTransition(expectedActive: true, reason: "start legacy")
        isStoppingPiP = false
        prepareCustomViewForPiPStart()
        restorePiPVisualSurfaces()
        showPiPContentForOpening()
        prepareSourceLayerForPiP()
        primePlayerLayerPiPStartIfNeeded(reason: "PlayerLayer PiP开始启动")
        schedulePiPStartTimeout()
        requestLegacyPlayerLayerPiPStartWhenReady()
    }

    private func requestLegacyPlayerLayerPiPStartWhenReady(attempt: Int = 0) {
        pendingPiPStartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard
                let self,
                self.isPiPTransitioning,
                let pipController = self.pipController,
                !pipController.isPictureInPictureActive
            else {
                return
            }
            guard self.isPlayerReadyForPiP && pipController.isPictureInPicturePossible else {
                AppDebugLogger.log("Wait PlayerLayer PiP: attempt=\(attempt), possible=\(pipController.isPictureInPicturePossible), playerReady=\(self.isPlayerReadyForPiP)")
                if attempt < self.maximumPiPStartAttempts {
                    _ = self.activatePlayerLayerPiPStartAudioIfNeeded(attempt: attempt)
                    self.requestLegacyPlayerLayerPiPStartWhenReady(attempt: attempt + 1)
                } else {
                    if self.retryPiPStartWithLegacyControlsStyleFallbackIfNeeded(reason: "PlayerLayer PiP暂时不可启动：possible=\(pipController.isPictureInPicturePossible), playerReady=\(self.isPlayerReadyForPiP)") {
                        return
                    }
                    self.resetPiPStartStateAfterFailure()
                    let message = "PlayerLayer PiP暂时不可启动：possible=\(pipController.isPictureInPicturePossible), playerReady=\(self.isPlayerReadyForPiP)"
                    AppDebugLogger.log(message)
                    print(message)
                }
                return
            }
            AppDebugLogger.log("PlayerLayer PiP startPictureInPicture requested at attempt=\(attempt)")
            pipController.startPictureInPicture()
            self.schedulePlayerLayerPiPStartConfirmationRetry(afterStartAttempt: attempt)
        }
        pendingPiPStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + piPStartRetryDelay(for: attempt), execute: workItem)
    }

    private func schedulePlayerLayerPiPStartConfirmationRetry(afterStartAttempt attempt: Int) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard
                let self,
                self.shouldUsePlayerLayerPiPCompatibility,
                self.isPiPTransitioning,
                self.wantsPiPActive,
                let pipController = self.pipController,
                !pipController.isPictureInPictureActive
            else {
                return
            }
            guard attempt < self.maximumPiPStartAttempts else {
                if self.retryPiPStartWithLegacyControlsStyleFallbackIfNeeded(reason: "PlayerLayer PiP start ignored and retries exhausted: attempt=\(attempt)") {
                    return
                }
                self.resetPiPStartStateAfterFailure()
                AppDebugLogger.log("PlayerLayer PiP start ignored and retries exhausted: attempt=\(attempt)")
                return
            }
            AppDebugLogger.log("PlayerLayer PiP start request was ignored; retrying, attempt=\(attempt + 1), possible=\(pipController.isPictureInPicturePossible), playerReady=\(self.isPlayerReadyForPiP)")
            self.requestLegacyPlayerLayerPiPStartWhenReady(attempt: attempt + 1)
        }
        pendingPiPStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: workItem)
    }

    private func restoreMinimumRememberedHeightIfNeeded() {
        guard !shouldUsePlayerLayerPiPCompatibility, clampedPiPHeight <= minPiPHeight + 0.01 else { return }
        pipHeight = compactPiPHeight
        isCompactPiPStyle = true
        updatePiPSourceGeometry()
        videoCallContentController?.preferredContentSize = currentPiPSize
        reloadPlayerItemIfNeededForCurrentSize()
        configureRunningText()
        if remembersPiPHeight {
            saveCurrentPiPHeightPreference()
        }
        updateHomeView()
    }

    private func stopPiPSmoothly() {
        guard pipController != nil else {
            isPiPActiveForUI = false
            return
        }
        guard !isPiPTransitioning else {
            pendingPiPStartWorkItem?.cancel()
            finishPiPTransition()
            isPiPActiveForUI = pipController.isPictureInPictureActive
            return
        }
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        beginPiPTransition(expectedActive: false, reason: "stop smooth")
        isStoppingPiP = true
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        stopDisplayLinks()
        stopClockTimer()
        stopPlayerLayerActivityDisplayLink(reason: "手动关闭悬浮窗")
        if shouldUseVideoCallOffscreenCloseAnimation {
            movePiPSourceViewOffscreenForClosing()
        } else {
            hidePiPContentForClosing()
            preparePiPVisualSurfacesForClosing()
            movePiPSourceViewOffscreenForClosing()
        }
        pipController.stopPictureInPicture()
    }

    private func resignForegroundAfterPiPCloseIfNeeded(reason: String) {
        guard shouldResignForegroundAfterPiPClose else { return }
        hideForegroundWindowsForPiPClose(reason: reason)
        let selector = NSSelectorFromString("suspend")
        guard UIApplication.shared.responds(to: selector) else {
            AppDebugLogger.log("PiP close cannot resign foreground: suspend selector unavailable, reason=\(reason)")
            shouldResignForegroundAfterPiPClose = false
            restoreForegroundWindowsHiddenForPiPCloseIfNeeded()
            return
        }

        if UIApplication.shared.applicationState != .background {
            AppDebugLogger.log("PiP close resign foreground immediately: reason=\(reason), state=\(UIApplication.shared.applicationState.rawValue)")
            _ = UIApplication.shared.perform(selector)
        }

        let delays: [TimeInterval] = [0, 0.03, 0.12, 0.3]
        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.shouldResignForegroundAfterPiPClose else { return }
                if UIApplication.shared.applicationState != .background {
                    AppDebugLogger.log("PiP close resign foreground: reason=\(reason), delay=\(delay)")
                    _ = UIApplication.shared.perform(selector)
                } else if UIApplication.shared.applicationState == .background {
                    self.shouldResignForegroundAfterPiPClose = false
                }
                if index == delays.indices.last {
                    self.shouldResignForegroundAfterPiPClose = false
                }
            }
        }
    }

    private func hideForegroundWindowsForPiPClose(reason: String) {
        guard windowsHiddenForPiPClose.isEmpty else { return }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.alpha > 0.001 }
        guard !windows.isEmpty else { return }
        windowsHiddenForPiPClose = windows.map { ($0, $0.alpha) }
        UIView.performWithoutAnimation {
            windows.forEach { $0.alpha = 0 }
        }
        AppDebugLogger.log("Hide app windows before PiP close foreground restore: reason=\(reason), count=\(windows.count)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.shouldResignForegroundAfterPiPClose else { return }
            self.restoreForegroundWindowsHiddenForPiPCloseIfNeeded()
        }
    }

    private func restoreForegroundWindowsHiddenForPiPCloseIfNeeded() {
        guard !windowsHiddenForPiPClose.isEmpty else { return }
        UIView.performWithoutAnimation {
            windowsHiddenForPiPClose.forEach { item in
                item.window.alpha = item.alpha
            }
        }
        windowsHiddenForPiPClose.removeAll()
        AppDebugLogger.log("Restore app windows hidden for PiP close")
    }

    @discardableResult
    private func triggerSystemPiPCloseControlIfAvailable(reason: String) -> Bool {
        guard pipController?.isPictureInPictureActive == true else { return false }
        let controls = systemPiPControls()
        let diagnostics = controls.map(systemPiPControlDescription).joined(separator: ";")
        let sortedControls = controls.sorted { lhs, rhs in
            let lhsFrame = lhs.convert(lhs.bounds, to: nil)
            let rhsFrame = rhs.convert(rhs.bounds, to: nil)
            if abs(lhsFrame.midY - rhsFrame.midY) > 2 {
                return lhsFrame.midY < rhsFrame.midY
            }
            return lhsFrame.midX < rhsFrame.midX
        }
        guard let control = sortedControls.first(where: isLikelySystemPiPCloseControl) else {
            AppDebugLogger.log("System PiP close control unavailable: reason=\(reason), controls=\(diagnostics)")
            return false
        }

        AppDebugLogger.log("Trigger system PiP close control: reason=\(reason), control=\(systemPiPControlDescription(control))")
        wantsPiPActive = false
        isPiPActiveForUI = false
        updatePiPAutomaticStartPolicy()
        if !control.accessibilityActivate() {
            control.sendActions(for: [.touchUpInside, .primaryActionTriggered])
        }
        return true
    }

    private func systemPiPControls() -> [UIControl] {
        allApplicationWindows()
            .filter { window in
                window !== view.window
                    && !window.isHidden
                    && window.alpha > 0
            }
            .flatMap { window in
                visibleControls(in: window)
            }
            .filter { control in
                control !== customView
                    && control.window !== view.window
                    && isControlOutsideCustomPiPContent(control)
            }
    }

    private func installDirectCloseGestureForSystemPiPControls(reason: String) {
        guard pipController?.isPictureInPictureActive == true else { return }
        guard let host = candidatePiPGestureHostView() else {
            AppDebugLogger.log("Skip install PiP direct close gesture: host unavailable, reason=\(reason), windows=\(windowDiagnosticsForPiPAttach())")
            return
        }
        if pipDirectCloseGestureHost !== host {
            if let gesture = pipDirectCloseTapGesture {
                pipDirectCloseGestureHost?.removeGestureRecognizer(gesture)
            }
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handlePiPDirectCloseTap(_:)))
            gesture.cancelsTouchesInView = true
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            host.addGestureRecognizer(gesture)
            pipDirectCloseTapGesture = gesture
            pipDirectCloseGestureHost = host
            AppDebugLogger.log("Install PiP direct close gesture: reason=\(reason), host=\(type(of: host)), bounds=\(host.bounds), window=\(type(of: host.window))")
        }
        updateSystemPiPControlsForDirectClose(reason: reason)
    }

    private func removeDirectCloseGestureForSystemPiPControls() {
        if let gesture = pipDirectCloseTapGesture {
            pipDirectCloseGestureHost?.removeGestureRecognizer(gesture)
        }
        pipDirectCloseTapGesture = nil
        pipDirectCloseGestureHost = nil
    }

    private func candidatePiPGestureHostView() -> UIView? {
        let visibleWindows = allApplicationWindows().filter {
            $0 !== view.window
                && !$0.isHidden
                && $0.alpha > 0
                && $0.bounds.width > 1
                && $0.bounds.height > 1
        }
        if let newWindow = visibleWindows.first(where: { !windowsBeforePiPStart.contains(ObjectIdentifier($0)) }) {
            return newWindow
        }
        return visibleWindows.first
    }

    private func updateSystemPiPControlsForDirectClose(reason: String) {
        let controls = systemPiPControls()
        guard !controls.isEmpty else {
            AppDebugLogger.log("No system PiP controls to adjust: reason=\(reason)")
            return
        }
        for control in controls {
            let frame = control.convert(control.bounds, to: nil)
            let screen = control.window?.screen.bounds ?? UIScreen.main.bounds
            let isLeftCloseArea = frame.minX <= screen.width * 0.40
            control.alpha = 0.01
            control.isHidden = false
            control.isUserInteractionEnabled = isLeftCloseArea
            AppDebugLogger.log("Adjust PiP system control: reason=\(reason), left=\(isLeftCloseArea), control=\(systemPiPControlDescription(control))")
        }
    }

    private func visibleControls(in rootView: UIView) -> [UIControl] {
        var controls: [UIControl] = []
        func visit(_ view: UIView) {
            if let control = view as? UIControl {
                controls.append(control)
            }
            view.subviews.forEach(visit)
        }
        visit(rootView)
        return controls
    }

    private func isControlOutsideCustomPiPContent(_ control: UIControl) -> Bool {
        var current: UIView? = control
        while let view = current {
            if view === customView || view === textView || view === clockOverlayView || view === clockLabel {
                return false
            }
            current = view.superview
        }
        return true
    }

    private func isLikelySystemPiPCloseControl(_ control: UIControl) -> Bool {
        let text = [
            String(describing: type(of: control)),
            control.accessibilityLabel,
            control.accessibilityIdentifier,
            control.accessibilityHint
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        if text.contains("close")
            || text.contains("dismiss")
            || text.contains("stop")
            || text.contains("关闭")
            || text.contains("結束")
            || text.contains("退出")
            || text.contains("xmark") {
            return true
        }

        let frame = control.convert(control.bounds, to: nil)
        let screen = control.window?.screen.bounds ?? UIScreen.main.bounds
        let maxSide = max(frame.width, frame.height)
        let minSide = min(frame.width, frame.height)
        let isSmallButton = maxSide <= 72 && minSide >= 16
        let isNearTopLeft = frame.minY <= screen.height * 0.28
            && frame.minX <= screen.width * 0.40
        return isSmallButton && isNearTopLeft && control.allTargets.count > 0
    }

    private func systemPiPControlDescription(_ control: UIControl) -> String {
        let frame = control.convert(control.bounds, to: nil)
        let label = control.accessibilityLabel ?? "-"
        let identifier = control.accessibilityIdentifier ?? "-"
        return "\(type(of: control)){hidden=\(control.isHidden),alpha=\(String(format: "%.2f", control.alpha)),enabled=\(control.isEnabled),frame=\(formatRect(frame)),label=\(label),id=\(identifier),targets=\(control.allTargets.count)}"
    }

    private func requestPiPStartWhenReady(attempt: Int = 0) {
        pendingPiPStartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            self.prepareCustomViewForPiPStart()
            self.restorePiPVisualSurfaces()
            self.showPiPContentForOpening()
            self.prepareSourceLayerForPiP()
            self.keepPlaybackAlive()

            guard let pipSourceView = self.pipSourceView, let pipController = self.pipController else {
                self.resetPiPStartStateAfterFailure()
                return
            }

            let sourceReady = !pipSourceView.bounds.isEmpty && pipSourceView.window != nil
            let canStartNow = self.isPlayerReadyForPiP && sourceReady && pipController.isPictureInPicturePossible

            if canStartNow {
                self.pendingPiPStartWorkItem = nil
                pipController.startPictureInPicture()
                return
            }

            if attempt < self.maximumPiPStartAttempts {
                self.requestPiPStartWhenReady(attempt: attempt + 1)
            } else {
                if self.retryPiPStartWithLegacyControlsStyleFallbackIfNeeded(reason: "画中画暂时不可启动：possible=\(pipController.isPictureInPicturePossible), playerReady=\(self.isPlayerReadyForPiP), sourceReady=\(sourceReady)") {
                    return
                }
                if self.retryLegacyPiPStartIfNeeded(reason: "画中画暂时不可启动：possible=\(pipController.isPictureInPicturePossible), playerReady=\(self.isPlayerReadyForPiP), sourceReady=\(sourceReady)") {
                    return
                }
                self.resetPiPStartStateAfterFailure()
                let message = "画中画暂时不可启动：possible=\(pipController.isPictureInPicturePossible), playerReady=\(self.isPlayerReadyForPiP), sourceReady=\(sourceReady)"
                AppDebugLogger.log(message)
                print(message)
            }
        }

        pendingPiPStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + piPStartRetryDelay(for: attempt), execute: workItem)
    }

    private var maximumPiPStartAttempts: Int {
        if shouldUsePlayerLayerPiPCompatibility {
            return 36
        }
        guard needsLegacyPiPCompatibility else {
            return 8
        }
        return 36
    }

    private func piPStartRetryDelay(for attempt: Int) -> TimeInterval {
        if shouldUsePlayerLayerPiPCompatibility {
            return attempt == 0 ? 0.18 : 0.15
        }
        guard needsLegacyPiPCompatibility else {
            return attempt == 0 ? 0.02 : 0.12
        }
        if attempt == 0 {
            return 0.05
        }
        return 0.15
    }

    private func schedulePiPStartTimeout() {
        pipStartTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard
                let self,
                self.isPiPTransitioning,
                let pipController = self.pipController,
                !pipController.isPictureInPictureActive
            else {
                return
            }
            if self.retryPiPStartWithLegacyControlsStyleFallbackIfNeeded(reason: "画中画启动超时") {
                return
            }
            if self.retryLegacyPiPStartIfNeeded(reason: "画中画启动超时") {
                return
            }
            self.resetPiPStartStateAfterFailure()
            AppDebugLogger.log("PiP start timeout")
            print("画中画启动超时，已恢复按钮状态")
        }
        pipStartTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + piPStartTimeoutDuration, execute: workItem)
    }

    private var piPStartTimeoutDuration: TimeInterval {
        shouldUsePlayerLayerPiPCompatibility ? 8.0 : 8.0
    }

    private func resetPiPStartStateAfterFailure() {
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        pipTransitionWatchdogWorkItem?.cancel()
        cancelDelayedPiPHideCountdown(reason: "悬浮窗启动失败")
        pipExpectedActiveBeforeStop = nil
        pendingPiPStartWorkItem = nil
        pipStartTimeoutWorkItem = nil
        hasPrimedPlayerLayerPiPStart = false
        isLegacyPlayerLayerFallbackActive = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        wantsPiPActive = false
        isOwnPiPConfirmedActive = pipController?.isPictureInPictureActive ?? false
        updatePiPAutomaticStartPolicy()
        detachLegacyCustomViewIfNeeded()
        isPiPActiveForUI = pipController?.isPictureInPictureActive ?? false
        isStoppingPiP = false
        finishPiPTransition()
        if pipController?.isPictureInPictureActive != true {
            finishPiPRuntimeSession()
        }
        if pipController?.isPictureInPictureActive != true {
            stopDisplayLinks()
            BackgroundTaskManager.shared.stopPlay()
            pauseBackingPlayerIfIdle()
            releaseTransientPlayerLayerPiPAudioSession(reason: "PiP启动失败恢复")
            endBackgroundTask()
        }
    }

    private func retryPiPStartWithLegacyControlsStyleFallbackIfNeeded(reason: String) -> Bool {
        guard shouldExperimentWithLegacyPiPControlsStyle2,
              preferredPiPControlsStyle == 2,
              !didFallbackLegacyPiPControlsStyle
        else {
            return false
        }

        didFallbackLegacyPiPControlsStyle = true
        pipControlsStyleOverride = 1
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        pipTransitionWatchdogWorkItem?.cancel()
        pendingPlayerLayerAudioReleaseWorkItem?.cancel()
        pendingPiPStartWorkItem = nil
        pipStartTimeoutWorkItem = nil
        pendingPlayerLayerAudioReleaseWorkItem = nil
        hasPrimedPlayerLayerPiPStart = false
        playerLayerPiPStartAudioMode = .defaultStartupMode

        AppDebugLogger.log("\(reason), iOS15 controlsStyle=2 failed; fallback to controlsStyle=1")
        teardownPiPInfrastructure()
        wantsPiPActive = true
        isPiPActiveForUI = true
        guard preparePiPInfrastructureIfNeeded() else {
            resetPiPStartStateAfterFailure()
            AppDebugLogger.log("PiP controlsStyle fallback prepare failed")
            return true
        }
        updatePiPAutomaticStartPolicy()
        configureRunningText()
        updateHomeView()
        finishPiPTransition()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard
                let self,
                self.isPiPActiveForUI,
                self.pipController?.isPictureInPictureActive != true
            else {
                return
            }
            self.startPiPSmoothly()
        }
        return true
    }

    private func retryLegacyPiPStartIfNeeded(reason: String) -> Bool {
        guard needsLegacyPiPCompatibility, !shouldUsePlayerLayerPiPCompatibility, !didRetryLegacyPiPStart else {
            return false
        }
        didRetryLegacyPiPStart = true
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        pendingPiPStartWorkItem = nil
        pipStartTimeoutWorkItem = nil

        print("\(reason)，低版本兼容模式重试一次")
        AppDebugLogger.log("\(reason), retry legacy compatibility once")
        pipHeight = compactPiPHeight
        isCompactPiPStyle = true
        updatePiPSourceGeometry()
        videoCallContentController?.preferredContentSize = currentPiPSize
        reloadPlayerItemIfNeededForCurrentSize()
        configureRunningText()
        updateHomeView()

        finishPiPTransition()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard
                let self,
                self.isPiPActiveForUI,
                let pipController = self.pipController,
                !pipController.isPictureInPictureActive
            else {
                return
            }
            self.startPiPSmoothly()
        }
        return true
    }

    private func prepareCustomViewForPiPStart() {
        if shouldUsePlayerLayerPiPCompatibility {
            guard shouldAttachCustomViewInPlayerLayerPiP else {
                detachLegacyCustomViewIfNeeded()
                return
            }
            attachCustomViewToPiPWindowIfAvailable(reason: "prepare start")
        } else {
            attachCustomViewToPiPContent()
        }
    }

    private func attachCustomViewToKeyWindow() {
        guard shouldAttachCustomViewInPlayerLayerPiP else { return }
        attachCustomViewToPiPWindowIfAvailable(reason: "legacy fallback")
    }

    private func captureWindowsBeforePiPStart() {
        windowsBeforePiPStart = Set(allApplicationWindows().map { ObjectIdentifier($0) })
    }

    @discardableResult
    private func attachCustomViewToPiPWindowIfAvailable(reason: String) -> Bool {
        guard shouldUsePlayerLayerPiPCompatibility, let customView else { return false }
        guard let hostView = candidatePiPHostViewForCustomView() else {
            AppDebugLogger.log("Skip attach custom view: PiP host unavailable, reason=\(reason), windows=\(windowDiagnosticsForPiPAttach())")
            return false
        }
        if customView.superview !== hostView {
            customView.removeFromSuperview()
            hostView.addSubview(customView)
            AppDebugLogger.log("Attach custom view to PiP host, reason=\(reason), host=\(type(of: hostView)), bounds=\(hostView.bounds), window=\(type(of: hostView.window))")
        }
        updateLegacyCustomViewGeometry()
        hostView.layoutIfNeeded()
        return true
    }

    private func allApplicationWindows() -> [UIWindow] {
        var windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in UIApplication.shared.windows where !windows.contains(where: { $0 === window }) {
            windows.append(window)
        }
        return windows
    }

    private func candidatePiPHostViewForCustomView() -> UIView? {
        let windows = allApplicationWindows()
        let visibleWindows = windows.filter {
            !$0.isHidden
                && $0.alpha > 0
                && $0.bounds.width > 1
                && $0.bounds.height > 1
        }

        if let currentHost = customView?.superview,
           currentHost !== view,
           currentHost.window !== view.window,
           isSafePiPHostView(currentHost) {
            return currentHost
        }

        let newWindows = visibleWindows.filter { window in
            window !== view.window && !windowsBeforePiPStart.contains(ObjectIdentifier(window))
        }
        if let host = newWindows.compactMap({ safePiPHostView(in: $0) }).first {
            return host
        }

        if pipController?.isPictureInPictureActive == true {
            let nonMainWindows = visibleWindows.filter { $0 !== view.window }
            if let host = nonMainWindows.compactMap({ safePiPHostView(in: $0) }).first {
                return host
            }
        }

        return nil
    }

    private func safePiPHostView(in window: UIWindow) -> UIView? {
        if isSafePiPHostView(window) {
            return window
        }
        return safePiPSubviewCandidates(in: window).first
    }

    private func safePiPSubviewCandidates(in rootView: UIView) -> [UIView] {
        var candidates: [UIView] = []
        func visit(_ candidate: UIView) {
            if isSafePiPHostView(candidate) {
                candidates.append(candidate)
            }
            candidate.subviews.forEach(visit)
        }
        rootView.subviews.forEach(visit)
        return candidates.sorted { lhs, rhs in
            let lhsArea = lhs.bounds.width * lhs.bounds.height
            let rhsArea = rhs.bounds.width * rhs.bounds.height
            return lhsArea > rhsArea
        }
    }

    private func isSafePiPHostView(_ candidate: UIView) -> Bool {
        guard !candidate.isHidden, candidate.alpha > 0 else { return false }
        let bounds = candidate.bounds
        guard bounds.width >= currentPiPSize.width * 0.5,
              bounds.height >= currentPiPSize.height * 0.5 else {
            return false
        }

        let screenBounds = candidate.window?.screen.bounds ?? UIScreen.main.bounds
        let screenWidth = max(screenBounds.width, screenBounds.height)
        let screenHeight = min(screenBounds.width, screenBounds.height)
        let candidateWidth = max(bounds.width, bounds.height)
        let candidateHeight = min(bounds.width, bounds.height)
        let isFullscreenLike = candidateWidth >= screenWidth * 0.92
            && candidateHeight >= screenHeight * 0.92
        return !isFullscreenLike
    }

    private func windowDiagnosticsForPiPAttach() -> String {
        allApplicationWindows().enumerated().map { index, window in
            let marker = windowsBeforePiPStart.contains(ObjectIdentifier(window)) ? "old" : "new"
            let isMain = window === view.window ? "main" : "other"
            return "#\(index){\(marker),\(isMain),hidden=\(window.isHidden),alpha=\(String(format: "%.2f", window.alpha)),bounds=\(formatRect(window.bounds)),type=\(type(of: window))}"
        }.joined(separator: ";")
    }

    private func detachLegacyCustomViewIfNeeded() {
        guard shouldUsePlayerLayerPiPCompatibility, let customView else { return }
        customView.removeFromSuperview()
        legacyCustomViewWidthConstraint = nil
        legacyCustomViewHeightConstraint = nil
    }

    private func hidePiPContentForClosing() {
        guard let customView, let textView else { return }
        UIView.performWithoutAnimation {
            customView.layer.removeAllAnimations()
            customView.alpha = 0
            customView.layer.opacity = 0
            textView.alpha = 0
            textView.layer.opacity = 0
            clockLabel?.alpha = 0
            clockLabel?.layer.opacity = 0
            clockOverlayView?.alpha = 0
            clockOverlayView?.layer.opacity = 0
            customView.superview?.layoutIfNeeded()
        }
    }

    private func showPiPContentForOpening() {
        guard let customView, let textView else { return }
        guard !shouldUsePlayerLayerPiPCompatibility || shouldAttachCustomViewInPlayerLayerPiP else {
            hidePiPContentForClosing()
            return
        }
        if shouldRenderClockMode {
            updateClockAppearance()
            updateClockOverlay(timestamp: CACurrentMediaTime(), forceNetworkSample: true)
        }
        UIView.performWithoutAnimation {
            textView.alpha = 1
            clockLabel?.alpha = 0
            clockLabel?.isHidden = true
            customView.alpha = 1
            customView.layer.opacity = 1
            textView.layer.opacity = textView.isHidden ? 0 : 1
            clockLabel?.layer.opacity = 0
            clockOverlayView?.layer.opacity = (shouldRenderClockMode && !isPiPVisuallyHidden) ? 1 : 0
            clockOverlayView?.alpha = (shouldRenderClockMode && !isPiPVisuallyHidden) ? 1 : 0
            customView.superview?.layoutIfNeeded()
        }
    }

    private func preparePiPVisualSurfacesForClosing() {
        guard let pipSourceView else { return }
        UIView.performWithoutAnimation {
            pipSourceView.backgroundColor = .clear
            pipSourceView.layer.backgroundColor = UIColor.clear.cgColor
            pipSourceView.alpha = 0.01
            videoCallContentController?.preferredContentSize = CGSize(width: 1, height: 1)
            videoCallContentController?.view.backgroundColor = .clear
            videoCallContentController?.view.layer.backgroundColor = UIColor.clear.cgColor
            videoCallContentController?.view.alpha = 0.01
            playerLayer?.opacity = 0
            playerLayer?.backgroundColor = UIColor.clear.cgColor
            playerLayer?.removeAllAnimations()
            view.layoutIfNeeded()
            CATransaction.flush()
        }
    }

    private func restorePiPVisualSurfaces() {
        guard let pipSourceView else { return }
        UIView.performWithoutAnimation {
            restorePiPSourceViewFrame()
            pipSourceView.alpha = 1
            pipSourceView.layer.opacity = 1
            pipSourceView.backgroundColor = .clear
            pipSourceView.layer.backgroundColor = UIColor.clear.cgColor
            pipSourceView.isOpaque = false
            pipSourceView.layer.isOpaque = false
            videoCallContentController?.preferredContentSize = currentPiPSize
            videoCallContentController?.view.alpha = 1
            videoCallContentController?.view.backgroundColor = .clear
            videoCallContentController?.view.layer.backgroundColor = UIColor.clear.cgColor
            videoCallContentController?.view.isOpaque = false
            videoCallContentController?.view.layer.isOpaque = false
            playerLayer?.opacity = shouldUsePlayerLayerPiPCompatibility ? 1 : 0
            playerLayer?.backgroundColor = UIColor.clear.cgColor
            view.layoutIfNeeded()
        }
    }

    private func movePiPSourceViewOffscreenForClosing() {
        guard let pipSourceView else { return }
        guard !needsLegacyPiPCompatibility else {
            view.layoutIfNeeded()
            CATransaction.flush()
            return
        }
        UIView.performWithoutAnimation {
            pipSourceWidthConstraint = nil
            pipSourceHeightConstraint = nil
            pipSourceView.snp.remakeConstraints { make in
                make.top.equalTo(view.snp.top).offset(-8)
                make.leading.equalTo(view.snp.leading).offset(-8)
                make.width.height.equalTo(1)
            }
            view.layoutIfNeeded()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer?.frame = CGRect(x: -8, y: -8, width: 1, height: 1)
            playerLayer?.removeAllAnimations()
            CATransaction.commit()
            CATransaction.flush()
        }
    }

    private func restorePiPSourceViewFrame() {
        updatePiPSourceGeometry()
    }

    private func updatePiPSourceGeometry() {
        guard let pipSourceView else { return }
        if let pipSourceWidthConstraint, let pipSourceHeightConstraint {
            pipSourceWidthConstraint.update(offset: currentPiPSize.width)
            pipSourceHeightConstraint.update(offset: currentPiPSize.height)
        } else {
            pipSourceView.snp.remakeConstraints { make in
                make.center.equalToSuperview()
                pipSourceWidthConstraint = make.width.equalTo(currentPiPSize.width).constraint
                pipSourceHeightConstraint = make.height.equalTo(currentPiPSize.height).constraint
            }
        }
        pipSourceView.alpha = 1
        pipSourceView.layer.opacity = 1
        videoCallContentController?.view.alpha = 1
        playerLayer?.opacity = shouldUsePlayerLayerPiPCompatibility ? 1 : 0
        view.layoutIfNeeded()
        centerPlayerLayer()
        updateLegacyCustomViewGeometry()
    }

    private func updateLegacyCustomViewGeometry() {
        guard shouldUsePlayerLayerPiPCompatibility, let customView, customView.superview != nil else { return }
        customView.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        legacyCustomViewWidthConstraint = nil
        legacyCustomViewHeightConstraint = nil
        customView.superview?.layoutIfNeeded()
    }

    private func configureRunningText() {
        guard let textView else { return }
        if shouldUsePlayerLayerPiPCompatibility && !shouldAttachCustomViewInPlayerLayerPiP {
            stopDisplayLinks()
            stopClockTimer()
            customView?.removeFromSuperview()
            textView.isHidden = true
            clockLabel?.isHidden = true
            clockOverlayView?.isHidden = true
            return
        }
        if isPiPVisuallyHidden {
            customView?.backgroundColor = .clear
            customView?.layer.backgroundColor = UIColor.clear.cgColor
            customView?.layer.opacity = 0
            customView?.isOpaque = false
            customView?.layer.isOpaque = false
            textView.isHidden = true
            textView.alpha = 0
            textView.layer.opacity = 0
            clockLabel?.isHidden = true
            clockLabel?.alpha = 0
            clockLabel?.layer.opacity = 0
            clockOverlayView?.isHidden = true
            clockOverlayView?.alpha = 0
            clockOverlayView?.layer.opacity = 0
            if shouldRenderClockMode {
                startClockTimerIfNeeded()
            } else if isScrollingEnabled, !isContentExtremeModeEnabled {
                startDisplayLinks()
            }
            return
        }
        if shouldRenderClockMode {
            stopDisplayLinks()
            customView?.backgroundColor = .white
            customView?.layer.backgroundColor = UIColor.white.cgColor
            customView?.layer.opacity = 1
            customView?.layer.isOpaque = true
            customView?.isOpaque = true
            pipSourceView?.backgroundColor = .clear
            pipSourceView?.layer.backgroundColor = UIColor.clear.cgColor
            pipSourceView?.isOpaque = false
            pipSourceView?.layer.isOpaque = false
            videoCallContentController?.view.backgroundColor = .clear
            videoCallContentController?.view.layer.backgroundColor = UIColor.clear.cgColor
            videoCallContentController?.view.isOpaque = false
            videoCallContentController?.view.layer.isOpaque = false
            textView.isHidden = true
            textView.alpha = 0
            textView.layer.opacity = 0
            clockLabel?.isHidden = true
            clockLabel?.alpha = 0
            clockLabel?.layer.opacity = 0
            clockOverlayView?.isHidden = false
            clockOverlayView?.alpha = 1
            clockOverlayView?.layer.opacity = 1
            updateClockAppearance()
            if shouldPreviewPiPHeightLive {
                startClockTimerIfNeeded()
            } else {
                stopClockTimer()
            }
            return
        }

        stopClockTimer()
        customView?.backgroundColor = .white
        customView?.layer.backgroundColor = UIColor.white.cgColor
        customView?.layer.opacity = 1
        customView?.layer.isOpaque = true
        customView?.isOpaque = true
        clockLabel?.isHidden = true
        clockLabel?.alpha = 0
        clockLabel?.layer.opacity = 0
        clockOverlayView?.isHidden = true
        clockOverlayView?.alpha = 0
        clockOverlayView?.layer.opacity = 0
        clockLabel?.backgroundColor = .clear
        clockLabel?.layer.backgroundColor = UIColor.clear.cgColor
        clockLabel?.isOpaque = false
        clockLabel?.layer.isOpaque = false
        pipSourceView?.backgroundColor = .clear
        pipSourceView?.layer.backgroundColor = UIColor.clear.cgColor
        pipSourceView?.isOpaque = false
        pipSourceView?.layer.isOpaque = false
        videoCallContentController?.view.backgroundColor = .clear
        videoCallContentController?.view.layer.backgroundColor = UIColor.clear.cgColor
        videoCallContentController?.view.isOpaque = false
        videoCallContentController?.view.layer.isOpaque = false
        textView.isHidden = false
        textView.alpha = 1
        textView.text = originalPiPText
        textView.backgroundColor = .black
        textView.layer.backgroundColor = UIColor.black.cgColor
        textView.layer.opacity = 1
        textView.layer.isOpaque = true
        textView.textColor = .white
        textView.isOpaque = true
        textView.setContentOffset(.zero, animated: false)
        textView.layoutIfNeeded()
        if isScrollingEnabled, !isContentExtremeModeEnabled, shouldPreviewPiPHeightLive {
            startDisplayLinks()
        } else {
            stopDisplayLinks()
        }
    }

    private func updateClockAppearance() {
        guard let clockLabel else { return }
        let shouldHideClockSurface = isPiPVisuallyHidden
        let fontSize = min(max(clampedPiPHeight * 0.74, 18), 58)
        clockLabel.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .black)
        clockLabel.textColor = shouldHideClockSurface ? .clear : .black
        clockLabel.backgroundColor = shouldHideClockSurface ? .clear : .white
        clockLabel.layer.backgroundColor = (shouldHideClockSurface ? UIColor.clear : UIColor.white).cgColor
        clockLabel.isHidden = true
        clockLabel.alpha = 0
        clockLabel.layer.opacity = 0
        clockLabel.layer.isOpaque = false
        clockLabel.isOpaque = false
        clockOverlayView?.configure(height: clampedPiPHeight, hidden: shouldHideClockSurface)
        customView?.backgroundColor = shouldHideClockSurface ? .clear : .white
        customView?.layer.backgroundColor = (shouldHideClockSurface ? UIColor.clear : UIColor.white).cgColor
        customView?.layer.opacity = shouldHideClockSurface ? 0 : 1
        customView?.layer.isOpaque = !shouldHideClockSurface
        customView?.isOpaque = !shouldHideClockSurface
        pipSourceView?.backgroundColor = .clear
        pipSourceView?.layer.backgroundColor = UIColor.clear.cgColor
        pipSourceView?.isOpaque = false
        pipSourceView?.layer.isOpaque = false
        videoCallContentController?.view.backgroundColor = .clear
        videoCallContentController?.view.layer.backgroundColor = UIColor.clear.cgColor
        videoCallContentController?.view.isOpaque = false
        videoCallContentController?.view.layer.isOpaque = false
        textView?.isHidden = true
        textView?.backgroundColor = .clear
        textView?.layer.backgroundColor = UIColor.clear.cgColor
        textView?.alpha = 0
        textView?.layer.opacity = 0
        textView?.layer.isOpaque = false
        textView?.textColor = .clear
        textView?.isOpaque = false
        updateClockOverlay(timestamp: CACurrentMediaTime(), forceNetworkSample: true)
    }

    private func toggleScrolling() {
        guard !isContentExtremeModeEnabled else {
            showMessage(L10n.text("内容极限模式下已固定为静态文本", "Text is fixed in content extreme mode."))
            return
        }
        guard !isClockModeEnabled else {
            AppDebugLogger.log("Ignore text scrolling toggle while clock mode is enabled")
            return
        }
        DiagnosticsRuntimeState.recordUserAction(isScrollingEnabled ? "关闭悬浮窗内容滚动" : "开启悬浮窗内容滚动")
        isScrollingEnabled.toggle()
        AppDebugLogger.log("PiP text scrolling changed, enabled=\(isScrollingEnabled)")
        if isScrollingEnabled, !shouldRenderClockMode {
            if pipController?.isPictureInPictureActive == true {
                startDisplayLinks()
            }
        } else {
            stopDisplayLinks()
        }
    }

    private func setClockMode(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "切换为时分秒悬浮窗" : "切换为文本悬浮窗")
        if isEnabled {
            guard isClockModeFeatureEnabled else {
                UserDefaults.standard.set(false, forKey: userDefaultsClockModeEnabledKey)
                isClockModeEnabled = false
                prefersTextScrolling = true
                UserDefaults.standard.set(true, forKey: userDefaultsScrollingEnabledKey)
                isScrollingEnabled = true
                updateHomeView()
                AppDebugLogger.log("Clock mode blocked below iOS 26 to avoid ProMotion fallback")
                return
            }
            isClockModeEnabled = true
            isScrollingEnabled = false
        } else {
            prefersTextScrolling = true
            UserDefaults.standard.set(true, forKey: userDefaultsScrollingEnabledKey)
            isClockModeEnabled = false
            isScrollingEnabled = true
        }
        AppDebugLogger.log("PiP clock mode changed, enabled=\(isClockModeEnabled)")
        videoCallContentController?.preferredContentSize = currentPiPSize
        updatePiPSourceGeometry()
        reloadPlayerItemIfNeededForCurrentSize()
        if pipController?.isPictureInPictureActive == true {
            configureRunningText()
            if !shouldRenderClockMode && isScrollingEnabled && !isContentExtremeModeEnabled {
                startDisplayLinks()
            }
        } else if !shouldRenderClockMode {
            stopClockTimer()
        }
        updateDiagnosticsPiPState()
        logPiPSurfaceDiagnostics("clock mode changed")
    }

    private func presentTutorial() {
        DiagnosticsRuntimeState.recordUserAction("打开使用教程")
        let tutorialController = TutorialTabBarController()
        let navigationController = UINavigationController(rootViewController: tutorialController)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    private func presentPiPHeightEditor() {
        DiagnosticsRuntimeState.recordUserAction("打开自定义悬浮窗高度")
        let editor = PiPHeightEditorViewController(
            height: clampedPiPHeight,
            range: currentMinimumPiPHeight...maxPiPHeight,
            step: currentPiPHeightStep,
            minimumHintText: shouldUsePlayerLayerPiPCompatibility
                ? L10n.text("当前为PlayerLayer新方案，最低1pt，调节精度为1pt", "PlayerLayer route: minimum 1 pt, step 1 pt.")
                : L10n.text("当前为默认老方案，最低0.1pt，调节精度为0.1pt", "Default route: minimum 0.1 pt, step 0.1 pt."),
            onChange: { [weak self] height in
                self?.previewPiPHeight(height)
            },
            onFinish: { [weak self] height in
                self?.commitPiPHeight(height)
            },
            onReset: { [weak self] in
                self?.commitPiPHeight(self?.compactPiPHeight ?? 44)
            }
        )
        editor.configureAdaptivePageSheet(preferredHeightRatio: 0.52)
        present(editor, animated: true)
    }

    private func previewPiPHeight(_ height: CGFloat) {
        isPreviewingPiPHeight = true
        pipHeight = clampedHeight(height)
        updateAutoHiddenOverheadState(reason: "预览高度 \(formattedHeight(clampedPiPHeight))")
        guard shouldPreviewPiPHeightLive else {
            return
        }
        UIView.performWithoutAnimation {
            videoCallContentController?.preferredContentSize = currentPiPSize
            updatePiPSourceGeometry()
            if textView != nil, shouldRenderClockMode {
                updateClockAppearance()
            }
        }
        if isPiPVisuallyHidden {
            configureRunningText()
        }
        if !isPiPVisuallyHidden {
            schedulePlayerItemReloadForCurrentSize()
        }
    }

    private func commitPiPHeight(_ height: CGFloat) {
        isPreviewingPiPHeight = false
        previewPiPHeight(height)
        isPreviewingPiPHeight = false
        isCompactPiPStyle = abs(clampedPiPHeight - compactPiPHeight) < 0.5
        if remembersPiPHeight {
            saveCurrentPiPHeightPreference()
        }
        if pipSourceView != nil {
            videoCallContentController?.preferredContentSize = currentPiPSize
            updatePiPSourceGeometry()
        }
        updateHomeView()
        if !isPiPVisuallyHidden {
            reloadPlayerItemIfNeededForCurrentSize()
        }
        if shouldUsePlayerLayerPiPCompatibility {
            updatePiPSourceGeometry()
        }
        if textView != nil {
            configureRunningText()
        }
        updateAutoHiddenOverheadState(reason: "提交高度 \(formattedHeight(clampedPiPHeight))")
        updateDiagnosticsPiPState()
        AppDebugLogger.log("PiP height committed: \(formattedHeight(clampedPiPHeight))")
        logPiPSurfaceDiagnostics("height committed")
    }

    private func formattedHeight(_ height: CGFloat) -> String {
        let roundedHeight = (height * 10).rounded() / 10
        if roundedHeight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(roundedHeight))pt"
        }
        return String(format: "%.1fpt", roundedHeight)
    }

    private func reloadPlayerItemIfNeededForCurrentSize() {
        pendingPlayerItemReloadWorkItem?.cancel()
        pendingPlayerItemReloadWorkItem = nil
        guard shouldPrepareBackingPlayerForPlayback else { return }
        guard let playerLayer else { return }
        guard let playerItem = makePlayerItem() else { return }
        observeLooping(for: playerItem)
        if let player = playerLayer.player {
            configureBackingPlayerForPiP(player)
            observePlaybackHealth(for: player, item: playerItem)
        }
        playerLayer.player?.replaceCurrentItem(with: playerItem)
        if shouldKeepPiPPlaybackAlive {
            updateBackingPlayerPlaybackForCurrentMode()
        } else {
            playerLayer.player?.pause()
        }
    }

    private func schedulePlayerItemReloadForCurrentSize() {
        guard shouldUsePlayerLayerPiPCompatibility, shouldPreviewPiPHeightLive else { return }
        pendingPlayerItemReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isPreviewingPiPHeight else { return }
            self.reloadPlayerItemIfNeededForCurrentSize()
        }
        pendingPlayerItemReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func togglePiPStyle() {
        DiagnosticsRuntimeState.recordUserAction("修改悬浮窗样式")
        let nextHeight = isCompactPiPStyle ? defaultPiPHeight : compactPiPHeight
        isCompactPiPStyle.toggle()
        commitPiPHeight(nextHeight)
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        present(alert, animated: true)
    }

    private func prepareSourceLayerForPiP() {
        view.layoutIfNeeded()
        centerPlayerLayer()
        let surfaceAlpha: Float = isPiPVisuallyHidden ? 0.01 : 1
        playerLayer?.opacity = shouldUsePlayerLayerPiPCompatibility ? surfaceAlpha : 0
        CATransaction.flush()
    }

    private func centerPlayerLayer() {
        guard let playerLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = centeredPreviewFrame()
        playerLayer.zPosition = -1
        playerLayer.removeAllAnimations()
        CATransaction.commit()
    }

    private func centeredPreviewFrame() -> CGRect {
        let bounds = view.bounds.isEmpty ? UIScreen.main.bounds : view.bounds
        let safeBounds = bounds.inset(by: view.safeAreaInsets)
        let origin = CGPoint(
            x: safeBounds.midX - currentPiPSize.width / 2,
            y: safeBounds.midY - currentPiPSize.height / 2
        )
        return CGRect(origin: origin, size: currentPiPSize)
    }

    @objc private func handleEnterForeground() {
        print("进入前台")
        if shouldResignForegroundAfterPiPClose {
            DiagnosticsRuntimeState.updateAppState("PiP关闭后阻止回前台")
            AppDebugLogger.log("Suppress foreground restore after PiP close: willEnterForeground")
            resignForegroundAfterPiPCloseIfNeeded(reason: "即将回前台")
            return
        }
        restoreForegroundWindowsHiddenForPiPCloseIfNeeded()
        DiagnosticsRuntimeState.updateAppState("即将回前台")
        recoverStalePiPTransitionIfNeeded(reason: "进入前台")
        validateOwnPiPState(reason: "进入前台")
        updateDiagnosticsPiPState()
        PowerUsageLogger.markForegroundStart()
        AppDebugLogger.log("Enter foreground, keepAlive=\(shouldKeepPiPPlaybackAlive)")
        if shouldKeepPiPPlaybackAlive {
            pipRuntimeDuration = pipRuntimeStartedAt.map { max(0, Date().timeIntervalSince($0)) } ?? pipRuntimeDuration
            updateHomeView()
        }
        if shouldRenderClockMode {
            startClockTimerIfNeeded()
        } else if isScrollingEnabled {
            startDisplayLinks()
        }
        updateAutoHiddenOverheadState(reason: "进入前台")
        if shouldKeepPiPPlaybackAlive {
            KeepAliveLogger.markEnterForeground()
        }
        endBackgroundTask()
        if needsLegacyPiPCompatibility && shouldKeepPiPPlaybackAlive {
            keepPlaybackAlive()
        } else {
            BackgroundTaskManager.shared.stopPlay()
            PowerUsageLogger.markKeepAliveStop()
            pauseBackingPlayerIfIdle()
        }
        updateDisplaySleepDiagnostics(reason: "进入前台", shouldLog: true)
        KeepAliveNotificationTester.presentPendingLocalNotificationAlertIfNeeded(from: self)
    }

    @objc private func handleDidBecomeActive() {
        guard shouldResignForegroundAfterPiPClose else { return }
        DiagnosticsRuntimeState.updateAppState("PiP关闭后阻止激活")
        AppDebugLogger.log("Suppress foreground restore after PiP close: didBecomeActive")
        resignForegroundAfterPiPCloseIfNeeded(reason: "已激活")
    }

    @objc private func handleEnterBackground() {
        print("进入后台")
        if shouldResignForegroundAfterPiPClose {
            shouldResignForegroundAfterPiPClose = false
        }
        DiagnosticsRuntimeState.updateAppState("后台")
        recoverStalePiPTransitionIfNeeded(reason: "进入后台")
        updateDiagnosticsPiPState()
        PowerUsageLogger.markBackgroundStart()
        AppDebugLogger.log("Enter background, keepAlive=\(shouldKeepPiPPlaybackAlive)")
        guard shouldKeepPiPPlaybackAlive else {
            BackgroundTaskManager.shared.stopPlay()
            PowerUsageLogger.markKeepAliveStop()
            pauseBackingPlayerIfIdle()
            endBackgroundTask()
            KeepAliveNotificationTester.cancelBackgroundInterruptionProbe(reason: "进入后台未保活")
            updateDisplaySleepDiagnostics(reason: "进入后台未保活", shouldLog: true)
            return
        }
        beginBackgroundTaskIfNeeded()
        KeepAliveLogger.markEnterBackground(mode: shouldUsePiPOnlyKeepAlive ? "PiP保活-低功耗" : "音频强保活")
        keepPlaybackAlive()
        if shouldRenderClockMode {
            stopDisplayLinks()
            startClockTimerIfNeeded()
        } else if isScrollingEnabled {
            startDisplayLinks()
        }
        updateAutoHiddenOverheadState(reason: "进入后台")
        updateDisplaySleepDiagnostics(reason: "进入后台保活", shouldLog: true)
    }

    @objc private func handleKeepAliveModeDidChange() {
        updateDiagnosticsPiPState()
        AppDebugLogger.log("KeepAlive mode changed, PiPOnly=\(shouldUsePiPOnlyKeepAlive), active=\(shouldKeepPiPPlaybackAlive)")
        updateHomeView()
        if shouldUsePiPOnlyKeepAlive {
            BackgroundTaskManager.shared.forceStopAndDeactivate()
            PowerUsageLogger.markKeepAliveStop()
            releaseMediaAudioSessionForPiPOnly(reason: "保活方案切换为低功耗")
        }
        guard shouldKeepPiPPlaybackAlive else { return }
        keepPlaybackAlive()
        KeepAliveLogger.markPiPStarted(mode: shouldUsePiPOnlyKeepAlive ? "PiP保活-低功耗" : "音频强保活")
        updateDisplaySleepDiagnostics(reason: "保活方案切换", shouldLog: true)
    }

    @objc private func handleLanguageDidChange() {
        updateHomeView()
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return
        }

        switch type {
        case .began:
            AppDebugLogger.log("Audio interruption began")
            KeepAliveNotificationTester.markAudioInterruptionBegan()
            BackgroundTaskManager.shared.stopPlay()
            PowerUsageLogger.markKeepAliveStop()
        case .ended:
            KeepAliveNotificationTester.markAudioInterruptionEnded()
            guard shouldKeepPiPPlaybackAlive else { return }
            AppDebugLogger.log("Audio interruption ended, resume keepAlive")
            keepPlaybackAlive()
        @unknown default:
            break
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        AppDebugLogger.log("Audio route changed: \(currentAudioRouteDescription), external=\(hasExternalAudioRoute)")
        guard shouldKeepPiPPlaybackAlive else { return }
        guard !shouldUsePiPOnlyKeepAlive else { return }
        keepPlaybackAlive()
    }

    private var hasExternalAudioRoute: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            switch output.portType {
            case .airPlay, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                return true
            default:
                return false
            }
        }
    }

    private var currentAudioRouteDescription: String {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ",")
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("画中画初始化后：\(UIApplication.shared.windows)")
        updateDiagnosticsPiPState()
        AppDebugLogger.log("PiP will start")
        prepareCustomViewForPiPStart()
        showPiPContentForOpening()
        scheduleLegacyCustomViewAttachRetries()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        pendingPiPStartWorkItem = nil
        pipStartTimeoutWorkItem = nil
        didRetryLegacyPiPStart = false
        cancelShortcutPiPStartRetry()
        wantsPiPActive = true
        updatePiPAutomaticStartPolicy()
        prepareCustomViewForPiPStart()
        configureRunningText()
        showPiPContentForOpening()
        scheduleLegacyCustomViewAttachRetries()
        finishPiPTransition()
        hasPrimedPlayerLayerPiPStart = false
        isOwnPiPConfirmedActive = true
        isPiPActiveForUI = true
        beginPiPRuntimeSession()
        startDisplayLinks()
        settlePlayerLayerPiPAfterStart()
        startPlayerLayerActivityDisplayLinkIfNeeded(reason: "PiP启动完成")
        if !shouldUsePlayerLayerPiPCompatibility {
            keepPlaybackAlive()
        }
        updateAutoHiddenOverheadState(reason: "PiP启动完成")
        PowerUsageLogger.markPiPStart()
        KeepAliveLogger.markPiPStarted(mode: shouldUsePiPOnlyKeepAlive ? "PiP保活-低功耗" : "音频强保活")
        updateDiagnosticsPiPState()
        updateDisplaySleepDiagnostics(reason: "PiP启动完成", shouldLog: true)
        hidePiPAfterShortcutStartIfNeeded()
        hidePiPForCurrentSuspendedStateIfNeeded(reason: "PiP启动后已吸附")
        performDeferredShortcutPiPStopIfNeeded(reason: "PiP启动完成")
        AppDebugLogger.log("PiP did start")
        print("画中画弹出后：\(UIApplication.shared.windows)")
    }

    private func scheduleSystemPiPDirectCloseGestureRetries(reason: String) {
        let delays: [TimeInterval] = [0, 0.08, 0.2, 0.5, 1.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.pipController?.isPictureInPictureActive == true else { return }
                self.installDirectCloseGestureForSystemPiPControls(reason: "\(reason) retry \(String(format: "%.2f", delay))")
            }
        }
    }

    private func scheduleLegacyCustomViewAttachRetries() {
        guard shouldUsePlayerLayerPiPCompatibility, shouldAttachCustomViewInPlayerLayerPiP else { return }
        let delays: [TimeInterval] = [0, 0.08, 0.2, 0.5, 1.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard
                    let self,
                    self.shouldUsePlayerLayerPiPCompatibility,
                    self.pipController?.isPictureInPictureActive == true
                else {
                    return
                }
                _ = self.attachCustomViewToPiPWindowIfAvailable(reason: "did start retry \(String(format: "%.2f", delay))")
                self.showPiPContentForOpening()
            }
        }
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pipExpectedActiveBeforeStop = wantsPiPActive
            && !isStoppingPiP
            && !isClosingPiPFromCustomContentTap
            && pipTransitionExpectedActive != false
        removeDirectCloseGestureForSystemPiPControls()
        cancelDelayedPiPHideCountdown(reason: "悬浮窗即将停止")
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        pipTransitionWatchdogWorkItem?.cancel()
        cancelShortcutPiPStartRetry()
        pendingPlayerLayerAudioReleaseWorkItem?.cancel()
        pendingPlayerLayerAudioReleaseWorkItem = nil
        pendingPiPStartWorkItem = nil
        pipStartTimeoutWorkItem = nil
        pendingPlayerItemReloadWorkItem?.cancel()
        pendingPlayerItemReloadWorkItem = nil
        hasPrimedPlayerLayerPiPStart = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        shouldHidePiPAfterShortcutStart = false
        cancelShortcutPiPStopRetry()
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        beginPiPTransition(expectedActive: false, reason: "will stop")
        if needsLegacyPiPCompatibility {
            isStoppingPiP = true
        } else {
            isPiPActiveForUI = false
        }
        stopDisplayLinks()
        stopClockTimer()
        stopPlayerLayerActivityDisplayLink(reason: "PiP即将停止")
        updateDiagnosticsPiPState()
        updateDisplaySleepDiagnostics(reason: "PiP即将停止", shouldLog: true)
        AppDebugLogger.log("PiP will stop")
        if shouldUseVideoCallOffscreenCloseAnimation {
            movePiPSourceViewOffscreenForClosing()
        } else {
            hidePiPContentForClosing()
            preparePiPVisualSurfacesForClosing()
            movePiPSourceViewOffscreenForClosing()
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        hidePiPContentForClosing()
        let expectedActiveBeforeStop = pipExpectedActiveBeforeStop ?? (
            wantsPiPActive
                && !isStoppingPiP
                && !isClosingPiPFromCustomContentTap
                && pipTransitionExpectedActive != false
        )
        pipExpectedActiveBeforeStop = nil
        let wasExpectedStop = !expectedActiveBeforeStop || isStoppingPiP || didRecoverStalePiPStop
        let stoppedMode = shouldUsePiPOnlyKeepAlive ? "PiP保活-低功耗" : "音频强保活"
        detachLegacyCustomViewIfNeeded()
        restorePiPVisualSurfaces()
        isOwnPiPConfirmedActive = false
        isPiPActiveForUI = false
        isStoppingPiP = false
        let shouldSuppressStopNotification = !wasExpectedStop
            && KeepAliveNotificationTester.shouldSuppressPiPStoppedNotification(reason: "悬浮窗异常停止")
        finishPiPTransition()
        finishPiPRuntimeSession()
        didRetryLegacyPiPStart = false
        didRecoverStalePiPStop = false
        hasPrimedPlayerLayerPiPStart = false
        isLegacyPlayerLayerFallbackActive = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        BackgroundTaskManager.shared.stopPlay()
        pauseBackingPlayerIfIdle()
        releaseTransientPlayerLayerPiPAudioSession(reason: "PiP停止完成")
        PowerUsageLogger.markPiPStop()
        PowerUsageLogger.markKeepAliveStop()
        KeepAliveLogger.markPiPStopped(reason: "PiP did stop")
        if !wasExpectedStop, !shouldSuppressStopNotification {
            KeepAliveNotificationTester.schedulePiPStoppedNotification(mode: stoppedMode, reason: "悬浮窗异常停止")
        }
        endBackgroundTask()
        updateDisplaySleepDiagnostics(reason: "PiP停止完成", shouldLog: true)
        updateDiagnosticsPiPState()
        AppDebugLogger.log("PiP did stop")
        resignForegroundAfterPiPCloseIfNeeded(reason: "PiP停止完成")
        isClosingPiPFromCustomContentTap = false
        if let pendingRoute = pendingPiPEngineRouteAfterStop {
        pendingPiPEngineRouteAfterStop = nil
            DispatchQueue.main.async { [weak self] in
                self?.applyPiPEngineRoute(pendingRoute)
            }
        }
        cancelShortcutPiPStopRetry()

    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        if isClosingPiPFromCustomContentTap || isStoppingPiP || pipTransitionExpectedActive == false {
            DiagnosticsRuntimeState.recordUserAction("自定义悬浮窗关闭PiP")
            AppDebugLogger.log("PiP restore UI requested during expected close; keep app out of foreground")
            wantsPiPActive = false
            isPiPActiveForUI = false
            shouldResignForegroundAfterPiPClose = false
            restoreForegroundWindowsHiddenForPiPCloseIfNeeded()
            updatePiPAutomaticStartPolicy()
            completionHandler(false)
            return
        }

        DiagnosticsRuntimeState.recordUserAction("系统悬浮窗控件还原App")
        AppDebugLogger.log("PiP restore UI requested by system control, suppress app foreground restore")
        wantsPiPActive = false
        isPiPActiveForUI = false
        updatePiPAutomaticStartPolicy()
        shouldResignForegroundAfterPiPClose = true
        resignForegroundAfterPiPCloseIfNeeded(reason: "系统请求恢复UI")
        completionHandler(false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        AppDebugLogger.log("PiP failed to start: \(error.localizedDescription)")
        if retryPiPStartWithLegacyControlsStyleFallbackIfNeeded(reason: "画中画启动失败：\(error.localizedDescription)") {
            return
        }
        if retryLegacyPiPStartIfNeeded(reason: "画中画启动失败：\(error.localizedDescription)") {
            return
        }
        if scheduleShortcutPiPStartRetry(reason: "画中画启动失败：\(error.localizedDescription)") {
            resetPiPStartStateAfterFailure()
            return
        }
        resetPiPStartStateAfterFailure()
        releaseTransientPlayerLayerPiPAudioSession(reason: "PiP启动失败")
        print(error)
    }

}

private extension UIColor {
    var debugRGBAString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "unresolved"
        }
        return String(format: "%.2f,%.2f,%.2f,%.2f", red, green, blue, alpha)
    }
}

private final class PiPHeightEditorViewController: UIViewController {
    private let range: ClosedRange<CGFloat>
    private let step: CGFloat
    private let minimumHintText: String
    private let onChange: (CGFloat) -> Void
    private let onFinish: (CGFloat) -> Void
    private let onReset: () -> Void

    private let inputField = UITextField()
    private let slider = UISlider()
    private let initialHeight: CGFloat
    private var isUpdatingInputFieldProgrammatically = false
    private var inputFieldWidthConstraint: Constraint?

    init(
        height: CGFloat,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        minimumHintText: String,
        onChange: @escaping (CGFloat) -> Void,
        onFinish: @escaping (CGFloat) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.range = range
        self.step = step
        self.minimumHintText = minimumHintText
        self.onChange = onChange
        self.onFinish = onFinish
        self.onReset = onReset
        self.initialHeight = height
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let contentView = applyLegacyGlassSheetBackground()

        let titleLabel = UILabel()
        titleLabel.text = L10n.text("自定义悬浮窗高度", "Custom PiP Height")
        titleLabel.font = .systemFont(ofSize: 24, weight: .black)
        titleLabel.textColor = .label

        inputField.keyboardType = .decimalPad
        inputField.textAlignment = .right
        inputField.font = .monospacedDigitSystemFont(ofSize: 18, weight: .black)
        inputField.textColor = .label
        inputField.tintColor = .systemBlue
        inputField.placeholder = "44"
        inputField.borderStyle = .none
        inputField.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.82)
        inputField.clearButtonMode = .whileEditing
        inputField.layer.cornerRadius = 12
        inputField.layer.cornerCurve = .continuous
        inputField.layer.borderWidth = 1
        inputField.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.28).cgColor
        inputField.clipsToBounds = true
        inputField.addTarget(self, action: #selector(handleHeightInputChange), for: .editingChanged)
        inputField.addTarget(self, action: #selector(handleHeightInputBegin), for: .editingDidBegin)
        inputField.addTarget(self, action: #selector(handleHeightInputEnd), for: [.editingDidEnd, .editingDidEndOnExit])
        inputField.inputAccessoryView = makeInputAccessoryToolbar()
        let inputLeftPadding = UIView(frame: CGRect(x: 0, y: 0, width: 4, height: 1))
        inputField.leftView = inputLeftPadding
        inputField.leftViewMode = .always

        let unitLabel = UILabel()
        unitLabel.text = "pt"
        unitLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .black)
        unitLabel.textColor = .secondaryLabel
        unitLabel.sizeToFit()
        let unitContainer = UIView(frame: CGRect(x: 0, y: 0, width: 26, height: 24))
        unitContainer.addSubview(unitLabel)
        unitLabel.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        inputField.rightView = unitContainer
        inputField.rightViewMode = .always
        inputField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        inputField.snp.makeConstraints { make in
            inputFieldWidthConstraint = make.width.equalTo(adaptiveInputFieldWidth(for: "44")).constraint
            make.height.equalTo(36)
        }

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, inputField])
        headerStack.axis = .horizontal
        headerStack.alignment = .firstBaseline
        headerStack.spacing = 12

        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(min(max(initialHeight, range.lowerBound), range.upperBound))
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = .tertiaryLabel
        slider.thumbTintColor = .systemBlue
        slider.isContinuous = true
        slider.addTarget(self, action: #selector(handleSliderChange), for: .valueChanged)
        slider.addTarget(self, action: #selector(handleSliderFinish), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let sliderContainer = makeSliderGlassContainer()
        sliderContainer.contentView.addSubview(slider)
        slider.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(18)
            make.centerY.equalToSuperview()
        }
        sliderContainer.snp.makeConstraints { make in
            make.height.equalTo(72)
        }

        let hintLabel = UILabel()
        hintLabel.text = [
            L10n.text("滑动时会实时调整已打开悬浮窗的高度", "Drag to adjust the active floating window height in real time."),
            minimumHintText,
            L10n.text("可根据自身喜好调节侧边吸附框大小", "Use it to tune the side dock size.")
        ].joined(separator: "\n")
        hintLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 0

        let resetButton = makeGlassButton(title: L10n.text("恢复默认值 44pt", "Reset to 44 pt"), isPrimary: false)
        resetButton.addTarget(self, action: #selector(handleReset), for: .touchUpInside)

        let doneButton = makeGlassButton(title: L10n.text("完成", "Done"), isPrimary: true)
        doneButton.addTarget(self, action: #selector(handleDone), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [resetButton, doneButton])
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 12
        buttonStack.snp.makeConstraints { make in
            make.height.equalTo(52)
        }

        let stackView = UIStackView(arrangedSubviews: [headerStack, sliderContainer, hintLabel, buttonStack])
        stackView.axis = .vertical
        stackView.spacing = 20
        contentView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.leading.trailing.equalTo(contentView.safeAreaLayoutGuide).inset(24)
            make.top.equalTo(contentView.safeAreaLayoutGuide).offset(28)
        }

        updateValueLabel()
        updateInputField()
    }

    private func makeSliderGlassContainer() -> UIVisualEffectView {
        let effectView: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            effect.tintColor = UIColor.systemBlue.withAlphaComponent(0.08)
            effectView = UIVisualEffectView(effect: effect)
        } else {
            effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        }

        effectView.layer.cornerRadius = 24
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        effectView.contentView.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.28)
        effectView.layer.borderWidth = 1
        effectView.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        return effectView
    }

    private func makeGlassButton(title: String, isPrimary: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: isPrimary ? .black : .bold)
        button.tintColor = isPrimary ? .white : .systemBlue
        button.backgroundColor = isPrimary
            ? UIColor.systemBlue.withAlphaComponent(0.88)
            : UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.74)
        button.layer.cornerRadius = 18
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = (isPrimary
            ? UIColor.white.withAlphaComponent(0.32)
            : UIColor.black.withAlphaComponent(0.46)
        ).cgColor
        button.clipsToBounds = true
        return button
    }

    private func makeInputAccessoryToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneItem = UIBarButtonItem(
            title: L10n.text("完成", "Done"),
            style: .done,
            target: self,
            action: #selector(handleInputAccessoryDone)
        )
        toolbar.items = [flexibleSpace, doneItem]
        return toolbar
    }

    @objc private func handleSliderChange() {
        syncSliderToCurrentHeight(animated: false)
        updateValueLabel()
        updateInputField()
        onChange(currentHeight)
    }

    @objc private func handleSliderFinish() {
        syncSliderToCurrentHeight(animated: true)
        updateValueLabel()
        updateInputField()
        onFinish(currentHeight)
    }

    @objc private func handleHeightInputBegin() {
        updateInputFieldAppearance(isEditing: true)
    }

    @objc private func handleHeightInputChange() {
        updateInputFieldWidth(for: inputField.text ?? "44")
        guard !isUpdatingInputFieldProgrammatically, let parsedHeight = parsedInputHeight else { return }
        applyInputHeight(parsedHeight, shouldCommit: false)
    }

    @objc private func handleHeightInputEnd() {
        updateInputFieldAppearance(isEditing: false)
        guard let parsedHeight = parsedInputHeight else {
            updateInputField()
            return
        }
        applyInputHeight(parsedHeight, shouldCommit: true)
    }

    @objc private func handleInputAccessoryDone() {
        handleHeightInputEnd()
        inputField.resignFirstResponder()
    }

    @objc private func handleReset() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let defaultHeight = CGFloat(44)
        slider.setValue(Float(defaultHeight), animated: true)
        updateValueLabel()
        updateInputField()
        onReset()
    }

    @objc private func handleDone() {
        if inputField.isFirstResponder {
            if let parsedHeight = parsedInputHeight {
                applyInputHeight(parsedHeight, shouldCommit: false)
                updateInputField()
            } else {
                updateInputField()
            }
            inputField.resignFirstResponder()
        }
        onFinish(currentHeight)
        dismiss(animated: true)
    }

    private var currentHeight: CGFloat {
        let rawHeight = CGFloat(slider.value)
        let snappedHeight = (rawHeight / step).rounded() * step
        return min(max(snappedHeight, range.lowerBound), range.upperBound)
    }

    private func syncSliderToCurrentHeight(animated: Bool) {
        let snappedValue = Float(currentHeight)
        guard abs(slider.value - snappedValue) > 0.0001 else { return }
        slider.setValue(snappedValue, animated: animated)
    }

    private var parsedInputHeight: CGFloat? {
        let text = (inputField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "pt", with: "", options: .caseInsensitive)
        guard !text.isEmpty, let value = Double(text) else { return nil }
        return CGFloat(value)
    }

    private func applyInputHeight(_ height: CGFloat, shouldCommit: Bool) {
        let snappedHeight = snappedClampedHeight(height)
        slider.setValue(Float(snappedHeight), animated: true)
        updateValueLabel()
        if shouldCommit {
            updateInputField()
            onFinish(currentHeight)
        } else {
            onChange(currentHeight)
        }
    }

    private func snappedClampedHeight(_ height: CGFloat) -> CGFloat {
        let snappedHeight = (height / step).rounded() * step
        return min(max(snappedHeight, range.lowerBound), range.upperBound)
    }

    private func formattedHeightValue(_ height: CGFloat) -> String {
        if height.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(height))"
        }
        return String(format: "%.1f", height)
    }

    private func updateInputField() {
        isUpdatingInputFieldProgrammatically = true
        let text = formattedHeightValue(currentHeight)
        inputField.text = text
        updateInputFieldWidth(for: text)
        isUpdatingInputFieldProgrammatically = false
    }

    private func adaptiveInputFieldWidth(for text: String) -> CGFloat {
        let displayText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "44" : text
        let font = inputField.font ?? .monospacedDigitSystemFont(ofSize: 18, weight: .black)
        let textWidth = (displayText as NSString).size(withAttributes: [.font: font]).width
        return min(max(ceil(textWidth) + 38, 62), 104)
    }

    private func updateInputFieldWidth(for text: String) {
        inputFieldWidthConstraint?.update(offset: adaptiveInputFieldWidth(for: text))
    }

    private func updateInputFieldAppearance(isEditing: Bool) {
        let borderColor = isEditing
            ? UIColor.systemBlue.withAlphaComponent(0.72)
            : UIColor.systemBlue.withAlphaComponent(0.28)
        inputField.layer.borderColor = borderColor.cgColor
        inputField.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(isEditing ? 0.96 : 0.82)
    }

    private func updateValueLabel() {
        guard !inputField.isFirstResponder else { return }
        updateInputField()
    }
}

private final class ClockOverlayView: UIView {
    private let timeLabel = UILabel()
    private let fpsLabel = UILabel()
    private let networkLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(time: String, fps: String, network: String) {
        if timeLabel.text != time {
            timeLabel.text = time
        }
        if fpsLabel.text != fps {
            fpsLabel.text = fps
        }
        if networkLabel.text != network {
            networkLabel.text = network
        }
    }

    func configure(height: CGFloat, hidden: Bool) {
        isHidden = hidden
        alpha = hidden ? 0 : 1
        layer.opacity = hidden ? 0 : 1
        backgroundColor = hidden ? .clear : .white
        layer.backgroundColor = (hidden ? UIColor.clear : UIColor.white).cgColor
        isOpaque = !hidden
        layer.isOpaque = !hidden

        let isCompactHeight = height < 40
        let shouldShowMetrics = !hidden && height >= 28
        let timeSize = isCompactHeight
            ? min(max(height * 0.56, 10), 22)
            : min(max(height * 0.58, 18), 40)
        let metricSize = isCompactHeight
            ? min(max(height * 0.22, 7), 11)
            : min(max(height * 0.3, 12), 18)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: timeSize, weight: .black)
	        fpsLabel.font = .monospacedDigitSystemFont(ofSize: metricSize, weight: .bold)
	        networkLabel.font = .monospacedDigitSystemFont(ofSize: metricSize, weight: .bold)

        let textColor: UIColor = hidden ? .clear : .black
	        timeLabel.textColor = textColor
        fpsLabel.textColor = shouldShowMetrics ? .darkGray : .clear
        networkLabel.textColor = shouldShowMetrics ? .darkGray : .clear
        fpsLabel.isHidden = !shouldShowMetrics
        networkLabel.isHidden = !shouldShowMetrics
    }

    private func setup() {
        backgroundColor = .white
        layer.backgroundColor = UIColor.white.cgColor
        isOpaque = true
        layer.isOpaque = true
        isUserInteractionEnabled = false
        clipsToBounds = true

        timeLabel.textAlignment = .center
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.45
        timeLabel.baselineAdjustment = .alignCenters
        timeLabel.textColor = .black

        fpsLabel.textAlignment = .left
        fpsLabel.adjustsFontSizeToFitWidth = true
        fpsLabel.minimumScaleFactor = 0.55
        fpsLabel.textColor = .darkGray

        networkLabel.textAlignment = .right
        networkLabel.adjustsFontSizeToFitWidth = true
        networkLabel.minimumScaleFactor = 0.45
        networkLabel.lineBreakMode = .byClipping
        networkLabel.textColor = .darkGray

        addSubview(timeLabel)
        addSubview(fpsLabel)
        addSubview(networkLabel)

        timeLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(2)
            make.centerY.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(0.74)
        }
        fpsLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().inset(2)
            make.width.equalToSuperview().multipliedBy(0.34)
        }
        networkLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().inset(2)
            make.leading.greaterThanOrEqualTo(fpsLabel.snp.trailing).offset(3)
        }
    }
}

private struct NetworkTrafficSample {
    let timestamp: Date
    let sentBytes: UInt64
    let receivedBytes: UInt64

    static func current() -> NetworkTrafficSample? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var sentBytes: UInt64 = 0
        var receivedBytes: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstInterface

        while let currentPointer = pointer {
            let interface = currentPointer.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if isUp,
               !isLoopback,
               let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                sentBytes += UInt64(networkData.ifi_obytes)
                receivedBytes += UInt64(networkData.ifi_ibytes)
            }

            pointer = interface.ifa_next
        }

        return NetworkTrafficSample(timestamp: Date(), sentBytes: sentBytes, receivedBytes: receivedBytes)
    }
}

private enum PlaceholderVideoFactory {
    static func makeBackingVideo(at url: URL, size: CGSize, text: String) throws {
        try? FileManager.default.removeItem(at: url)
        try makeVideo(at: url, size: size, text: text)
    }

    static func makeLongBackingVideo(at url: URL, size: CGSize, text: String) throws {
        try? FileManager.default.removeItem(at: url)
        try makeVideo(at: url, size: size, text: text, frameCount: 450, frameRate: 30)
    }

    private static func makeVideo(
        at url: URL,
        size: CGSize,
        text: String,
        frameCount: Int = 1,
        frameRate: Int32 = 10
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

	        let sourceAttributes: [String: Any] = [
	            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
	            kCVPixelBufferWidthKey as String: Int(size.width),
	            kCVPixelBufferHeightKey as String: Int(size.height)
	        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourceAttributes
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "PlaceholderVideoFactory", code: 1)
        }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let pixelBuffer = makePixelBuffer(size: size, text: text) else {
            throw NSError(domain: "PlaceholderVideoFactory", code: 2)
        }
        let frameDuration = CMTime(value: 1, timescale: frameRate)
        for frameIndex in 0..<max(frameCount, 1) {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        if let error = writer.error {
            throw error
		    }
	}

    private static func makePixelBuffer(size: CGSize, text: String) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
	            kCFAllocatorDefault,
	            Int(size.width),
	            Int(size.height),
	            kCVPixelFormatType_32BGRA,
	            attributes as CFDictionary,
	            &pixelBuffer
	        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width),
            height: Int(size.height),
	            bitsPerComponent: 8,
	            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
	            space: CGColorSpaceCreateDeviceRGB(),
	            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
	        ) else {
	            return nil
	        }

	        let pixelRect = CGRect(origin: .zero, size: size)
	        context.clear(pixelRect)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(pixelRect)
		        if !text.isEmpty {
		            context.saveGState()
		            context.translateBy(x: 0, y: size.height)
	            context.scaleBy(x: 1, y: -1)
	            UIGraphicsPushContext(context)
	            let paragraphStyle = NSMutableParagraphStyle()
	            paragraphStyle.alignment = .center
	            paragraphStyle.lineBreakMode = .byTruncatingTail
	            let fontSize = min(max(size.height * 0.48, 18), 96)
	            let attributes: [NSAttributedString.Key: Any] = [
	                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
	                .foregroundColor: UIColor.black,
	                .paragraphStyle: paragraphStyle
	            ]
	            let textHeight = ceil(fontSize * 1.24)
	            let horizontalInset = max(16, size.width * 0.05)
	            let rect = CGRect(
	                x: horizontalInset,
	                y: max(0, (size.height - textHeight) / 2),
	                width: max(1, size.width - horizontalInset * 2),
	                height: textHeight
	            )
	            (text as NSString).draw(in: rect, withAttributes: attributes)
	            UIGraphicsPopContext()
	            context.restoreGState()
		        }
		        return pixelBuffer
		    }

		}
