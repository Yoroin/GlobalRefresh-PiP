//
//  FrameRateTestTabBarController.swift
//  pip_swift
//

import UIKit
import SwiftUI

enum FrameRatePreference {
    static let force120HzKey = "frameRateDemo.force120Hz"
    static let didChangeNotification = Notification.Name("FrameRatePreferenceDidChange")

    static var isHighRefreshEnabled: Bool {
        if UserDefaults.standard.object(forKey: force120HzKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: force120HzKey)
    }

    static var targetFrameRate: Int {
        isHighRefreshEnabled ? 120 : 80
    }

    static func preferredFrameRateValue(target: Float) -> Float {
        isHighRefreshEnabled ? target : 0
    }
}

enum ClockDisplayLinkPreference {
    // BETA5_ANCHOR_CLOCK_DISPLAYLINK_TARGET:
    // 1.0.8 兼容验证：时间悬浮窗自身保留 preferred=target，观察侧边吸附和游戏帧率表现。
    private static let forceTargetKey = "pip.debug.clockDisplayLinkForceTarget"
    static let didChangeNotification = Notification.Name("ClockDisplayLinkPreferenceDidChange")

    static var forcesTargetFrameRate: Bool {
        get { false }
        set {
            UserDefaults.standard.set(false, forKey: forceTargetKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    static func preferredFrameRateValue(target: Float) -> Float {
        target
    }
}

final class FrameRateTestTabBarController: UITabBarController, UITabBarControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        DiagnosticsRuntimeState.updateCurrentPage("帧率演示")

        viewControllers = [
            makePage(title: "测试页面1-120", contentPrefix: "测试页面一", targetFrameRate: 120, symbol: "1.circle", selectedSymbol: "1.circle.fill"),
            makePage(title: "测试页面2-80", contentPrefix: "测试页面二", targetFrameRate: 90, symbol: "2.circle", selectedSymbol: "2.circle.fill"),
            makePage(title: "测试页面3-60", contentPrefix: "测试页面三", targetFrameRate: 60, symbol: "3.circle", selectedSymbol: "3.circle.fill")
        ]
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard selectedViewController !== viewController else {
            return true
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DiagnosticsRuntimeState.recordUserAction("帧率演示内切换页面")
        return true
    }

    private func makePage(
        title: String,
        contentPrefix: String,
        targetFrameRate: Int,
        symbol: String,
        selectedSymbol: String
    ) -> UIViewController {
        let controller = UIHostingController(
            rootView: FrameRateTestPageView(title: title, contentPrefix: contentPrefix, targetFrameRate: targetFrameRate) { [weak self] in
                self?.dismiss(animated: true)
            }
        )
        controller.tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(systemName: symbol),
            selectedImage: UIImage(systemName: selectedSymbol)
        )
        return controller
    }
}

private struct FrameRateTestPageView: View {
    let title: String
    let contentPrefix: String
    let targetFrameRate: Int
    let onBack: () -> Void

    @State private var isCollapsed = false
    @State private var isSearchVisible = false
    @State private var searchText = ""
    @State private var frameTick = 0

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                topBar

                FrameRateScrollableListView(
                    contentPrefix: contentPrefix,
                    isCollapsed: isCollapsed
                )
            }
        }
        .background(FrameRateDriverView(frameTick: $frameTick, targetFrameRate: targetFrameRate))
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                glassIconButton(systemName: "chevron.left", action: onBack)

                Spacer()

                glassIconButton(systemName: isCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical") {
                    isCollapsed.toggle()
                }

                glassIconButton(systemName: "magnifyingglass") {
                    isSearchVisible.toggle()
                }
            }

            if isSearchVisible {
                TextField("搜索", text: $searchText)
                    .font(.system(size: 16, weight: .semibold))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .fill(Color(UIColor.secondarySystemBackground).opacity(0.78))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color(UIColor.systemGroupedBackground).opacity(0.92))
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isSearchVisible)
    }

    private func glassIconButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DiagnosticsRuntimeState.recordUserAction("帧率演示按钮：\(systemName)")
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(UIColor.label))
                .frame(width: 46, height: 46)
        }
        .buttonStyle(FrameRateGlassIconButtonStyle())
        .accessibilityLabel(Text(systemName))
    }
}

struct RootFrameRateTestView: View {
    @AppStorage(FrameRatePreference.force120HzKey) private var isHighRefreshEnabled = true
    @State private var frameTick = 0

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)

            VStack(alignment: .leading, spacing: 0) {
                PageHeaderTitle(title: "帧率演示")

                Text("可通过该页面的开关控制来对比80hz和120hz的区别，本app内所有页面帧率以及悬浮窗帧率受到该开关控制")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, -6)
                    .padding(.bottom, 14)

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("强制本页面120hz")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(Color(UIColor.label))

                            Text(isHighRefreshEnabled ? "当前请求 120Hz 演示刷新" : "全局120功能已失效，请开始上下滑动体验系统80hz")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }

                        Spacer()

                        Toggle("", isOn: forceRefreshBinding)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.84))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )

                    HStack(spacing: 10) {
                        frameBadge(title: "ON", value: "120")
                        frameBadge(title: "OFF", value: "80")
                        frameBadge(title: "MAX", value: isHighRefreshEnabled ? "120" : "80")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                RootFrameRateListView(
                    contentPrefix: "帧率演示",
                    targetFrameRate: isHighRefreshEnabled ? 120 : 80
                )
            }
        }
        .background(
            FrameRateDriverView(
                frameTick: $frameTick,
                targetFrameRate: isHighRefreshEnabled ? 120 : 80
            )
        )
    }

    private var forceRefreshBinding: Binding<Bool> {
        Binding(
            get: { isHighRefreshEnabled },
            set: { newValue in
                DiagnosticsRuntimeState.recordUserAction(newValue ? "强制本页面120Hz开启" : "强制本页面120Hz关闭")
                UserDefaults.standard.set(newValue, forKey: FrameRatePreference.force120HzKey)
                isHighRefreshEnabled = newValue
                NotificationCenter.default.post(name: FrameRatePreference.didChangeNotification, object: nil)
            }
        )
    }

    private func frameBadge(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .black))
                .foregroundColor(Color(UIColor.secondaryLabel))

            Text("\(value)Hz")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(Color(UIColor.label))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.28), lineWidth: 1)
        )
    }
}

private struct RootFrameRateListView: View {
    let contentPrefix: String
    let targetFrameRate: Int

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<36, id: \.self) { index in
                    twoLineItem(index: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    private func twoLineItem(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(contentPrefix)-\(index + 1)")
                    .font(.system(size: 17, weight: .black))
                    .foregroundColor(Color(UIColor.label))

                Spacer()

                Text("\(targetFrameRate)Hz")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Color(UIColor.systemBlue))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(
                        Capsule()
                            .fill(Color(UIColor.systemBlue).opacity(0.12))
                    )
            }

            Text("测试测试测试测试测试")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.35), lineWidth: 1)
        )
    }
}

struct FrameRateScrollableListView: View {
    let contentPrefix: String
    let isCollapsed: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(visibleRows, id: \.self) { index in
                    testTextField(index: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    private var visibleRows: Range<Int> {
        isCollapsed ? 0..<1 : 0..<36
    }

    private func testTextField(index: Int) -> some View {
        TextField("", text: .constant("\(contentPrefix)-\(index + 1) 测试测试测试测试测试"))
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(Color(UIColor.label))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(UIColor.separator).opacity(0.35), lineWidth: 1)
            )
            .textFieldStyle(.plain)
    }
}

private struct FrameRateDriverView: UIViewRepresentable {
    @Binding var frameTick: Int
    let targetFrameRate: Int

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        let displayLink = CADisplayLink(
            target: context.coordinator,
            selector: #selector(Coordinator.step)
        )
        configure(displayLink)
        displayLink.add(to: .main, forMode: .common)
        context.coordinator.displayLink = displayLink
        context.coordinator.installObservers()
        context.coordinator.updatePausedState()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let displayLink = context.coordinator.displayLink {
            configure(displayLink)
            context.coordinator.updatePausedState()
        }
    }

    func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.displayLink?.invalidate()
        coordinator.displayLink = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(frameTick: $frameTick)
    }

    private func configure(_ displayLink: CADisplayLink) {
        let maximumFramesPerSecond = UIScreen.main.maximumFramesPerSecond
        let targetFramesPerSecond = min(targetFrameRate, maximumFramesPerSecond)
        if #available(iOS 15.0, *) {
            let target = Float(targetFramesPerSecond)
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30,
                maximum: target,
                preferred: target
            )
        } else {
            displayLink.preferredFramesPerSecond = targetFramesPerSecond
        }
    }

    final class Coordinator {
        var displayLink: CADisplayLink?
        private var frameTick: Binding<Int>
        private var didInstallObservers = false

        init(frameTick: Binding<Int>) {
            self.frameTick = frameTick
        }

        func installObservers() {
            guard !didInstallObservers else { return }
            didInstallObservers = true
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(updatePausedState), name: UIApplication.didBecomeActiveNotification, object: nil)
            center.addObserver(self, selector: #selector(updatePausedState), name: UIApplication.willResignActiveNotification, object: nil)
            center.addObserver(self, selector: #selector(updatePausedState), name: UIApplication.didEnterBackgroundNotification, object: nil)
        }

        @objc func updatePausedState() {
            displayLink?.isPaused = UIApplication.shared.applicationState != .active
        }

        @objc func step() {
            guard UIApplication.shared.applicationState == .active else {
                displayLink?.isPaused = true
                return
            }
            frameTick.wrappedValue &+= 1
        }
    }
}

private struct FrameRateGlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = Circle()

        return configuration.label
            .background(background(isPressed: configuration.isPressed, shape: shape))
            .overlay(
                shape.strokeBorder(
                    Color.white.opacity(configuration.isPressed ? 0.38 : 0.22),
                    lineWidth: 1
                )
            )
            .clipShape(shape)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.06 : 0.12),
                radius: configuration.isPressed ? 6 : 14,
                x: 0,
                y: configuration.isPressed ? 3 : 8
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: configuration.isPressed)
    }

    @ViewBuilder
    private func background(
        isPressed: Bool,
        shape: Circle
    ) -> some View {
        if #available(iOS 26.0, *) {
            shape
                .fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.42 : 0.24))
                .glassEffect(.regular.interactive(), in: shape)
        } else if #available(iOS 15.0, *) {
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.38 : 0.22))
                )
        } else {
            shape
                .fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.86 : 0.68))
        }
    }
}
