//
//  TutorialTabBarController.swift
//  pip_swift
//

import UIKit
import SwiftUI

final class TutorialTabBarController: UITabBarController, UITabBarControllerDelegate, UIGestureRecognizerDelegate {

    private var interactionController: UIPercentDrivenInteractiveTransition?
    private var isInteractive = false

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        title = "使用教程"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )

        let stepOneController = UIHostingController(
            rootView: TutorialStepView(
                title: "步骤一",
                content: "点击首页的“开启悬浮窗”按钮，打开悬浮窗",
                imageName: "tutorial-step-1"
            )
        )
        stepOneController.tabBarItem = UITabBarItem(
            title: "步骤一",
            image: UIImage(systemName: "1.circle"),
            selectedImage: UIImage(systemName: "1.circle.fill")
        )

        let stepTwoController = UIHostingController(
            rootView: TutorialStepView(
                title: "步骤二",
                content: "将悬浮窗拖动到侧边吸附，即可实现系统全局120hz（划掉后台失效）。如需完全隐藏，点击自定义悬浮窗高度将滑块拖至0.1pt",
                imageName: "tutorial-step-2"
            )
        )
        stepTwoController.tabBarItem = UITabBarItem(
            title: "步骤二",
            image: UIImage(systemName: "2.circle"),
            selectedImage: UIImage(systemName: "2.circle.fill")
        )

        viewControllers = [stepOneController, stepTwoController]

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(panGesture)
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

            isInteractive = true
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

        return TabSlideAnimator(direction: toIndex > fromIndex ? .forward : .backward)
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        interactionControllerFor animationController: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        isInteractive ? interactionController : nil
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard
            !isInteractive,
            selectedViewController !== viewController
        else {
            return true
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        return true
    }
}

private struct TutorialStepView: View {
    let title: String
    let content: String
    let imageName: String

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)

            GeometryReader { proxy in
                let isStepOne = imageName == "tutorial-step-1"
                let imageHeight = isStepOne
                    ? min(proxy.size.height * 0.64, 500)
                    : min(proxy.size.height * 0.68, 520)
                let imageWidth = imageHeight * (1206.0 / 2622.0)

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(Color(UIColor.label))

                    Text(content)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)

                    HStack {
                        Spacer(minLength: 0)
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: imageWidth, height: imageHeight)
                            .compositingGroup()
                            .shadow(
                                color: Color.black.opacity(0.16),
                                radius: 11,
                                x: 0,
                                y: 0
                            )
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 10)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
        }
    }
}
