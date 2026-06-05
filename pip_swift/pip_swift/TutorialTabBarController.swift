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
                content: "点击首页的“启用悬浮窗”按钮，打开悬浮窗"
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
                content: "将悬浮窗拖动到侧边吸附，即可实现系统全局120hz"
            )
        )
        stepTwoController.tabBarItem = UITabBarItem(
            title: "步骤二",
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

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)

            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(Color(UIColor.label))

                Text(content)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 34)
        }
    }
}
