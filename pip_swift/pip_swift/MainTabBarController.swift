//
//  MainTabBarController.swift
//  pip_swift
//

import UIKit
import SwiftUI

final class MainTabBarController: UITabBarController, UITabBarControllerDelegate, UIGestureRecognizerDelegate {

    private var interactionController: UIPercentDrivenInteractiveTransition?
    private var isInteractive = false
    private var isTabTransitioning = false
    private var tabTransitionResetWorkItem: DispatchWorkItem?
    private var refreshDisplayLink: CADisplayLink?
    private var pendingShortcutRetryWorkItems: [DispatchWorkItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        DiagnosticsRuntimeState.updateCurrentPage("悬浮窗")

        let pipController = ViewController()
        pipController.tabBarItem = UITabBarItem(
            title: "悬浮窗",
            image: TabIconFactory.icon120Hz(),
            selectedImage: TabIconFactory.icon120Hz()
        )

        let frameRateController = UIHostingController(rootView: RootFrameRateTestView())
        frameRateController.tabBarItem = UITabBarItem(
            title: "帧率演示",
            image: UIImage(systemName: "speedometer"),
            selectedImage: UIImage(systemName: "speedometer")
        )

        let versionController = VersionViewController()
        versionController.tabBarItem = UITabBarItem(
            title: "版本",
            image: UIImage(systemName: "info.circle"),
            selectedImage: UIImage(systemName: "info.circle.fill")
        )

        viewControllers = [pipController, frameRateController, versionController]

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(panGesture)

        startRefreshDriver()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFrameRatePreferenceChange),
            name: FrameRatePreference.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShortcutActionNotification),
            name: PiPShortcutActionCenter.didRequestActionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        DispatchQueue.main.async { [weak self] in
            self?.performPendingShortcutAction(reason: "主界面加载")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        tabTransitionResetWorkItem?.cancel()
        pendingShortcutRetryWorkItems.forEach { $0.cancel() }
        refreshDisplayLink?.invalidate()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }
        let velocity = panGesture.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let controllers = viewControllers, controllers.count > 1 else { return }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let progress = min(max(abs(translation.x) / max(view.bounds.width, 1), 0), 1)

        switch gesture.state {
        case .began:
            let targetIndex = velocity.x < 0 ? selectedIndex + 1 : selectedIndex - 1
            guard controllers.indices.contains(targetIndex) else { return }
            guard !isTabTransitioning else {
                AppDebugLogger.log("忽略底栏左右滑动：转场中")
                return
            }

            dismissVisibleTransientOverlays()
            DiagnosticsRuntimeState.recordUserAction("底栏左右滑动切换：\(diagnosticPageName(for: targetIndex))")
            DiagnosticsRuntimeState.updateCurrentPage(diagnosticPageName(for: targetIndex))
            isInteractive = true
            beginTabTransition(reason: "swipe")
            interactionController = UIPercentDrivenInteractiveTransition()
            selectedIndex = targetIndex

        case .changed:
            interactionController?.update(progress)

        case .ended:
            let shouldFinish = progress > 0.35 || abs(velocity.x) > 700
            shouldFinish ? interactionController?.finish() : interactionController?.cancel()
            interactionController = nil
            isInteractive = false

        case .cancelled, .failed:
            interactionController?.cancel()
            interactionController = nil
            isInteractive = false

        default:
            break
        }
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        animationControllerForTransitionFrom fromVC: UIViewController,
        to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        guard
            let controllers = viewControllers,
            let fromIndex = controllers.firstIndex(of: fromVC),
            let toIndex = controllers.firstIndex(of: toVC)
        else {
            return nil
        }

        return TabSlideAnimator(direction: toIndex > fromIndex ? .forward : .backward) { [weak self] completed, cancelled, finished in
            self?.finishTabTransition(completed: completed, cancelled: cancelled, finished: finished)
        }
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        interactionControllerFor animationController: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        isInteractive ? interactionController : nil
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard selectedViewController !== viewController else {
            return true
        }

        guard !isInteractive, !isTabTransitioning else {
            AppDebugLogger.log("忽略底栏点击：转场中")
            UISelectionFeedbackGenerator().selectionChanged()
            normalizeSelectedViewAfterTabTransition()
            return false
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismissVisibleTransientOverlays()
        if let index = viewControllers?.firstIndex(of: viewController) {
            DiagnosticsRuntimeState.recordUserAction("底栏点击切换：\(diagnosticPageName(for: index))")
            DiagnosticsRuntimeState.updateCurrentPage(diagnosticPageName(for: index))
        }
        beginTabTransition(reason: "tap")
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if let index = viewControllers?.firstIndex(of: viewController) {
            DiagnosticsRuntimeState.updateCurrentPage(diagnosticPageName(for: index))
        }
    }

    private func dismissVisibleTransientOverlays() {
        if let controller = selectedViewController as? ViewController {
            controller.dismissTransientOverlays()
        } else if let controller = selectedViewController as? VersionViewController {
            controller.dismissTransientOverlays()
        }
    }

    private func beginTabTransition(reason: String) {
        tabTransitionResetWorkItem?.cancel()
        isTabTransitioning = true

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isTabTransitioning else { return }
            self.isTabTransitioning = false
            self.normalizeSelectedViewAfterTabTransition()
            AppDebugLogger.log("Tab transition watchdog reset, reason=\(reason)")
        }
        tabTransitionResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)
    }

    private func finishTabTransition(completed: Bool, cancelled: Bool, finished: Bool) {
        tabTransitionResetWorkItem?.cancel()
        tabTransitionResetWorkItem = nil
        isTabTransitioning = false
        normalizeSelectedViewAfterTabTransition()

        if !finished || cancelled || !completed {
            AppDebugLogger.log("Tab transition normalized, finished=\(finished), cancelled=\(cancelled), completed=\(completed)")
        }
    }

    private func normalizeSelectedViewAfterTabTransition() {
        guard let selectedView = selectedViewController?.view,
              let container = selectedView.superview
        else { return }
        selectedView.frame = container.bounds
        selectedView.isUserInteractionEnabled = true
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

        let displayLink = CADisplayLink(target: self, selector: #selector(stepRefreshDriver))
        configureRefreshDriver(displayLink)
        // BETA2 ANCHOR: 避免空 DisplayLink 在滑动 tracking mode 中抢主线程。
        displayLink.add(to: .main, forMode: .default)
        refreshDisplayLink = displayLink
    }

    @objc private func handleFrameRatePreferenceChange() {
        if let refreshDisplayLink {
            configureRefreshDriver(refreshDisplayLink)
        } else {
            startRefreshDriver()
        }
    }

    @objc private func handleShortcutActionNotification() {
        schedulePendingShortcutActionChecks(reason: "快捷方式通知")
    }

    @objc private func handleAppDidBecomeActive() {
        schedulePendingShortcutActionChecks(reason: "App激活")
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

    @discardableResult
    private func performPendingShortcutAction(reason: String) -> Bool {
        guard PiPShortcutActionCenter.hasPendingAction else { return false }
        AppDebugLogger.log("Route shortcut action to PiP page, reason=\(reason)")
        dismissVisibleTransientOverlays()

        if selectedIndex != 0 {
            tabTransitionResetWorkItem?.cancel()
            tabTransitionResetWorkItem = nil
            isTabTransitioning = false
            isInteractive = false
            interactionController?.cancel()
            interactionController = nil
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
        let targetFramesPerSecond = max(60, maximumFramesPerSecond)

        if #available(iOS 15.0, *) {
            let target = Float(targetFramesPerSecond)
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30,
                maximum: target,
                preferred: FrameRatePreference.preferredFrameRateValue(target: target)
            )
        } else {
            displayLink.preferredFramesPerSecond = targetFramesPerSecond
        }
    }
}

final class TabSlideAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    enum Direction {
        case forward
        case backward
    }

    private let direction: Direction
    private let onCompletion: ((Bool, Bool, Bool) -> Void)?

    init(direction: Direction, onCompletion: ((Bool, Bool, Bool) -> Void)? = nil) {
        self.direction = direction
        self.onCompletion = onCompletion
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.28
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard
            let fromView = transitionContext.view(forKey: .from),
            let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            onCompletion?(false, true, false)
            return
        }

        let container = transitionContext.containerView
        let width = container.bounds.width
        let offset = direction == .forward ? width : -width

        toView.frame = container.bounds.offsetBy(dx: offset, dy: 0)
        container.addSubview(toView)

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
            animations: {
                fromView.frame = container.bounds.offsetBy(dx: -offset * 0.32, dy: 0)
                toView.frame = container.bounds
            },
            completion: { finished in
                fromView.frame = container.bounds
                toView.frame = container.bounds
                let cancelled = transitionContext.transitionWasCancelled
                let completed = !cancelled
                if !finished || !completed {
                    AppDebugLogger.log("Tab transition completion, finished=\(finished), cancelled=\(cancelled), completed=\(completed)")
                }
                transitionContext.completeTransition(completed)
                DispatchQueue.main.async {
                    self.onCompletion?(completed, cancelled, finished)
                }
            }
        )
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
