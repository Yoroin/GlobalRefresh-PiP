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
    private var videoCallContentController: UIViewController?
    private var hostingController: UIHostingController<PiPHomeView>?
    private var scrollDisplayLink: CADisplayLink?
    private var clockTimer: Timer?
    private var lastScrollTimestamp: CFTimeInterval?
    private var playerEndObserver: NSObjectProtocol?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isPiPTransitioning = false
    private var isStoppingPiP = false
    private var pendingPiPStartWorkItem: DispatchWorkItem?
    private var pipStartTimeoutWorkItem: DispatchWorkItem?
    private var playerStallObserver: NSObjectProtocol?
    private var playerPauseObserver: NSKeyValueObservation?
    private var isPreviewingPiPHeight = false
    private var didRetryLegacyPiPStart = false
    private var isCompactPiPStyle = true
    private var isLoadingHomePreferences = false
    private var hasPreparedPiPInfrastructure = false
    private var wantsPiPActive = false
    private var pipRuntimeStartedAt: Date?
    private var pipRuntimeDuration: TimeInterval = 0
    private var pipRuntimeStoppedAtText = "暂无"
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
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private let textPiPWidth: CGFloat = 300
    private let clockPiPWidth: CGFloat = 200
    private let isClockModeFeatureEnabled = false
    private let defaultPiPHeight: CGFloat = 120
    private let compactPiPHeight: CGFloat = 44
    private let minPiPHeight: CGFloat = 0.1
    private let maxPiPHeight: CGFloat = 220
    private let userDefaultsScrollingEnabledKey = "pip.home.scrollingEnabled"
    private let userDefaultsRememberPiPHeightKey = "pip.home.rememberPiPHeight"
    private let userDefaultsClockModeEnabledKey = "pip.home.clockModeEnabled"
    private let userDefaultsPiPHeightKey = "pip.home.rememberedPiPHeight"
    private let userDefaultsPiPRuntimeStartedAtKey = "pip.home.runtimeStartedAt"
    private let userDefaultsPiPRuntimeDurationKey = "pip.home.runtimeDuration"
    private let userDefaultsPiPRuntimeWasActiveKey = "pip.home.runtimeWasActive"
    private let userDefaultsPiPRuntimeStoppedAtTextKey = "pip.home.runtimeStoppedAtText"
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
    private var shouldRenderClockMode: Bool {
        isClockModeFeatureEnabled && isClockModeEnabled && !isPiPVisuallyHidden
    }
    private var pipStatusColor: UIColor {
        isPiPRuntimeActive ? .systemBlue : .secondaryLabel
    }
    private var isPiPRuntimeActive: Bool {
        pipRuntimeStartedAt != nil && ((pipController?.isPictureInPictureActive ?? false) || isPiPActiveForUI)
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
        return false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        print("画中画初始化前：\(UIApplication.shared.windows)")
        DiagnosticsRuntimeState.updateCurrentPage("悬浮窗")
        AppDebugLogger.log("Home viewDidLoad")
        PowerUsageLogger.markLaunch()
        KeepAliveLogger.markAppLaunch()

        loadHomePreferences()
        loadPiPRuntimeState()
        setupSwiftUI()

        NotificationCenter.default.addObserver(self, selector: #selector(handleEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeepAliveModeDidChange), name: Self.iOS26KeepAliveModeDidChangeNotification, object: nil)
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
            remembersPiPHeight: remembersPiPHeight,
            isSettingsExpanded: isSettingsExpanded,
            onTogglePiP: { [weak self] in self?.togglePiP() },
            onShowTutorial: { [weak self] in self?.presentTutorial() },
            onToggleStyle: { [weak self] in self?.togglePiPStyle() },
            onCustomizeHeight: { [weak self] in self?.presentPiPHeightEditor() },
            onToggleScrolling: { [weak self] in self?.toggleScrolling() },
            onSetClockMode: { [weak self] newValue in self?.setClockMode(newValue) },
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
        syncPiPRuntimeDisplayState()
        hostingController?.rootView = PiPHomeView(
            isPiPActive: Binding(
                get: { [weak self] in self?.isPiPActiveForUI ?? false },
                set: { [weak self] newValue in self?.isPiPActiveForUI = newValue }
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
            remembersPiPHeight: remembersPiPHeight,
            isSettingsExpanded: isSettingsExpanded,
            onTogglePiP: { [weak self] in self?.togglePiP() },
            onShowTutorial: { [weak self] in self?.presentTutorial() },
            onToggleStyle: { [weak self] in self?.togglePiPStyle() },
            onCustomizeHeight: { [weak self] in self?.presentPiPHeightEditor() },
            onToggleScrolling: { [weak self] in self?.toggleScrolling() },
            onSetClockMode: { [weak self] newValue in self?.setClockMode(newValue) },
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
            isClockModeEnabled = UserDefaults.standard.object(forKey: userDefaultsClockModeEnabledKey) == nil
                ? true
                : UserDefaults.standard.bool(forKey: userDefaultsClockModeEnabledKey)
        } else {
            isClockModeEnabled = false
            UserDefaults.standard.set(false, forKey: userDefaultsClockModeEnabledKey)
        }
        isScrollingEnabled = isClockModeEnabled ? false : prefersTextScrolling

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
        if requiresPlayerLayerForPiP {
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
        player.allowsExternalPlayback = false
        playerLayer.player = player
        observeLooping(for: playerItem)
        observePlaybackHealth(for: player, item: playerItem)

        view.layer.addSublayer(playerLayer)
    }

    private func configureBackingPlayerForPiP(_ player: AVPlayer) {
        player.preventsDisplaySleepDuringVideoPlayback = false
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
        clockLabel.adjustsFontSizeToFitWidth = true
        clockLabel.minimumScaleFactor = 0.45
        clockLabel.baselineAdjustment = .alignCenters
        clockLabel.isHidden = true
        customView.addSubview(clockLabel)
        clockLabel.snp.makeConstraints { make in
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
        guard needsLegacyPiPCompatibility else { return }

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
        !shouldUsePiPOnlyKeepAlive || requiresPlayerLayerForPiP
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
        wantsPiPActive && ((pipController?.isPictureInPictureActive ?? false) || isPiPTransitioning || isPiPActiveForUI)
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

    private var shouldPreviewPiPHeightLive: Bool {
        (pipController?.isPictureInPictureActive ?? false) || isPiPTransitioning || isPiPActiveForUI
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

    private func makePlayerItem() -> AVPlayerItem? {
        let backingVideoSize = CGSize(
            width: max(currentPiPSize.width, 1),
            height: max(currentPiPSize.height, 1)
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pip-transparent-alpha-v5-\(Int(backingVideoSize.width))x\(Int(backingVideoSize.height)).mov")
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
        configureForScrollingTextRefreshRate(scrollDisplayLink)
        scrollDisplayLink.add(to: .main, forMode: .common)
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
        updateClockLabel()
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(updateClockLabel), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func stopClockTimer() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    private func configureForScrollingTextRefreshRate(_ displayLink: CADisplayLink) {
        let targetFramesPerSecond = 30
        if #available(iOS 15.0, *) {
            let target = Float(targetFramesPerSecond)
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: target,
                maximum: target,
                preferred: target
            )
        } else {
            displayLink.preferredFramesPerSecond = targetFramesPerSecond
        }
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

    @objc private func updateClockLabel() {
        guard let clockLabel else { return }
        clockLabel.text = clockFormatter.string(from: Date())
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
        isPiPTransitioning = true
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
        isPiPTransitioning = true
        isStoppingPiP = false
        keepPlaybackAlive()
        schedulePiPStartTimeout()
        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                self.isPiPTransitioning,
                let pipController = self.pipController,
                !pipController.isPictureInPictureActive
            else {
                return
            }
            pipController.startPictureInPicture()
        }
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
            isPiPTransitioning = false
            isPiPActiveForUI = pipController.isPictureInPictureActive
            return
        }
        isPiPTransitioning = true
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
        pendingPiPStartWorkItem = nil
        pipStartTimeoutWorkItem = nil
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        hidePiPContentForClosing()
        detachLegacyCustomViewIfNeeded()
        restorePiPVisualSurfaces()
        isPiPActiveForUI = pipController?.isPictureInPictureActive ?? false
        isStoppingPiP = false
        isPiPTransitioning = false
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

        isPiPTransitioning = false
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
            attachCustomViewToKeyWindow()
        } else {
            attachCustomViewToPiPContent()
        }
    }

    private func attachCustomViewToKeyWindow() {
        guard let window = UIApplication.shared.windows.first, let customView else { return }
        if customView.superview !== window {
            customView.removeFromSuperview()
            window.addSubview(customView)
            customView.snp.remakeConstraints { make in
                make.center.equalToSuperview()
                legacyCustomViewWidthConstraint = make.width.equalTo(currentPiPSize.width).constraint
                legacyCustomViewHeightConstraint = make.height.equalTo(currentPiPSize.height).constraint
            }
        } else {
            updateLegacyCustomViewGeometry()
        }
        window.layoutIfNeeded()
    }

    private func detachLegacyCustomViewIfNeeded() {
        guard shouldUsePlayerLayerPiPCompatibility, let customView else { return }
        customView.removeFromSuperview()
        legacyCustomViewWidthConstraint = nil
        legacyCustomViewHeightConstraint = nil
    }

    private func removeCustomViewWithoutFlash() {
        guard let customView else { return }
        customView.layer.removeAllAnimations()
        customView.alpha = 0
    }

    private func hidePiPContentForClosing() {
        guard let customView, let textView else { return }
        UIView.performWithoutAnimation {
            customView.layer.removeAllAnimations()
            customView.alpha = 0
            textView.alpha = 0
            clockLabel?.alpha = 0
            customView.superview?.layoutIfNeeded()
        }
    }

    private func showPiPContentForOpening() {
        guard let customView, let textView else { return }
        UIView.performWithoutAnimation {
            textView.alpha = 1
            clockLabel?.alpha = 1
            customView.alpha = 1
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
            videoCallContentController?.preferredContentSize = currentPiPSize
            videoCallContentController?.view.alpha = 1
            videoCallContentController?.view.backgroundColor = .clear
            videoCallContentController?.view.layer.backgroundColor = UIColor.clear.cgColor
            playerLayer?.opacity = 0
            playerLayer?.backgroundColor = UIColor.clear.cgColor
            view.layoutIfNeeded()
        }
    }

    private func movePiPSourceViewOffscreenForClosing() {
        guard let pipSourceView else { return }
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
        if let legacyCustomViewWidthConstraint, let legacyCustomViewHeightConstraint {
            legacyCustomViewWidthConstraint.update(offset: currentPiPSize.width)
            legacyCustomViewHeightConstraint.update(offset: currentPiPSize.height)
        } else {
            customView.snp.remakeConstraints { make in
                make.center.equalToSuperview()
                legacyCustomViewWidthConstraint = make.width.equalTo(currentPiPSize.width).constraint
                legacyCustomViewHeightConstraint = make.height.equalTo(currentPiPSize.height).constraint
            }
        }
        customView.superview?.layoutIfNeeded()
    }

    private func configureRunningText() {
        guard let textView else { return }
        if shouldRenderClockMode {
            stopDisplayLinks()
            customView?.backgroundColor = .white
            textView.isHidden = true
            clockLabel?.isHidden = false
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
        clockLabel?.alpha = 1
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
        clockLabel.alpha = shouldHideClockSurface ? 0 : 1
        clockLabel.layer.opacity = shouldHideClockSurface ? 0 : 1
        clockLabel.layer.isOpaque = !shouldHideClockSurface
        clockLabel.isOpaque = !shouldHideClockSurface
        customView?.backgroundColor = shouldHideClockSurface ? .clear : .white
        customView?.layer.backgroundColor = (shouldHideClockSurface ? UIColor.clear : UIColor.white).cgColor
        customView?.layer.opacity = shouldHideClockSurface ? 0 : 1
        customView?.layer.isOpaque = !shouldHideClockSurface
        customView?.isOpaque = !shouldHideClockSurface
        textView?.backgroundColor = shouldHideClockSurface ? .clear : .black
        textView?.layer.backgroundColor = (shouldHideClockSurface ? UIColor.clear : UIColor.black).cgColor
        textView?.alpha = shouldHideClockSurface ? 0 : 1
        textView?.layer.opacity = shouldHideClockSurface ? 0 : 1
        textView?.layer.isOpaque = !shouldHideClockSurface
        textView?.textColor = shouldHideClockSurface ? .clear : .white
        textView?.isOpaque = !shouldHideClockSurface
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
        videoCallContentController?.preferredContentSize = currentPiPSize
        updatePiPSourceGeometry()
        if textView != nil {
            configureRunningText()
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
        guard requiresPlayerLayerForPiP else { return }
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
    }

    @objc private func handleEnterBackground() {
        print("进入后台")
        DiagnosticsRuntimeState.updateAppState("后台")
        updateDiagnosticsPiPState()
        PowerUsageLogger.markBackgroundStart()
        AppDebugLogger.log("Enter background, keepAlive=\(shouldKeepPiPPlaybackAlive)")
        guard shouldKeepPiPPlaybackAlive else {
            BackgroundTaskManager.shared.stopPlay()
            PowerUsageLogger.markKeepAliveStop()
            pauseBackingPlayerIfIdle()
            endBackgroundTask()
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
            BackgroundTaskManager.shared.stopPlay()
            PowerUsageLogger.markKeepAliveStop()
        case .ended:
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
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        pendingPiPStartWorkItem = nil
        pipStartTimeoutWorkItem = nil
        didRetryLegacyPiPStart = false
        wantsPiPActive = true
        updatePiPAutomaticStartPolicy()
        prepareCustomViewForPiPStart()
        configureRunningText()
        showPiPContentForOpening()
        isPiPTransitioning = false
        isPiPActiveForUI = true
        beginPiPRuntimeSession()
        startDisplayLinks()
        keepPlaybackAlive()
        PowerUsageLogger.markPiPStart()
        KeepAliveLogger.markPiPStarted(mode: shouldUsePiPOnlyKeepAlive ? "PiP保活-低功耗" : "音频强保活")
        updateDiagnosticsPiPState()
        updateDisplaySleepDiagnostics(reason: "PiP启动完成", shouldLog: true)
        AppDebugLogger.log("PiP did start")
        print("画中画弹出后：\(UIApplication.shared.windows)")
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pendingPiPStartWorkItem?.cancel()
        pipStartTimeoutWorkItem?.cancel()
        pendingPiPStartWorkItem = nil
        pipStartTimeoutWorkItem = nil
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
        detachLegacyCustomViewIfNeeded()
        restorePiPVisualSurfaces()
        isPiPActiveForUI = false
        isStoppingPiP = false
        isPiPTransitioning = false
        finishPiPRuntimeSession()
        didRetryLegacyPiPStart = false
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        BackgroundTaskManager.shared.stopPlay()
        pauseBackingPlayerIfIdle()
        PowerUsageLogger.markPiPStop()
        PowerUsageLogger.markKeepAliveStop()
        KeepAliveLogger.markPiPStopped(reason: "PiP did stop")
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
            make.top.equalTo(contentView.safeAreaLayoutGuide).offset(28)
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

        let frameTimes = [
            CMTime(value: 0, timescale: 1),
            CMTime(value: 60, timescale: 1)
        ]
        for frameTime in frameTimes {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let pixelBuffer = makePixelBuffer(size: size, alpha: alpha) else {
                throw NSError(domain: "PlaceholderVideoFactory", code: 2)
            }
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
