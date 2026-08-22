//
//  TutorialTabBarController.swift
//  pip_swift
//

import UIKit
import SwiftUI
import QuartzCore

final class TutorialTabBarController: UITabBarController, UITabBarControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        title = L10n.text("使用教程", "Tutorial")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )

        let animationController = UIHostingController(
            rootView: TutorialAnimationView()
        )
        animationController.tabBarItem = UITabBarItem(
            title: L10n.text("动画演示", "Demo"),
            image: UIImage(systemName: "play.circle"),
            selectedImage: UIImage(systemName: "play.circle.fill")
        )

        let stepsController = UIHostingController(
            rootView: TutorialCombinedStepsView()
        )
        stepsController.tabBarItem = UITabBarItem(
            title: L10n.text("图文步骤", "Steps"),
            image: UIImage(systemName: "list.number"),
            selectedImage: UIImage(systemName: "list.number")
        )

        viewControllers = [animationController, stepsController]
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard selectedViewController !== viewController else {
            return true
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        return true
    }
}

private struct TutorialAnimationView: View {
    @State private var timestamp = CACurrentMediaTime()
    @State private var startedAt = CACurrentMediaTime()

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)

            GeometryReader { proxy in
                let loopDuration = 8.7
                let loopTime = max(0, timestamp - startedAt).truncatingRemainder(dividingBy: loopDuration)
                let animationTime = min(7.7, loopTime)
                let stageHeight = min(600, max(430, proxy.size.height - 82))

                ZStack {
                    LaunchDisplayLinkDriver(timestamp: $timestamp)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(L10n.text("动画演示", "Animated Demo"))
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(Color(UIColor.label))

                        Text(L10n.text("打开悬浮窗、拖到屏幕侧边吸附，再点击一键 0.1pt", "Open PiP, dock it to the edge, then tap One-tap 0.1pt."))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)

                        LaunchPiPTutorialStage(elapsed: animationTime)
                            .frame(maxWidth: 370)
                            .frame(height: stageHeight)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
            }
        }
        .onAppear {
            startedAt = CACurrentMediaTime()
        }
    }
}

private struct TutorialCombinedStepsView: View {
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    TutorialStepSection(
                        title: L10n.text("步骤一", "Step 1"),
                        content: L10n.text("点击首页的“开启悬浮窗”按钮，打开悬浮窗", "Tap Enable Floating Window on the home page to start PiP."),
                        imageName: "tutorial-step-1"
                    )

                    Divider()

                    TutorialStepSection(
                        title: L10n.text("步骤二", "Step 2"),
                        content: L10n.text("将悬浮窗拖动到侧边吸附，即可实现系统全局120hz（划掉后台失效）。如需完全隐藏，点击自定义悬浮窗高度将滑块拖至0.1pt", "Drag the floating window to the screen edge. To fully hide it, set the custom PiP height to 0.1 pt."),
                        imageName: "tutorial-step-2"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
    }
}

private struct TutorialStepSection: View {
    let title: String
    let content: String
    let imageName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(Color(UIColor.label))

            Text(content)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            HStack {
                Spacer(minLength: 0)
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 300)
                    .compositingGroup()
                    .shadow(
                        color: Color.black.opacity(0.16),
                        radius: 11,
                        x: 0,
                        y: 0
                    )
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
        }
    }
}
