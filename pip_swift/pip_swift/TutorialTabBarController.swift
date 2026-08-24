//
//  TutorialTabBarController.swift
//  pip_swift
//

import UIKit
import SwiftUI

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

        let stepOneController = UIHostingController(
            rootView: TutorialStepView(
                title: L10n.text("步骤一", "Step 1"),
                content: L10n.text("点击首页的“开启悬浮窗”按钮，打开悬浮窗", "Tap Enable Floating Window on the home page to start PiP."),
                imageName: "tutorial-step-1"
            )
        )
        stepOneController.tabBarItem = UITabBarItem(
            title: L10n.text("步骤一", "Step 1"),
            image: UIImage(systemName: "1.circle"),
            selectedImage: UIImage(systemName: "1.circle.fill")
        )

        let stepTwoController = UIHostingController(
            rootView: TutorialStepView(
                title: L10n.text("步骤二", "Step 2"),
                content: L10n.text("将悬浮窗拖动到侧边吸附，即可实现系统全局120hz（划掉后台失效）。如需完全隐藏，点击自定义悬浮窗高度将滑块拖至0.1pt", "Drag the floating window to the screen edge. To fully hide it, set the custom PiP height to 0.1 pt."),
                imageName: "tutorial-step-2"
            )
        )
        stepTwoController.tabBarItem = UITabBarItem(
            title: L10n.text("步骤二", "Step 2"),
            image: UIImage(systemName: "2.circle"),
            selectedImage: UIImage(systemName: "2.circle.fill")
        )

        viewControllers = [stepOneController, stepTwoController]
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard selectedViewController !== viewController else {
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
                let shortSide = min(proxy.size.width, proxy.size.height)
                let isCompact = shortSide <= 340 || proxy.size.height <= 600
                let imageHeight = isStepOne
                    ? min(proxy.size.height * (isCompact ? 0.52 : 0.64), isCompact ? 360 : 500)
                    : min(proxy.size.height * (isCompact ? 0.55 : 0.68), isCompact ? 380 : 520)
                let imageWidth = imageHeight * (1206.0 / 2622.0)

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: isCompact ? 30 : 34, weight: .black, design: .rounded))
                        .foregroundColor(Color(UIColor.label))

                    Text(content)
                        .font(.system(size: isCompact ? 16 : 19, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineSpacing(isCompact ? 3 : 6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, isCompact ? 14 : 24)

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
                    .padding(.top, isCompact ? 8 : 10)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, isCompact ? 18 : 24)
                .padding(.top, isCompact ? 8 : 14)
                .padding(.bottom, isCompact ? 8 : 12)
            }
        }
    }
}
