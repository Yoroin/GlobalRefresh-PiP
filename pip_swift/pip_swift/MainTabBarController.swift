//
//  MainTabBarController.swift
//  pip_swift
//

import UIKit
import SwiftUI
import AVFoundation

private final class TabContentFadeAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.18
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard
            let toViewController = transitionContext.viewController(forKey: .to),
            let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView
        toView.frame = transitionContext.finalFrame(for: toViewController)
        toView.alpha = 0
        toView.transform = CGAffineTransform(translationX: 0, y: 5)
            .scaledBy(x: 0.992, y: 0.992)
        containerView.addSubview(toView)

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            toView.alpha = 1
            toView.transform = .identity
        } completion: { finished in
            if transitionContext.transitionWasCancelled {
                toView.removeFromSuperview()
            }
            transitionContext.completeTransition(finished && !transitionContext.transitionWasCancelled)
        }
    }
}

final class MainTabBarController: UITabBarController, UITabBarControllerDelegate {

    private var refreshDisplayLink: CADisplayLink?
    private var pendingShortcutRetryWorkItems: [DispatchWorkItem] = []
    private var launchCelebrationController: UIHostingController<GlobalRefresh2LaunchCelebrationView>?
    private var latestChangelogController: LatestChangelogViewController?
    private var isShortcutDisabledAlertPending = false
    private let tabContentFadeAnimator = TabContentFadeAnimator()
    private weak var floatingWindowController: ViewController?
    private static let shortcutDarwinNotificationCallback: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        let controller = Unmanaged<MainTabBarController>.fromOpaque(observer).takeUnretainedValue()
        DispatchQueue.main.async {
            controller.handleShortcutDarwinNotification()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if GlobalRefresh2LaunchCelebration.shouldPresent {
            presentLaunchCelebrationIfNeeded()
        } else if GlobalRefresh2LaunchCelebration.shouldPresentLatestChangelog {
            scheduleLatestChangelogPresentation()
        }
    }

    private func presentLaunchCelebrationIfNeeded() {
        guard launchCelebrationController == nil else { return }
        guard GlobalRefresh2LaunchCelebration.shouldPresent else { return }

        GlobalRefresh2LaunchCelebration.markPresented()
        let celebration = GlobalRefresh2LaunchCelebrationView { [weak self] in
            self?.dismissLaunchCelebration()
        }
        let controller = UIHostingController(rootView: celebration)
        controller.view.backgroundColor = .clear
        launchCelebrationController = controller

        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        controller.view.alpha = 0
        UIView.animate(withDuration: 0.22) {
            controller.view.alpha = 1
        }
    }

    private func dismissLaunchCelebration() {
        guard let controller = launchCelebrationController else { return }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        launchCelebrationController = nil
        GlobalRefresh2LaunchCelebration.markFinished()
        scheduleLatestChangelogPresentation()
    }

    private func scheduleLatestChangelogPresentation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            self?.presentLatestChangelogIfPossible()
        }
    }

    private func presentLatestChangelogIfPossible() {
        guard latestChangelogController == nil else { return }
        guard viewIfLoaded?.window != nil else { return }

        if presentedViewController != nil {
            scheduleLatestChangelogPresentation()
            return
        }

        let controller = LatestChangelogViewController(
            onDismiss: { [weak self] in
                self?.dismissLatestChangelog()
            },
            onOpenFullChangelog: { [weak self] in
                self?.openFullChangelogFromLatestPopup()
            }
        )
        latestChangelogController = controller
        GlobalRefresh2LaunchCelebration.markLatestChangelogPresented()
        present(controller, animated: true)
    }

    private func dismissLatestChangelog() {
        guard latestChangelogController != nil else { return }
        dismiss(animated: true) { [weak self] in
            self?.latestChangelogController = nil
        }
    }

    private func openFullChangelogFromLatestPopup() {
        guard latestChangelogController != nil else { return }
        latestChangelogController = nil
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            let changelogController = ChangelogViewController()
            changelogController.configureAdaptivePageSheet(preferredHeightRatio: 0.58)
            self.present(changelogController, animated: true)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        L10n.rememberCurrentSystemLanguageIfNeeded()
        delegate = self
        DiagnosticsRuntimeState.updateCurrentPage("悬浮窗")

        let pipController = ViewController()
        floatingWindowController = pipController
        pipController.tabBarItem = UITabBarItem(
            title: L10n.floatingWindow,
            image: TabIconFactory.icon120Hz(),
            selectedImage: TabIconFactory.icon120Hz()
        )

        let frameRateController = UIHostingController(rootView: RootFrameRateTestView())
        frameRateController.tabBarItem = UITabBarItem(
            title: L10n.frameRateDemo,
            image: UIImage(systemName: "speedometer"),
            selectedImage: UIImage(systemName: "speedometer")
        )

        let versionController = VersionViewController()
        versionController.tabBarItem = UITabBarItem(
            title: L10n.version,
            image: UIImage(systemName: "info.circle"),
            selectedImage: UIImage(systemName: "info.circle.fill")
        )

        viewControllers = [pipController, frameRateController, versionController]

        startRefreshDriver()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFrameRatePreferenceChange),
            name: FrameRatePreference.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineRuntimeModeChange),
            name: ViewController.piPEngineRuntimeModeDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShortcutActionNotification),
            name: PiPShortcutActionCenter.didRequestActionNotification,
            object: nil
        )
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            Self.shortcutDarwinNotificationCallback,
            PiPShortcutActionCenter.darwinNotificationName as CFString,
            nil,
            .deliverImmediately
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageDidChange),
            name: L10n.languageDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemLocaleDidChange),
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillResetAllAppData),
            name: CacheCleanupManager.willResetAllAppDataNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidResetAllAppData),
            name: CacheCleanupManager.didResetAllAppDataNotification,
            object: nil
        )
        DispatchQueue.main.async { [weak self] in
            self?.performPendingShortcutAction(reason: "主界面加载")
            self?.presentShortcutDisabledAlertIfNeeded()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(rawValue: PiPShortcutActionCenter.darwinNotificationName as CFString),
            nil
        )
        pendingShortcutRetryWorkItems.forEach { $0.cancel() }
        refreshDisplayLink?.invalidate()
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard selectedViewController !== viewController else {
            return true
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismissVisibleTransientOverlays()
        if let index = viewControllers?.firstIndex(of: viewController) {
            DiagnosticsRuntimeState.recordUserAction("底栏点击切换：\(diagnosticPageName(for: index))")
            DiagnosticsRuntimeState.updateCurrentPage(diagnosticPageName(for: index))
        }
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if let index = viewControllers?.firstIndex(of: viewController) {
            DiagnosticsRuntimeState.updateCurrentPage(diagnosticPageName(for: index))
        }
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        animationControllerForTransitionFrom fromVC: UIViewController,
        to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        tabContentFadeAnimator
    }

    func handleExternalShortcutRequest(reason: String) {
        schedulePendingShortcutActionChecks(reason: reason)
    }

    private func dismissVisibleTransientOverlays() {
        if let controller = selectedViewController as? ViewController {
            controller.dismissTransientOverlays()
        } else if let controller = selectedViewController as? VersionViewController {
            controller.dismissTransientOverlays()
        }
    }

    private func diagnosticPageName(for index: Int) -> String {
        switch index {
        case 0:
            return "悬浮窗"
        case 1:
            return "帧率演示"
        case 2:
            return "版本"
        default:
            return "未知页面\(index)"
        }
    }

    private func startRefreshDriver() {
        refreshDisplayLink?.invalidate()
        refreshDisplayLink = nil

        let isPlayerLayerRouteEnabled = UserDefaults.standard.bool(forKey: "pip.home.playerLayerRouteEnabled")
        let isExtremeSilentModeEnabled = UserDefaults.standard.bool(forKey: "pip.home.extremeSilentModeEnabled")
        guard !isPlayerLayerRouteEnabled, !isExtremeSilentModeEnabled else {
            AppDebugLogger.log("RefreshDriver skipped: PlayerLayer/extreme silent route active")
            return
        }

        let displayLink = CADisplayLink(target: self, selector: #selector(stepRefreshDriver))
        configureRefreshDriver(displayLink)
        // Use the 1.0.7 driver mode for every supported iOS version; hidden 0.1 pt PiP depends on this driver more than visible PiP content.
        displayLink.add(to: .main, forMode: .common)
        refreshDisplayLink = displayLink
    }

    private func stopRefreshDriver(reason: String) {
        guard refreshDisplayLink != nil else { return }
        refreshDisplayLink?.invalidate()
        refreshDisplayLink = nil
        AppDebugLogger.log("RefreshDriver stopped: \(reason)")
    }

    @objc private func handleFrameRatePreferenceChange() {
        if let refreshDisplayLink {
            configureRefreshDriver(refreshDisplayLink)
        } else {
            startRefreshDriver()
        }
    }

    @objc private func handleEngineRuntimeModeChange() {
        startRefreshDriver()
    }

    @objc private func handleShortcutActionNotification() {
        schedulePendingShortcutActionChecks(reason: "快捷方式通知")
    }

    private func handleShortcutDarwinNotification() {
        schedulePendingShortcutActionChecks(reason: "快捷方式Darwin通知")
    }

    @objc private func handleAppDidBecomeActive() {
        startRefreshDriver()
        schedulePendingShortcutActionChecks(reason: "App激活")
        presentShortcutDisabledAlertIfNeeded()
    }

    @objc private func handleAppDidEnterBackground() {
        startRefreshDriver()
    }

    @objc private func handleLanguageDidChange() {
        updateTabBarItemTitles()
        refreshLocalizedHostedPages()
    }

    @objc private func handleSystemLocaleDidChange() {
        L10n.followSystemLanguageIfActuallyChanged()
    }

    @objc private func handleWillResetAllAppData() {
        dismissVisibleTransientOverlays()
        floatingWindowController?.stopForFullDataReset()
    }

    @objc private func handleDidResetAllAppData() {
        selectedIndex = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.presentLaunchCelebrationIfNeeded()
        }
    }

    private func updateTabBarItemTitles() {
        guard let viewControllers else { return }
        if viewControllers.indices.contains(0) {
            viewControllers[0].tabBarItem.title = L10n.floatingWindow
        }
        if viewControllers.indices.contains(1) {
            viewControllers[1].tabBarItem.title = L10n.frameRateDemo
        }
        if viewControllers.indices.contains(2) {
            viewControllers[2].tabBarItem.title = L10n.version
        }
    }

    private func refreshLocalizedHostedPages() {
        guard let viewControllers else { return }
        if viewControllers.indices.contains(1),
           let frameRateController = viewControllers[1] as? UIHostingController<RootFrameRateTestView> {
            frameRateController.rootView = RootFrameRateTestView()
        }
    }

    private func schedulePendingShortcutActionChecks(reason: String) {
        pendingShortcutRetryWorkItems.forEach { $0.cancel() }
        pendingShortcutRetryWorkItems.removeAll()

        let delays: [TimeInterval] = [0.2, 0.6, 1.1, 1.8, 2.6]
        for delay in delays {
            let workItem = DispatchWorkItem { [weak self] in
                self?.performPendingShortcutAction(reason: reason)
            }
            pendingShortcutRetryWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func presentShortcutDisabledAlertIfNeeded() {
        if PiPShortcutFeatureAccess.consumeBlockedAttempt() {
            isShortcutDisabledAlertPending = true
        }
        guard isShortcutDisabledAlertPending, viewIfLoaded?.window != nil else { return }
        guard presentedViewController == nil, launchCelebrationController == nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.presentShortcutDisabledAlertIfNeeded()
            }
            return
        }

        isShortcutDisabledAlertPending = false
        let alert = UIAlertController(
            title: L10n.text("快捷指令功能未启用", "Shortcuts Are Disabled"),
            message: L10n.text(
                "请先在首页的更多设置中打开“快捷指令功能”，阅读并确认无法自动熄屏的风险后再使用。",
                "Enable Shortcuts in Home > More Settings and confirm the auto-lock risk before using shortcut actions."
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        present(alert, animated: true)
    }

    @discardableResult
    private func performPendingShortcutAction(reason: String) -> Bool {
        guard PiPShortcutActionCenter.hasPendingAction else { return false }
        AppDebugLogger.log("Route shortcut action to PiP page, reason=\(reason)")

        dismissVisibleTransientOverlays()

        if selectedIndex != 0 {
            selectedIndex = 0
            DiagnosticsRuntimeState.updateCurrentPage("悬浮窗")
            loadViewIfNeeded()
            view.layoutIfNeeded()
        }

        guard let pipController = viewControllers?.first as? ViewController else {
            PiPShortcutActionCenter.notifyPendingActionIfNeeded()
            return false
        }
        guard pipController.isViewLoaded, pipController.view.window != nil else {
            AppDebugLogger.log("Delay shortcut action: PiP page not visible yet, reason=\(reason)")
            return false
        }
        return pipController.performPendingShortcutActionIfNeeded(reason: reason)
    }

    @objc private func stepRefreshDriver() {
    }

    private func configureRefreshDriver(_ displayLink: CADisplayLink) {
        let maximumFramesPerSecond = UIScreen.main.maximumFramesPerSecond
        let targetFramesPerSecond = min(FrameRatePreference.targetFrameRate, maximumFramesPerSecond)

        if #available(iOS 15.0, *) {
            let target = Float(targetFramesPerSecond)
            // 1.0.9 beta2: fully restore the 1.0.7 strict range; wider ranges can fall back to 80 Hz when PiP is hidden at 0.1 pt.
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: target,
                maximum: target,
                preferred: target
            )
        } else {
            displayLink.preferredFramesPerSecond = targetFramesPerSecond
        }
    }
}

enum TabIconFactory {
    static func icon120Hz() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let image = renderer.image { _ in
            UIColor.label.setFill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let numberAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .black),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ]
            let hzAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ]

            "120".draw(in: CGRect(x: 0, y: 6, width: 32, height: 14), withAttributes: numberAttributes)
            "Hz".draw(in: CGRect(x: 0, y: 18, width: 32, height: 10), withAttributes: hzAttributes)
        }

        return image.withRenderingMode(.alwaysTemplate)
    }
}
