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

enum AppAppearancePreference {
    private static let darkModeForcedKey = "pip.home.darkModeForced"

    static var isDarkModeForced: Bool {
        get { UserDefaults.standard.bool(forKey: darkModeForcedKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: darkModeForcedKey)
            applyCurrentPreference()
        }
    }

    static var preferredStyle: UIUserInterfaceStyle {
        isDarkModeForced ? .dark : .unspecified
    }

    static func apply(to window: UIWindow?) {
        window?.overrideUserInterfaceStyle = preferredStyle
        window?.rootViewController?.overrideUserInterfaceStyle = preferredStyle
    }

    static func applyCurrentPreference() {
        UIView.performWithoutAnimation {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .forEach { apply(to: $0) }
        }
    }
}

class ViewController: UIViewController, AVPictureInPictureControllerDelegate {

    private var playerLayer: AVPlayerLayer!
    private var pipController: AVPictureInPictureController!
    private var pipSourceView: UIView!
    private var pipSourceWidthConstraint: Constraint?
    private var pipSourceHeightConstraint: Constraint?
    private var legacyCustomViewWidthConstraint: Constraint?
    private var legacyCustomViewHeightConstraint: Constraint?
    private var customView: UIView!
    private var textView: UITextView!
    private var clockLabel: UILabel!
    private var clockOverlayView: ClockOverlayView!
    private var videoCallContentController: UIViewController?
    private var hostingController: UIHostingController<PiPHomeView>?
    private var scrollDisplayLink: CADisplayLink?
    private var clockDisplayLink: CADisplayLink?
    private var lastScrollTimestamp: CFTimeInterval?
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
    private var pipTransitionStartedAt: Date?
    private var pipTransitionReason = "未知"
    private var pipTransitionExpectedActive: Bool?
    private var didRecoverStalePiPStop = false
    private var pendingShortcutPiPStartRetry: DispatchWorkItem?
    private var shortcutPiPStartRetryRemaining = 0
    private var shouldHidePiPAfterShortcutStart = false
    private var playerStallObserver: NSObjectProtocol?
    private var playerPauseObserver: NSKeyValueObservation?
    private var isPreviewingPiPHeight = false
    private var didRetryLegacyPiPStart = false
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
    private var remembersPiPHeight = false {
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
            if !isLoadingHomePreferences {
                AppAppearancePreference.isDarkModeForced = isDarkModeForced
            }
            updateHomeView()
        }
    }
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
    private var keepsPiPStatusInfoPersistent = false {
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
    private let maxPiPHeight: CGFloat = 220
    private let userDefaultsScrollingEnabledKey = "pip.home.scrollingEnabled"
    private let userDefaultsRememberPiPHeightKey = "pip.home.rememberPiPHeight"
    private let userDefaultsClockModeEnabledKey = "pip.home.clockModeEnabled"
    private let userDefaultsClockModeDefaultMigrationKey = "pip.home.clockModeDefaultMigration.v1"
    private let userDefaultsPiPHeightKey = "pip.home.rememberedPiPHeight"
    private let userDefaultsPiPRuntimeStartedAtKey = "pip.home.runtimeStartedAt"
    private let userDefaultsPiPRuntimeDurationKey = "pip.home.runtimeDuration"
    private let userDefaultsPiPRuntimeWasActiveKey = "pip.home.runtimeWasActive"
    private let userDefaultsPiPRuntimeStoppedAtTextKey = "pip.home.runtimeStoppedAtText"
    private let userDefaultsPiPStatusInfoPersistentKey = "pip.home.pipStatusInfoPersistent"
    static let userDefaultsIOS26AudioKeepAliveKey = "pip.keepAlive.iOS26AudioEnabled"
    static let userDefaultsIOS26PiPOnlyKeepAliveKey = "pip.keepAlive.iOS26PiPOnlyEnabled"
    static let iOS26KeepAliveModeDidChangeNotification = Notification.Name("pip.iOS26KeepAliveModeDidChange")
    private var currentPiPSize: CGSize {
        CGSize(width: currentPiPWidth, height: clampedPiPHeight)
    }
    private var currentPiPWidth: CGFloat {
        shouldRenderClockMode ? clockPiPWidth : textPiPWidth
    }
    private var clampedPiPHeight: CGFloat {
        min(max(pipHeight, minPiPHeight), maxPiPHeight)
    }
    private var pipHeightForDisplay: String {
        formattedHeight(clampedPiPHeight)
    }
    private var pipStatusTitle: String {
        guard isPiPRuntimeActive else {
            return "待启用"
        }
        return clampedPiPHeight <= 0.15 ? "运行中-已隐藏" : "运行中"
    }

    private var isPiPVisuallyHidden: Bool {
        clampedPiPHeight <= 0.15
    }
    private var isPiPSuspendedAtSide: Bool {
        guard pipController?.isPictureInPictureActive == true else { return false }
        return pipController.isPictureInPictureSuspended
    }
    private var shouldRenderClockMode: Bool {
        isClockModeFeatureEnabled && isClockModeEnabled && !isPiPVisuallyHidden
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
        // BETA5_ANCHOR_PLAYER_LAYER_PIP_TIME_MODE:
        // playerLayer 承载实验已验证：高度调整慢、PiP 内容挂载易黑屏、0.1pt 隐藏会触发关闭。
        // 因此默认回到 beta4 的 VideoCall contentSource 主线，保留实验代码但不启用。
        return false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        print("画中画初始化前：\(UIApplication.shared.windows)")
        DiagnosticsRuntimeState.updateCurrentPage("悬浮窗")
        AppDebugLogger.log("Home viewDidLoad")
        PowerUsageLogger.markLaunch()
        KeepAliveNotificationTester.sanitizeOnLaunch()
        let keepAliveInterruptionNotice = KeepAliveLogger.markAppLaunch()

        loadHomePreferences()
        loadPiPRuntimeState()
        setupSwiftUI()
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeepAliveModeDidChange), name: Self.iOS26KeepAliveModeDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleClockDisplayLinkPreferenceDidChange), name: ClockDisplayLinkPreference.didChangeNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DiagnosticsRuntimeState.updateCurrentPage("悬浮窗")
        updateDiagnosticsPiPState()
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
        NotificationCenter.default.removeObserver(self)
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        pipTransitionWatchdogWorkItem?.cancel()
        pendingShortcutPiPStartRetry?.cancel()
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
            isPiPStoppedNotificationEnabled: isPiPStoppedNotificationEnabled,
            isBackgroundInterruptionNotificationEnabled: isBackgroundInterruptionNotificationEnabled,
            keepAliveNotificationFrequency: keepAliveNotificationFrequency,
            keepsPiPStatusInfoPersistent: keepsPiPStatusInfoPersistent,
            remembersPiPHeight: remembersPiPHeight,
            isSettingsExpanded: isSettingsExpanded,
            onTogglePiP: { [weak self] in self?.togglePiP() },
            onShowTutorial: { [weak self] in self?.presentTutorial() },
            onToggleStyle: { [weak self] in self?.togglePiPStyle() },
            onCustomizeHeight: { [weak self] in self?.presentPiPHeightEditor() },
            onToggleScrolling: { [weak self] in self?.toggleScrolling() },
            onSetClockMode: { [weak self] newValue in self?.setClockMode(newValue) },
            onSetDarkModeForced: { [weak self] newValue in self?.setDarkModeForced(newValue) },
            onSetPiPStoppedNotificationEnabled: { [weak self] newValue in self?.setPiPStoppedNotificationEnabled(newValue) },
            onSetBackgroundInterruptionNotificationEnabled: { [weak self] newValue in self?.setBackgroundInterruptionNotificationEnabled(newValue) },
            onSetKeepAliveNotificationFrequency: { [weak self] frequency in self?.setKeepAliveNotificationFrequency(frequency) },
            onSetPiPStatusInfoPersistent: { [weak self] newValue in self?.setPiPStatusInfoPersistent(newValue) },
            onToggleSettings: { [weak self] in self?.toggleSettingsPanel() },
            onDismissSettings: { [weak self] in self?.dismissSettingsPanel() },
            onSetRememberPiPHeight: { [weak self] newValue in self?.setRememberPiPHeight(newValue) }
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
            isPiPStoppedNotificationEnabled: isPiPStoppedNotificationEnabled,
            isBackgroundInterruptionNotificationEnabled: isBackgroundInterruptionNotificationEnabled,
            keepAliveNotificationFrequency: keepAliveNotificationFrequency,
            keepsPiPStatusInfoPersistent: keepsPiPStatusInfoPersistent,
            remembersPiPHeight: remembersPiPHeight,
            isSettingsExpanded: isSettingsExpanded,
            onTogglePiP: { [weak self] in self?.togglePiP() },
            onShowTutorial: { [weak self] in self?.presentTutorial() },
            onToggleStyle: { [weak self] in self?.togglePiPStyle() },
            onCustomizeHeight: { [weak self] in self?.presentPiPHeightEditor() },
            onToggleScrolling: { [weak self] in self?.toggleScrolling() },
            onSetClockMode: { [weak self] newValue in self?.setClockMode(newValue) },
            onSetDarkModeForced: { [weak self] newValue in self?.setDarkModeForced(newValue) },
            onSetPiPStoppedNotificationEnabled: { [weak self] newValue in self?.setPiPStoppedNotificationEnabled(newValue) },
            onSetBackgroundInterruptionNotificationEnabled: { [weak self] newValue in self?.setBackgroundInterruptionNotificationEnabled(newValue) },
            onSetKeepAliveNotificationFrequency: { [weak self] frequency in self?.setKeepAliveNotificationFrequency(frequency) },
            onSetPiPStatusInfoPersistent: { [weak self] newValue in self?.setPiPStatusInfoPersistent(newValue) },
            onToggleSettings: { [weak self] in self?.toggleSettingsPanel() },
            onDismissSettings: { [weak self] in self?.dismissSettingsPanel() },
            onSetRememberPiPHeight: { [weak self] newValue in self?.setRememberPiPHeight(newValue) }
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
                UserDefaults.standard.set(true, forKey: userDefaultsClockModeEnabledKey)
                isClockModeEnabled = true
            } else {
                isClockModeEnabled = UserDefaults.standard.object(forKey: userDefaultsClockModeEnabledKey) == nil
                    ? true
                    : UserDefaults.standard.bool(forKey: userDefaultsClockModeEnabledKey)
            }
        } else {
            isClockModeEnabled = false
            UserDefaults.standard.set(false, forKey: userDefaultsClockModeEnabledKey)
        }
        isScrollingEnabled = isClockModeEnabled ? false : prefersTextScrolling
        isDarkModeForced = AppAppearancePreference.isDarkModeForced
        isPiPStoppedNotificationEnabled = KeepAliveNotificationTester.isPiPStoppedNotificationEnabled
        isBackgroundInterruptionNotificationEnabled = KeepAliveNotificationTester.isBackgroundProbeEnabled
        keepAliveNotificationFrequency = KeepAliveNotificationTester.probeFrequency
        keepsPiPStatusInfoPersistent = UserDefaults.standard.bool(forKey: userDefaultsPiPStatusInfoPersistentKey)
        isPiPStatusInfoVisible = keepsPiPStatusInfoPersistent

        remembersPiPHeight = UserDefaults.standard.bool(forKey: userDefaultsRememberPiPHeightKey)
        if remembersPiPHeight,
           UserDefaults.standard.object(forKey: userDefaultsPiPHeightKey) != nil {
            pipHeight = clampedHeight(CGFloat(UserDefaults.standard.double(forKey: userDefaultsPiPHeightKey)))
            isCompactPiPStyle = abs(clampedPiPHeight - compactPiPHeight) < 0.5
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
        return storedText.isEmpty ? "暂无" : storedText
    }

    private func setRememberPiPHeight(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启记忆悬浮窗高度" : "关闭记忆悬浮窗高度")
        remembersPiPHeight = isEnabled
    }

    private func setDarkModeForced(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启深色模式" : "关闭深色模式")
        UIView.performWithoutAnimation {
            isDarkModeForced = isEnabled
            view.layoutIfNeeded()
        }
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

    private func setBackgroundInterruptionNotificationEnabled(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启后台中断提醒beta" : "关闭后台中断提醒beta")
        if isEnabled {
            KeepAliveNotificationTester.prepareForBackgroundProbeToggle(from: self) { [weak self] granted in
                guard let self else { return }
                self.isBackgroundInterruptionNotificationEnabled = granted
            }
        } else {
            isBackgroundInterruptionNotificationEnabled = false
            KeepAliveNotificationTester.cancelBackgroundProbeNotifications(reason: "首页关闭后台中断提醒beta")
        }
    }

    private func setKeepAliveNotificationFrequency(_ frequency: KeepAliveNotificationProbeFrequency) {
        DiagnosticsRuntimeState.recordUserAction("切换后台中断提醒频率：\(frequency.title)")
        keepAliveNotificationFrequency = frequency
    }

    private func setPiPStatusInfoPersistent(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启悬浮窗状态常驻" : "关闭悬浮窗状态常驻")
        keepsPiPStatusInfoPersistent = isEnabled
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
        min(max(height, minPiPHeight), maxPiPHeight)
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
        updateDiagnosticsPiPState()
        updateHomeView()
    }

    private func finishPiPRuntimeSession() {
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
            "render=\(shouldRenderClockMode ? "clock" : "text")",
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
            "source=\(viewDiagnosticsText(pipSourceView))",
            "content=\(viewDiagnosticsText(contentView))",
            "custom=\(viewDiagnosticsText(customView))",
            "text=\(viewDiagnosticsText(textView))",
            "clock=\(viewDiagnosticsText(clockLabel))",
            "playerLayer=\(layerDiagnosticsText(playerLayer))"
        ]
        return "surface{\(parts.joined(separator: ";"))}"
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
        configurePiPAudioSession()
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
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
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
        playerLayer.opacity = 0
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.needsDisplayOnBoundsChange = false

        let player = AVPlayer(playerItem: playerItem)
        configureBackingPlayerForPiP(player)
        player.actionAtItemEnd = .none
        player.isMuted = true
        player.volume = 0
        player.allowsExternalPlayback = false
        playerLayer.player = player
        observeLooping(for: playerItem)
        observePlaybackHealth(for: player, item: playerItem)

        view.layer.addSublayer(playerLayer)
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
        } else {
            guard let playerLayer else { return }
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
        }
        guard pipController != nil else { return }
        pipController.delegate = self
        pipController.setValue(1, forKey: "controlsStyle")
        pipController.requiresLinearPlayback = true
        updatePiPAutomaticStartPolicy()
    }

    private func setupCustomView() {
        customView = UIView()
        customView.backgroundColor = .white
        customView.isOpaque = true
        customView.isUserInteractionEnabled = false
        customView.clipsToBounds = true

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
        """
        悬浮窗运行中
        悬浮窗运行中
        悬浮窗运行中
        悬浮窗运行中
        悬浮窗运行中
        悬浮窗运行中
        悬浮窗运行中
        悬浮窗运行中
        悬浮窗运行中
        悬浮窗运行中
        """
    }

    private func togglePiP() {
        DiagnosticsRuntimeState.recordUserAction((pipController?.isPictureInPictureActive ?? false) ? "点击关闭悬浮窗" : "点击开启悬浮窗")
        updateDiagnosticsPiPState()
        AppDebugLogger.log("Toggle PiP tapped, active=\(pipController?.isPictureInPictureActive ?? false), prepared=\(hasPreparedPiPInfrastructure), wants=\(wantsPiPActive)")
        if pipController == nil, !preparePiPInfrastructureIfNeeded() {
            isPiPActiveForUI = false
            showMessage("当前环境不支持悬浮窗")
            return
        }

        guard let pipController else {
            isPiPActiveForUI = false
            showMessage("当前环境不支持悬浮窗")
            return
        }

        recoverStalePiPTransitionIfNeeded(reason: "用户点击悬浮窗按钮")

        if needsLegacyPiPCompatibility {
            guard !isPiPTransitioning else { return }
        }

        if pipController.isPictureInPictureActive {
            AppDebugLogger.log("Stop PiP requested")
            wantsPiPActive = false
            updatePiPAutomaticStartPolicy()
            pendingPiPStartWorkItem?.cancel()
            pipStartTimeoutWorkItem?.cancel()
            isPiPActiveForUI = false
            stopPiPSmoothly()
        } else {
            AppDebugLogger.log("Start PiP requested")
            wantsPiPActive = true
            updatePiPAutomaticStartPolicy()
            didRetryLegacyPiPStart = false
            isPiPActiveForUI = true
            configureRunningText()
            startPiPSmoothly()
        }
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

    private func startPiPFromShortcut(shouldHideAfterStart: Bool) {
        // BETA5_ANCHOR_SHORTCUT_START_AND_HIDE:
        // 快捷指令“打开悬浮窗”只负责打开；“打开并隐藏悬浮窗”在 PiP 真正启动后缩小到 0.1pt。
        if pipController == nil, !preparePiPInfrastructureIfNeeded() {
            isPiPActiveForUI = false
            shouldHidePiPAfterShortcutStart = false
            showMessage("当前环境不支持悬浮窗")
            return
        }

        guard let pipController else {
            isPiPActiveForUI = false
            shouldHidePiPAfterShortcutStart = false
            showMessage("当前环境不支持悬浮窗")
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
                hidePiPFromShortcut()
            } else {
                showMessage("悬浮窗已开启")
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
            showMessage("请先开启悬浮窗并吸附到侧边")
            return
        }

        commitPiPHeight(minPiPHeight)
        showMessage("已隐藏悬浮窗")
    }

    private func hidePiPAfterShortcutStartIfNeeded() {
        guard shouldHidePiPAfterShortcutStart else { return }
        shouldHidePiPAfterShortcutStart = false
        commitPiPHeight(minPiPHeight)
        showMessage("已打开并隐藏悬浮窗")
    }

    private func shortcutActionTitle(_ action: PiPShortcutAction) -> String {
        switch action {
        case .startFloatingWindow:
            return "打开悬浮窗"
        case .hideFloatingWindow:
            return "隐藏悬浮窗"
        case .startAndHideFloatingWindow:
            return "打开并隐藏悬浮窗"
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

    private func restartPlaybackFromBeginning() {
        guard let player = playerLayer?.player else { return }
        player.seek(to: .zero) { _ in
            guard self.shouldKeepPiPPlaybackAlive else {
                player.pause()
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
        if shouldUsePiPOnlyKeepAlive {
            BackgroundTaskManager.shared.forceStopAndDeactivate()
            PowerUsageLogger.markKeepAliveStop()
            KeepAliveLogger.heartbeat()
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
        !shouldUsePiPOnlyKeepAlive || shouldPrepareBackingPlayerForPlayback
    }

    private func updateBackingPlayerPlaybackForCurrentMode() {
        guard let player = playerLayer?.player else { return }
        configureBackingPlayerForPiP(player)
        if shouldPlayBackingPlayerForKeepAlive {
            player.play()
        } else {
            player.pause()
        }
        updateDisplaySleepDiagnostics()
    }

    private func configurePiPAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
        }
    }

    private var shouldKeepPiPPlaybackAlive: Bool {
        wantsPiPActive && (isOwnPiPConfirmedActive || isPiPTransitioning)
    }

    private var shouldUsePiPOnlyKeepAlive: Bool {
        if UserDefaults.standard.object(forKey: Self.userDefaultsIOS26AudioKeepAliveKey) == nil {
            if let legacyPiPOnly = UserDefaults.standard.object(forKey: Self.userDefaultsIOS26PiPOnlyKeepAliveKey) as? Bool {
                UserDefaults.standard.set(!legacyPiPOnly, forKey: Self.userDefaultsIOS26AudioKeepAliveKey)
            } else {
                UserDefaults.standard.set(false, forKey: Self.userDefaultsIOS26AudioKeepAliveKey)
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
        pendingPiPStartWorkItem = nil
        pipStartTimeoutWorkItem = nil
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
            if isScrollingEnabled, !shouldRenderClockMode, !isPiPVisuallyHidden {
                startDisplayLinks()
            }
            keepPlaybackAlive()
            KeepAliveLogger.heartbeat()
        } else {
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
        isOwnPiPConfirmedActive || isPiPTransitioning
    }

    private func handleOwnPiPInvalidated(reason: String) {
        let hadOwnSession = isOwnPiPConfirmedActive || pipRuntimeStartedAt != nil
        wantsPiPActive = false
        isOwnPiPConfirmedActive = false
        isPiPActiveForUI = false
        isStoppingPiP = false
        didRetryLegacyPiPStart = false
        didRecoverStalePiPStop = false
        updatePiPAutomaticStartPolicy()
        detachLegacyCustomViewIfNeeded()
        stopDisplayLinks()
        stopClockTimer()
        BackgroundTaskManager.shared.stopPlay()
        PowerUsageLogger.markKeepAliveStop()
        pauseBackingPlayerIfIdle()
        endBackgroundTask()
        if pipRuntimeStartedAt != nil || pipRuntimeDuration > 0 {
            finishPiPRuntimeSession()
        }
        if hadOwnSession {
            KeepAliveLogger.markPiPStopped(reason: reason)
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
        requiresPlayerLayerForPiP
    }

    private func makePlayerItem() -> AVPlayerItem? {
        let backingVideoSize = CGSize(
            width: max(currentPiPSize.width, 1),
            height: max(currentPiPSize.height, 1)
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pip-transparent-alpha-60fps-v1-\(Int(backingVideoSize.width))x\(Int(backingVideoSize.height)).mov")
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try PlaceholderVideoFactory.makeBackingVideo(at: url, size: backingVideoSize)
            } catch {
                print(error)
                AppDebugLogger.log("Placeholder video failed: \(error.localizedDescription)")
                return nil
            }
        }
        return AVPlayerItem(asset: AVAsset(url: url))
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
        guard isScrollingEnabled, !shouldRenderClockMode, !isPiPVisuallyHidden else { return }
        guard scrollDisplayLink == nil else { return }

        let scrollDisplayLink = CADisplayLink(target: self, selector: #selector(updateScrollingText(_:)))
        // BETA2 ANCHOR: 滚动文本驱动避开 tracking mode，降低桌面/列表滑动时的额外调度。
        scrollDisplayLink.add(to: .main, forMode: .default)
        lastScrollTimestamp = nil
        self.scrollDisplayLink = scrollDisplayLink
    }

    private func stopDisplayLinks() {
        scrollDisplayLink?.invalidate()
        scrollDisplayLink = nil
        lastScrollTimestamp = nil
    }

    private func startClockTimerIfNeeded() {
        guard isClockModeEnabled else { return }
        stopClockTimer()
        resetClockMetrics()
        updateClockOverlay(timestamp: CACurrentMediaTime(), forceNetworkSample: true)
        let displayLink = CADisplayLink(target: self, selector: #selector(updateClockDisplay(_:)))
        configureForClockRefreshRate(displayLink)
        // Avoid tracking mode so the PiP clock does not compete with scroll gestures.
        displayLink.add(to: .main, forMode: .default)
        clockDisplayLink = displayLink
    }

    private func stopClockTimer() {
        clockDisplayLink?.invalidate()
        clockDisplayLink = nil
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
    }

    private func resetClockMetrics() {
        lastClockTimestamp = nil
        lastClockNetworkTimestamp = nil
        clockFrameCount = 0
        pendingMeasuredPiPFPS = nil
        pendingMeasuredPiPFPSCount = 0
        pendingMeasuredPiPFPSStartedAt = nil
        measuredPiPFPS = 0
        lastNetworkSample = NetworkTrafficSample.current()
        currentNetworkSpeedText = "↑0B ↓0B"
        lastClockOverlayTimeText = ""
        lastClockOverlayFPSText = ""
        lastClockOverlayNetworkText = ""
        lastClockRenderTick = -1
        lastBackgroundClockDiagnosticsTimestamp = nil
    }

    @objc private func updateScrollingText(_ displayLink: CADisplayLink) {
        guard let textView, isScrollingEnabled, !shouldRenderClockMode, !isPiPVisuallyHidden else {
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
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: target,
                maximum: target,
                preferred: ClockDisplayLinkPreference.preferredFrameRateValue(target: target)
            )
        } else {
            displayLink.preferredFramesPerSecond = targetFramesPerSecond
        }
    }

    @objc private func handleClockDisplayLinkPreferenceDidChange() {
        if let clockDisplayLink {
            configureForClockRefreshRate(clockDisplayLink)
        }
        AppDebugLogger.log("时间悬浮窗强拉120调试开关：\(ClockDisplayLinkPreference.forcesTargetFrameRate ? "开启" : "关闭")")
    }

    @objc private func updateClockLabel() {
        updateClockOverlay(timestamp: CACurrentMediaTime(), forceNetworkSample: false)
    }

    @objc private func updateClockDisplay(_ displayLink: CADisplayLink) {
        guard shouldRenderClockMode, !isPiPVisuallyHidden else {
            stopClockTimer()
            return
        }
        logBackgroundClockDiagnosticsIfNeeded(displayLink)
        updateMeasuredFPS(from: displayLink)
        updateClockOverlay(timestamp: displayLink.timestamp, forceNetworkSample: false)
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

        let confirmation = fpsConfirmationRequirement(from: measuredPiPFPS, to: normalizedFPS)
        let pendingDuration = displayLink.timestamp - (pendingMeasuredPiPFPSStartedAt ?? displayLink.timestamp)
        if pendingMeasuredPiPFPSCount >= confirmation.count && pendingDuration >= confirmation.duration {
            measuredPiPFPS = normalizedFPS
            pendingMeasuredPiPFPS = nil
            pendingMeasuredPiPFPSCount = 0
            pendingMeasuredPiPFPSStartedAt = nil
        }
    }

    private func fpsConfirmationRequirement(from currentFPS: Int, to candidateFPS: Int) -> (count: Int, duration: CFTimeInterval) {
        guard candidateFPS > currentFPS else { return (3, 0) }
        if candidateFPS >= 120 {
            if currentFPS <= 60 {
                return (8, 0.18)
            }
            return (24, 0.9)
        }
        return (5, 0.12)
    }

    private func updateClockOverlay(timestamp: CFTimeInterval, forceNetworkSample: Bool) {
        guard let clockOverlayView else { return }
        updateClockMetrics(timestamp: timestamp, forceNetworkSample: forceNetworkSample)
        let now = Date()
        let renderTick = Int((now.timeIntervalSince1970 * 10).rounded(.down))
        let fpsText = "\(measuredPiPFPS)Hz"
        let networkText = currentNetworkSpeedText
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
        keepPlaybackAlive()
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
            self.keepPlaybackAlive()
            guard self.isPlayerReadyForPiP && pipController.isPictureInPicturePossible else {
                if attempt < self.maximumPiPStartAttempts {
                    self.requestLegacyPlayerLayerPiPStartWhenReady(attempt: attempt + 1)
                } else {
                    self.resetPiPStartStateAfterFailure()
                    let message = "PlayerLayer PiP暂时不可启动：possible=\(pipController.isPictureInPicturePossible), playerReady=\(self.isPlayerReadyForPiP)"
                    AppDebugLogger.log(message)
                    print(message)
                }
                return
            }
            pipController.startPictureInPicture()
        }
        pendingPiPStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + piPStartRetryDelay(for: attempt), execute: workItem)
    }

    private func restoreMinimumRememberedHeightIfNeeded() {
        guard clampedPiPHeight <= minPiPHeight + 0.01 else { return }
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
        beginPiPTransition(expectedActive: false, reason: "stop smooth")
        isStoppingPiP = true
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        stopDisplayLinks()
        stopClockTimer()
        hidePiPContentForClosing()
        preparePiPVisualSurfacesForClosing()
        movePiPSourceViewOffscreenForClosing()
        pipController.stopPictureInPicture()
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
        shouldUsePlayerLayerPiPCompatibility ? 3.0 : 8.0
    }

    private func resetPiPStartStateAfterFailure() {
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        pipTransitionWatchdogWorkItem?.cancel()
        pendingPiPStartWorkItem = nil
        pipStartTimeoutWorkItem = nil
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
            endBackgroundTask()
        }
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
            attachCustomViewToPiPWindowIfAvailable(reason: "prepare start")
        } else {
            attachCustomViewToPiPContent()
        }
    }

    private func attachCustomViewToKeyWindow() {
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
        UIView.performWithoutAnimation {
            textView.alpha = 1
            clockLabel?.alpha = shouldRenderClockMode ? 1 : 0
            customView.alpha = 1
            customView.layer.opacity = 1
            textView.layer.opacity = textView.isHidden ? 0 : 1
            clockLabel?.layer.opacity = (shouldRenderClockMode && !isPiPVisuallyHidden) ? 1 : 0
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
            playerLayer?.opacity = 0
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
            clockLabel?.isHidden = false
            clockOverlayView?.isHidden = false
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
        if isScrollingEnabled, !isPiPVisuallyHidden, shouldPreviewPiPHeightLive {
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
        updateClockLabel()
    }

    private func toggleScrolling() {
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
            if !shouldRenderClockMode && isScrollingEnabled {
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
            range: minPiPHeight...maxPiPHeight,
            onChange: { [weak self] height in
                self?.previewPiPHeight(height)
            },
            onFinish: { [weak self] height in
                self?.commitPiPHeight(height)
            },
            onReset: { [weak self] in
                self?.commitPiPHeight(self?.defaultPiPHeight ?? 120)
            }
        )
        editor.configureAdaptivePageSheet(preferredHeightRatio: 0.52)
        present(editor, animated: true)
    }

    private func previewPiPHeight(_ height: CGFloat) {
        isPreviewingPiPHeight = true
        pipHeight = clampedHeight(height)
        guard shouldPreviewPiPHeightLive else {
            return
        }
        UIView.performWithoutAnimation {
            videoCallContentController?.preferredContentSize = currentPiPSize
            updatePiPSourceGeometry()
            if textView != nil, shouldRenderClockMode {
                updateClockAppearance()
            } else if isPiPVisuallyHidden {
                stopDisplayLinks()
                stopClockTimer()
            }
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
        reloadPlayerItemIfNeededForCurrentSize()
        if shouldUsePlayerLayerPiPCompatibility {
            updatePiPSourceGeometry()
        }
        if textView != nil {
            configureRunningText()
        }
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

    private func togglePiPStyle() {
        DiagnosticsRuntimeState.recordUserAction("修改悬浮窗样式")
        let nextHeight = isCompactPiPStyle ? defaultPiPHeight : compactPiPHeight
        isCompactPiPStyle.toggle()
        commitPiPHeight(nextHeight)
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func prepareSourceLayerForPiP() {
        guard let playerLayer else { return }
        view.layoutIfNeeded()
        centerPlayerLayer()
        playerLayer.opacity = 0
        CATransaction.flush()
    }

    private func centerPlayerLayer() {
        guard let playerLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = centeredPreviewFrame()
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

    @objc private func handleEnterBackground() {
        print("进入后台")
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
        updateDisplaySleepDiagnostics(reason: "进入后台保活", shouldLog: true)
    }

    @objc private func handleKeepAliveModeDidChange() {
        updateDiagnosticsPiPState()
        AppDebugLogger.log("KeepAlive mode changed, PiPOnly=\(shouldUsePiPOnlyKeepAlive), active=\(shouldKeepPiPPlaybackAlive)")
        updateHomeView()
        if shouldUsePiPOnlyKeepAlive {
            BackgroundTaskManager.shared.forceStopAndDeactivate()
            PowerUsageLogger.markKeepAliveStop()
        }
        guard shouldKeepPiPPlaybackAlive else { return }
        keepPlaybackAlive()
        KeepAliveLogger.markPiPStarted(mode: shouldUsePiPOnlyKeepAlive ? "PiP保活-低功耗" : "音频强保活")
        updateDisplaySleepDiagnostics(reason: "保活方案切换", shouldLog: true)
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
        isOwnPiPConfirmedActive = true
        isPiPActiveForUI = true
        beginPiPRuntimeSession()
        startDisplayLinks()
        keepPlaybackAlive()
        PowerUsageLogger.markPiPStart()
        KeepAliveLogger.markPiPStarted(mode: shouldUsePiPOnlyKeepAlive ? "PiP保活-低功耗" : "音频强保活")
        updateDiagnosticsPiPState()
        updateDisplaySleepDiagnostics(reason: "PiP启动完成", shouldLog: true)
        hidePiPAfterShortcutStartIfNeeded()
        AppDebugLogger.log("PiP did start")
        print("画中画弹出后：\(UIApplication.shared.windows)")
    }

    private func scheduleLegacyCustomViewAttachRetries() {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
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
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        pipTransitionWatchdogWorkItem?.cancel()
        cancelShortcutPiPStartRetry()
        pendingPiPStartWorkItem = nil
        pipStartTimeoutWorkItem = nil
        shouldHidePiPAfterShortcutStart = false
        beginPiPTransition(expectedActive: false, reason: "will stop")
        if needsLegacyPiPCompatibility {
            isStoppingPiP = true
        } else {
            isPiPActiveForUI = false
        }
        stopDisplayLinks()
        stopClockTimer()
        updateDiagnosticsPiPState()
        updateDisplaySleepDiagnostics(reason: "PiP即将停止", shouldLog: true)
        AppDebugLogger.log("PiP will stop")
        hidePiPContentForClosing()
        preparePiPVisualSurfacesForClosing()
        movePiPSourceViewOffscreenForClosing()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        hidePiPContentForClosing()
        let wasExpectedStop = !wantsPiPActive || isStoppingPiP || didRecoverStalePiPStop
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
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        BackgroundTaskManager.shared.stopPlay()
        pauseBackingPlayerIfIdle()
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

    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        AppDebugLogger.log("PiP failed to start: \(error.localizedDescription)")
        if retryLegacyPiPStartIfNeeded(reason: "画中画启动失败：\(error.localizedDescription)") {
            return
        }
        if scheduleShortcutPiPStartRetry(reason: "画中画启动失败：\(error.localizedDescription)") {
            resetPiPStartStateAfterFailure()
            return
        }
        resetPiPStartStateAfterFailure()
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
    private let onChange: (CGFloat) -> Void
    private let onFinish: (CGFloat) -> Void
    private let onReset: () -> Void

    private let valueLabel = UILabel()
    private let slider = UISlider()
    private let initialHeight: CGFloat

    init(
        height: CGFloat,
        range: ClosedRange<CGFloat>,
        onChange: @escaping (CGFloat) -> Void,
        onFinish: @escaping (CGFloat) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.range = range
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
        titleLabel.text = "自定义悬浮窗高度"
        titleLabel.font = .systemFont(ofSize: 24, weight: .black)
        titleLabel.textColor = .label

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .black)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
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
        hintLabel.text = "滑动时会实时调整已打开悬浮窗的高度\n可根据自身喜好调节侧边吸附框大小"
        hintLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 0

        let resetButton = makeGlassButton(title: "恢复默认 120pt", isPrimary: false)
        resetButton.setTitle("恢复默认 120pt", for: .normal)
        resetButton.addTarget(self, action: #selector(handleReset), for: .touchUpInside)

        let doneButton = makeGlassButton(title: "完成", isPrimary: true)
        doneButton.setTitle("完成", for: .normal)
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
            make.top.equalTo(contentView.snp.top).offset(28)
        }

        updateValueLabel()
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
        button.layer.borderColor = UIColor.white.withAlphaComponent(isPrimary ? 0.32 : 0.22).cgColor
        button.clipsToBounds = true
        return button
    }

    @objc private func handleSliderChange() {
        updateValueLabel()
        onChange(currentHeight)
    }

    @objc private func handleSliderFinish() {
        onFinish(currentHeight)
    }

    @objc private func handleReset() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let defaultHeight = CGFloat(120)
        slider.setValue(Float(defaultHeight), animated: true)
        updateValueLabel()
        onReset()
    }

    @objc private func handleDone() {
        onFinish(currentHeight)
        dismiss(animated: true)
    }

    private var currentHeight: CGFloat {
        (CGFloat(slider.value) * 10).rounded() / 10
    }

    private func updateValueLabel() {
        let height = currentHeight
        if height.truncatingRemainder(dividingBy: 1) == 0 {
            valueLabel.text = "\(Int(height))pt"
        } else {
            valueLabel.text = String(format: "%.1fpt", height)
        }
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
        timeLabel.text = time
        fpsLabel.text = fps
        networkLabel.text = network
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
    static func makeBackingVideo(at url: URL, size: CGSize) throws {
        try? FileManager.default.removeItem(at: url)

        do {
            try makeVideo(at: url, size: size, fileType: .mov, codec: .hevcWithAlpha, alpha: 0)
        } catch {
            try? FileManager.default.removeItem(at: url)
            try makeVideo(at: url, size: size, fileType: .mov, codec: .h264, alpha: 0.01)
        }
    }

    private static func makeVideo(
        at url: URL,
        size: CGSize,
        fileType: AVFileType,
        codec: AVVideoCodecType,
        alpha: CGFloat
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
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

        let frameRate = 60
        let timescale = Int32(frameRate)
        for frameIndex in 0..<frameRate {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let pixelBuffer = makePixelBuffer(size: size, alpha: alpha) else {
                throw NSError(domain: "PlaceholderVideoFactory", code: 2)
            }
            let frameTime = CMTime(value: CMTimeValue(frameIndex), timescale: timescale)
            adaptor.append(pixelBuffer, withPresentationTime: frameTime)
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

    private static func makePixelBuffer(size: CGSize, alpha: CGFloat) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
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
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: size))
        context.setFillColor(UIColor.black.withAlphaComponent(alpha).cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        return pixelBuffer
    }
}
