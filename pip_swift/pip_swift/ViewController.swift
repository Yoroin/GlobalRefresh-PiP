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
    private var videoCallContentController: UIViewController?
    private var hostingController: UIHostingController<PiPHomeView>?
    private var scrollDisplayLink: CADisplayLink?
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
    private var isSettingsExpanded = false {
        didSet {
            guard oldValue != isSettingsExpanded else { return }
            updateHomeView()
        }
    }
    private var isScrollingEnabled = true {
        didSet {
            guard oldValue != isScrollingEnabled else { return }
            if !isLoadingHomePreferences {
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
    private lazy var pipHeight: CGFloat = compactPiPHeight
    private var isPiPActiveForUI = false {
        didSet {
            guard oldValue != isPiPActiveForUI else { return }
            updateHomeView()
        }
    }

    private let pipWidth: CGFloat = 300
    private let defaultPiPHeight: CGFloat = 120
    private let compactPiPHeight: CGFloat = 44
    private let minPiPHeight: CGFloat = 0.1
    private let maxPiPHeight: CGFloat = 220
    private let userDefaultsScrollingEnabledKey = "pip.home.scrollingEnabled"
    private let userDefaultsRememberPiPHeightKey = "pip.home.rememberPiPHeight"
    private let userDefaultsPiPHeightKey = "pip.home.rememberedPiPHeight"
    static let userDefaultsIOS26AudioKeepAliveKey = "pip.keepAlive.iOS26AudioEnabled"
    static let userDefaultsIOS26PiPOnlyKeepAliveKey = "pip.keepAlive.iOS26PiPOnlyEnabled"
    static let iOS26KeepAliveModeDidChangeNotification = Notification.Name("pip.iOS26KeepAliveModeDidChange")
    private var currentPiPSize: CGSize {
        CGSize(width: pipWidth, height: clampedPiPHeight)
    }
    private var clampedPiPHeight: CGFloat {
        min(max(pipHeight, minPiPHeight), maxPiPHeight)
    }
    private var pipHeightForDisplay: String {
        formattedHeight(clampedPiPHeight)
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
        AppDebugLogger.log("Home viewDidLoad")
        PowerUsageLogger.markLaunch()
        KeepAliveLogger.markAppLaunch()

        loadHomePreferences()
        setupSwiftUI()

        NotificationCenter.default.addObserver(self, selector: #selector(handleEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleKeepAliveModeDidChange), name: Self.iOS26KeepAliveModeDidChangeNotification, object: nil)
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
        endBackgroundTask()
    }

    private func setupSwiftUI() {
        let rootView = PiPHomeView(
            isPiPActive: Binding(
                get: { [weak self] in self?.isPiPActiveForUI ?? false },
                set: { [weak self] newValue in self?.isPiPActiveForUI = newValue }
            ),
            pipHeight: pipHeightForDisplay,
            isScrollingEnabled: isScrollingEnabled,
            remembersPiPHeight: remembersPiPHeight,
            isSettingsExpanded: isSettingsExpanded,
            onTogglePiP: { [weak self] in self?.togglePiP() },
            onShowTutorial: { [weak self] in self?.presentTutorial() },
            onToggleStyle: { [weak self] in self?.togglePiPStyle() },
            onCustomizeHeight: { [weak self] in self?.presentPiPHeightEditor() },
            onToggleScrolling: { [weak self] in self?.toggleScrolling() },
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
        hostingController?.rootView = PiPHomeView(
            isPiPActive: Binding(
                get: { [weak self] in self?.isPiPActiveForUI ?? false },
                set: { [weak self] newValue in self?.isPiPActiveForUI = newValue }
            ),
            pipHeight: pipHeightForDisplay,
            isScrollingEnabled: isScrollingEnabled,
            remembersPiPHeight: remembersPiPHeight,
            isSettingsExpanded: isSettingsExpanded,
            onTogglePiP: { [weak self] in self?.togglePiP() },
            onShowTutorial: { [weak self] in self?.presentTutorial() },
            onToggleStyle: { [weak self] in self?.togglePiPStyle() },
            onCustomizeHeight: { [weak self] in self?.presentPiPHeightEditor() },
            onToggleScrolling: { [weak self] in self?.toggleScrolling() },
            onToggleSettings: { [weak self] in self?.toggleSettingsPanel() },
            onDismissSettings: { [weak self] in self?.dismissSettingsPanel() },
            onSetRememberPiPHeight: { [weak self] newValue in self?.setRememberPiPHeight(newValue) }
        )
    }

    private func loadHomePreferences() {
        isLoadingHomePreferences = true
        defer { isLoadingHomePreferences = false }

        if UserDefaults.standard.object(forKey: userDefaultsScrollingEnabledKey) != nil {
            isScrollingEnabled = UserDefaults.standard.bool(forKey: userDefaultsScrollingEnabledKey)
        }

        remembersPiPHeight = UserDefaults.standard.bool(forKey: userDefaultsRememberPiPHeightKey)
        if remembersPiPHeight,
           UserDefaults.standard.object(forKey: userDefaultsPiPHeightKey) != nil {
            pipHeight = clampedHeight(CGFloat(UserDefaults.standard.double(forKey: userDefaultsPiPHeightKey)))
            isCompactPiPStyle = abs(clampedPiPHeight - compactPiPHeight) < 0.5
        }
    }

    private func setRememberPiPHeight(_ isEnabled: Bool) {
        remembersPiPHeight = isEnabled
    }

    private func toggleSettingsPanel() {
        isSettingsExpanded.toggle()
    }

    private func dismissSettingsPanel() {
        guard isSettingsExpanded else { return }
        isSettingsExpanded = false
    }

    private func saveCurrentPiPHeightPreference() {
        UserDefaults.standard.set(Double(clampedPiPHeight), forKey: userDefaultsPiPHeightKey)
    }

    private func clampedHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minPiPHeight), maxPiPHeight)
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
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        pipController = nil
        videoCallContentController = nil
        customView?.removeFromSuperview()
        customView = nil
        textView = nil
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
        player.actionAtItemEnd = .none
        player.isMuted = true
        player.allowsExternalPlayback = true
        playerLayer.player = player
        observeLooping(for: playerItem)
        observePlaybackHealth(for: player, item: playerItem)
        player.play()

        view.layer.addSublayer(playerLayer)
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
        文本文本开头
        这是自定义view，想放什么放什么
        这是自定义view，想放什么放什么
        这是自定义view，想放什么放什么
        这是自定义view，想放什么放什么
        这是自定义view，想放什么放什么
        文本
        文本
        文本
        文本文本结尾
        """
    }

    private func togglePiP() {
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
            player.play()
        }
    }

    private func keepPlaybackAlive() {
        guard shouldKeepPiPPlaybackAlive else { return }
        configurePiPAudioSession()
        if shouldUsePiPOnlyKeepAlive {
            BackgroundTaskManager.shared.stopPlay()
            PowerUsageLogger.markKeepAliveStop()
            KeepAliveLogger.heartbeat()
            AppDebugLogger.log("Skip silent keepAlive audio, PiP-only keepAlive")
        } else {
            PowerUsageLogger.markKeepAliveStart()
            BackgroundTaskManager.shared.startPlay()
            KeepAliveLogger.heartbeat()
        }
        playerLayer?.player?.play()
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
        guard isScrollingEnabled else { return }
        stopDisplayLinks()

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
        guard let textView else {
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
            stopDisplayLinks()
            BackgroundTaskManager.shared.stopPlay()
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
            customView.superview?.layoutIfNeeded()
        }
    }

    private func showPiPContentForOpening() {
        guard let customView, let textView else { return }
        UIView.performWithoutAnimation {
            textView.alpha = 1
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
        textView.isHidden = false
        textView.text = originalPiPText
        textView.backgroundColor = .black
        textView.textColor = .white
        textView.setContentOffset(.zero, animated: false)
        textView.layoutIfNeeded()
    }

    private func toggleScrolling() {
        isScrollingEnabled.toggle()
        if isScrollingEnabled {
            if pipController?.isPictureInPictureActive == true {
                startDisplayLinks()
            }
        } else {
            stopDisplayLinks()
        }
    }

    private func presentTutorial() {
        let tutorialController = TutorialTabBarController()
        let navigationController = UINavigationController(rootViewController: tutorialController)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    private func presentPiPHeightEditor() {
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
            observePlaybackHealth(for: player, item: playerItem)
        }
        playerLayer.player?.replaceCurrentItem(with: playerItem)
        playerLayer.player?.play()
    }

    private func togglePiPStyle() {
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
        PowerUsageLogger.markForegroundStart()
        AppDebugLogger.log("Enter foreground, keepAlive=\(shouldKeepPiPPlaybackAlive)")
        if shouldKeepPiPPlaybackAlive {
            KeepAliveLogger.markEnterForeground()
        }
        endBackgroundTask()
        if needsLegacyPiPCompatibility && shouldKeepPiPPlaybackAlive {
            keepPlaybackAlive()
        } else {
            BackgroundTaskManager.shared.stopPlay()
            PowerUsageLogger.markKeepAliveStop()
            playerLayer?.player?.play()
        }
    }

    @objc private func handleEnterBackground() {
        print("进入后台")
        PowerUsageLogger.markBackgroundStart()
        AppDebugLogger.log("Enter background, keepAlive=\(shouldKeepPiPPlaybackAlive)")
        guard shouldKeepPiPPlaybackAlive else {
            BackgroundTaskManager.shared.stopPlay()
            PowerUsageLogger.markKeepAliveStop()
            endBackgroundTask()
            return
        }
        beginBackgroundTaskIfNeeded()
        KeepAliveLogger.markEnterBackground(mode: shouldUsePiPOnlyKeepAlive ? "仅PiP保活" : "PiP+静音音频保活")
        keepPlaybackAlive()
    }

    @objc private func handleKeepAliveModeDidChange() {
        AppDebugLogger.log("KeepAlive mode changed, PiPOnly=\(shouldUsePiPOnlyKeepAlive), active=\(shouldKeepPiPPlaybackAlive)")
        guard shouldKeepPiPPlaybackAlive else { return }
        keepPlaybackAlive()
        KeepAliveLogger.markPiPStarted(mode: shouldUsePiPOnlyKeepAlive ? "仅PiP保活" : "PiP+静音音频保活")
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
        startDisplayLinks()
        keepPlaybackAlive()
        PowerUsageLogger.markPiPStart()
        KeepAliveLogger.markPiPStarted(mode: shouldUsePiPOnlyKeepAlive ? "仅PiP保活" : "PiP+静音音频保活")
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
        didRetryLegacyPiPStart = false
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        BackgroundTaskManager.shared.stopPlay()
        PowerUsageLogger.markPiPStop()
        PowerUsageLogger.markKeepAliveStop()
        KeepAliveLogger.markPiPStopped(reason: "PiP did stop")
        endBackgroundTask()
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
