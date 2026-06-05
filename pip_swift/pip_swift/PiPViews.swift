//
//  PiPViews.swift
//  pip_swift
//

import SwiftUI
import UIKit

struct PageHeaderTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 34, weight: .black, design: .rounded))
            .foregroundColor(Color(UIColor.label))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 12)
    }
}

struct PiPHomeView: View {
    @Binding var isPiPActive: Bool
    @State private var isSettingsVisible = false

    let pipHeight: String
    let isScrollingEnabled: Bool
    let remembersPiPHeight: Bool
    let isSettingsExpanded: Bool
    let onTogglePiP: () -> Void
    let onShowTutorial: () -> Void
    let onToggleStyle: () -> Void
    let onCustomizeHeight: () -> Void
    let onToggleScrolling: () -> Void
    let onToggleSettings: () -> Void
    let onDismissSettings: () -> Void
    let onSetRememberPiPHeight: (Bool) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissSettingsIfNeeded()
                }

            VStack(alignment: .leading, spacing: 18) {
                homeHeader

                VStack(spacing: 14) {
                    ActionButton(title: "使用教程", systemImage: "book") {
                        runAfterDismissingSettings(onShowTutorial)
                    }
                    ActionButton(title: "修改悬浮窗样式", systemImage: "rectangle.compress.vertical") {
                        runAfterDismissingSettings(onToggleStyle)
                    }
                    ActionButton(title: "自定义悬浮窗高度", systemImage: "arrow.up.and.down", detail: pipHeight) {
                        runAfterDismissingSettings(onCustomizeHeight)
                    }
                    ActionButton(
                        title: isScrollingEnabled ? "停止滚动悬浮窗内容文本" : "启用滚动悬浮窗内容文本",
                        systemImage: isScrollingEnabled ? "pause.circle" : "play.circle"
                    ) {
                        runAfterDismissingSettings(onToggleScrolling)
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 18)

                PrimaryPiPButton(title: isPiPActive ? "关闭悬浮窗" : "开启悬浮窗") {
                    runAfterDismissingSettings(onTogglePiP)
                }
                    .frame(maxWidth: 286)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissSettingsIfNeeded()
            }

            settingsPopover
                .padding(.top, 82)
                .padding(.trailing, 20)
                .opacity(isSettingsVisible ? 1 : 0)
                .scaleEffect(isSettingsVisible ? 1 : 0.98, anchor: .topTrailing)
                .offset(x: isSettingsVisible ? 0 : 4, y: isSettingsVisible ? 0 : -6)
                .allowsHitTesting(isSettingsVisible)
                .accessibilityHidden(!isSettingsVisible)
                .zIndex(10)
        }
        .onAppear {
            isSettingsVisible = isSettingsExpanded
        }
        .onChange(of: isSettingsExpanded) { newValue in
            animateSettingsVisibility(newValue)
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .center) {
            Text("首页")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(Color(UIColor.label))

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onToggleSettings()
            } label: {
                SettingsGearButton(isExpanded: isSettingsVisible)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Color(UIColor.label))

            SettingsToggleRow(
                title: "记忆悬浮窗高度",
                systemImage: "slider.horizontal.3",
                isOn: rememberHeightBinding
            )

            Text("高度记忆为0.1pt时，可能无法直接启用悬浮窗，因此会自动恢复成44pt")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .padding(16)
        .frame(width: 306)
        .modifier(SettingsGlassContainer(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var rememberHeightBinding: Binding<Bool> {
        Binding(
            get: { remembersPiPHeight },
            set: { newValue in
                guard newValue != remembersPiPHeight else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSetRememberPiPHeight(newValue)
            }
        )
    }

    private func dismissSettingsIfNeeded() {
        guard isSettingsVisible || isSettingsExpanded else { return }
        animateSettingsVisibility(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            onDismissSettings()
        }
    }

    private func runAfterDismissingSettings(_ action: @escaping () -> Void) {
        guard isSettingsVisible || isSettingsExpanded else {
            action()
            return
        }

        animateSettingsVisibility(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            onDismissSettings()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            action()
        }
    }

    private func animateSettingsVisibility(_ isVisible: Bool) {
        withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.18)) {
            isSettingsVisible = isVisible
        }
    }

}

private struct SettingsGearButton: View {
    let isExpanded: Bool

    var body: some View {
        let shape = Circle()

        Image(systemName: "gearshape.fill")
            .font(.system(size: 19, weight: .bold))
            .foregroundColor(Color(UIColor.label))
            .frame(width: 44, height: 44)
            .background(gearGlassBackground(shape: shape))
            .overlay(
                shape
                    .strokeBorder(
                        Color.white.opacity(isExpanded ? 0.38 : 0.22),
                        lineWidth: 1
                    )
            )
            .clipShape(Circle())
            .contentShape(Circle())
    }

    @ViewBuilder
    private func gearGlassBackground(shape: Circle) -> some View {
        if #available(iOS 26.0, *) {
            shape
                .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isExpanded ? 0.36 : 0.22))
                .glassEffect(.regular.interactive(), in: shape)
        } else if #available(iOS 15.0, *) {
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isExpanded ? 0.38 : 0.24))
                )
        } else {
            shape
                .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isExpanded ? 0.9 : 0.76))
        }
    }
}

private struct SettingsGlassContainer: ViewModifier {
    let cornerRadius: CGFloat
    var isActive = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return content
            .background(glassBackground(shape: shape))
    }

    @ViewBuilder
    private func glassBackground(shape: RoundedRectangle) -> some View {
        if #available(iOS 26.0, *) {
            shape
                .fill(Color.white.opacity(isActive ? 0.1 : 0.06))
                .glassEffect(.regular.interactive(), in: shape)
        } else if #available(iOS 15.0, *) {
            shape
                .fill(.regularMaterial)
                .overlay(
                    shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isActive ? 0.34 : 0.2))
                )
        } else {
            shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isActive ? 0.9 : 0.76))
        }
    }
}

struct VersionPageView: View {
    let isDebugModeEnabled: Bool
    let onShowChangelog: () -> Void
    let onShowFAQ: () -> Void
    let onCopyDebugLog: () -> Void
    let onSetDebugMode: (Bool) -> Void
    @State private var isDebugPanelVisible = false
    @State private var displayedDebugModeEnabled: Bool

    init(
        isDebugModeEnabled: Bool,
        onShowChangelog: @escaping () -> Void,
        onShowFAQ: @escaping () -> Void,
        onCopyDebugLog: @escaping () -> Void,
        onSetDebugMode: @escaping (Bool) -> Void
    ) {
        self.isDebugModeEnabled = isDebugModeEnabled
        self.onShowChangelog = onShowChangelog
        self.onShowFAQ = onShowFAQ
        self.onCopyDebugLog = onCopyDebugLog
        self.onSetDebugMode = onSetDebugMode
        _displayedDebugModeEnabled = State(initialValue: isDebugModeEnabled)
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    dismissDebugPanel()
                }

            HStack(alignment: .center) {
                PageHeaderTitle(title: "关于")

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onShowChangelog()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .bold))
                        Text("更新日志")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(Color(UIColor.systemBlue))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                }
                .buttonStyle(GlassCapsuleButtonStyle())
                .padding(.trailing, 20)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 24) {
                Text("全局高刷悬浮窗")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(Color(UIColor.label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                VStack(spacing: 8) {
                    Text("当前版本")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))

                    Text("1.0.5")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(Color(UIColor.label))
                }

                Divider()
                    .padding(.horizontal, 52)

                VersionDescriptionView()

                ZStack(alignment: .top) {
                    HStack(spacing: 10) {
                        Spacer(minLength: 0)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismissDebugPanel()
                            onShowFAQ()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 17, weight: .bold))
                                Text("常见问题")
                                    .font(.system(size: 17, weight: .bold))
                            }
                            .foregroundColor(Color(UIColor.systemBlue))
                            .padding(.horizontal, 18)
                            .frame(height: 46)
                        }
                        .buttonStyle(GlassCapsuleButtonStyle())

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            toggleDebugPanel()
                        } label: {
                            DebugModeButton(isExpanded: isDebugPanelVisible)
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)
                    }

                    DebugModePanel(
                        isEnabled: displayedDebugModeEnabled,
                        onSetEnabled: setDebugMode
                    )
                    .offset(x: 28, y: -106)
                    .scaleEffect(isDebugPanelVisible ? 1 : 0.92, anchor: .bottomTrailing)
                    .opacity(isDebugPanelVisible ? 1 : 0)
                    .allowsHitTesting(isDebugPanelVisible)
                    .zIndex(4)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .padding(.top, 14)
                .zIndex(3)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismissDebugPanel()
                    onCopyDebugLog()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 16, weight: .bold))
                        Text("复制调试日志")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(Color(UIColor.systemBlue))
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                }
                .buttonStyle(GlassCapsuleButtonStyle())
                .opacity(displayedDebugModeEnabled ? 1 : 0)
                .allowsHitTesting(displayedDebugModeEnabled)
                .frame(height: 44)
            }
            .padding(.horizontal, 28)
            .animation(nil, value: displayedDebugModeEnabled)
        }
        .onChange(of: isDebugModeEnabled) { newValue in
            guard newValue != displayedDebugModeEnabled else { return }
            displayedDebugModeEnabled = newValue
        }
    }

    private func toggleDebugPanel() {
        withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)) {
            isDebugPanelVisible.toggle()
        }
    }

    private func dismissDebugPanel() {
        guard isDebugPanelVisible else { return }
        withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)) {
            isDebugPanelVisible = false
        }
    }

    private func setDebugMode(_ isEnabled: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedDebugModeEnabled = isEnabled
        }
        onSetDebugMode(isEnabled)
    }
}

private struct DebugModeButton: View {
    let isExpanded: Bool

    var body: some View {
        let shape = Circle()

        Image(systemName: "wrench.and.screwdriver.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(Color(UIColor.systemBlue))
            .frame(width: 44, height: 44)
            .background(debugGlassBackground(shape: shape))
            .overlay(
                shape.strokeBorder(
                    Color.white.opacity(isExpanded ? 0.38 : 0.22),
                    lineWidth: 1
                )
            )
            .clipShape(Circle())
            .contentShape(Circle())
    }

    @ViewBuilder
    private func debugGlassBackground(shape: Circle) -> some View {
        if #available(iOS 26.0, *) {
            shape
                .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isExpanded ? 0.36 : 0.22))
                .glassEffect(.regular.interactive(), in: shape)
        } else if #available(iOS 15.0, *) {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isExpanded ? 0.38 : 0.24)))
        } else {
            shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isExpanded ? 0.9 : 0.76))
        }
    }
}

private struct DebugModePanel: View {
    let isEnabled: Bool
    let onSetEnabled: (Bool) -> Void
    @State private var displayedIsEnabled: Bool

    init(isEnabled: Bool, onSetEnabled: @escaping (Bool) -> Void) {
        self.isEnabled = isEnabled
        self.onSetEnabled = onSetEnabled
        _displayedIsEnabled = State(initialValue: isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 16, weight: .bold))
                Text("调试模式")
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 10)
                Toggle("", isOn: immediateBinding)
                    .labelsHidden()
            }

            Text("开启后显示复制调试日志按钮")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(Color(UIColor.label))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 245)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
        .onChange(of: isEnabled) { newValue in
            guard newValue != displayedIsEnabled else { return }
            displayedIsEnabled = newValue
        }
    }

    private var immediateBinding: Binding<Bool> {
        Binding(
            get: { displayedIsEnabled },
            set: { newValue in
                guard newValue != displayedIsEnabled else { return }
                displayedIsEnabled = newValue
                onSetEnabled(newValue)
            }
        )
    }

    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Group {
            if #available(iOS 26.0, *) {
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.2))
                    .glassEffect(.regular.interactive(), in: shape)
            } else if #available(iOS 15.0, *) {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.28)))
            } else {
                shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.9))
            }
        }
    }
}

private struct VersionDescriptionView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("增加悬浮窗后台保活和修改侧边栏大小功能，")
            Text("挂在侧边栏可保持系统全局120hz，")
            Text("适配ios26液态玻璃特性")
            HStack(spacing: 0) {
                Text("原作者：")
                Link("CaiWanFeng", destination: URL(string: "https://github.com/CaiWanFeng/PiP")!)
                    .foregroundColor(Color(UIColor.systemBlue))
                Text("，完善：")
                Link("Yoroin", destination: URL(string: "http://www.coolapk.com/u/3233328")!)
                    .foregroundColor(Color(UIColor.systemBlue))
            }
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(Color(UIColor.secondaryLabel))
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PrimaryPiPButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(UIColor.systemBlue).opacity(0.18))

                    Image(systemName: "pip.enter")
                        .font(.system(size: 21, weight: .black))
                }
                .frame(width: 44, height: 44)

                Text(title)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity)

                Color.clear
                    .frame(width: 44, height: 44)
            }
            .foregroundColor(Color(UIColor.label))
            .padding(.horizontal, 16)
            .frame(maxWidth: 286)
            .frame(height: 72)
        }
        .buttonStyle(PrimaryLiquidGlassButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    var detail: String?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(UIColor.systemBlue).opacity(isEnabled ? 0.12 : 0.04))

                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                }
                .frame(width: 38, height: 38)

                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .foregroundColor(isEnabled ? Color(UIColor.label) : Color(UIColor.tertiaryLabel))
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
        }
        .buttonStyle(LiquidGlassButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let systemImage: String
    let isOn: Binding<Bool>
    @State private var displayedIsOn: Bool

    init(title: String, systemImage: String, isOn: Binding<Bool>) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        _displayedIsOn = State(initialValue: isOn.wrappedValue)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .bold))

                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(UIColor.label))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Text(displayedIsOn ? "下次打开自动恢复当前高度" : "每次打开使用默认高度")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: immediateBinding)
                .labelsHidden()
        }
        .foregroundColor(Color(UIColor.label))
        .padding(.horizontal, 18)
        .frame(height: 76)
        .background(settingsRowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onChange(of: isOn.wrappedValue) { newValue in
            guard newValue != displayedIsOn else { return }
            displayedIsOn = newValue
        }
    }

    private var immediateBinding: Binding<Bool> {
        Binding(
            get: { displayedIsOn },
            set: { newValue in
                guard newValue != displayedIsOn else { return }
                displayedIsOn = newValue
                isOn.wrappedValue = newValue
            }
        )
    }

    private var settingsRowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return Group {
            if #available(iOS 26.0, *) {
                shape
                    .fill(Color.white.opacity(0.08))
                    .glassEffect(.regular.interactive(), in: shape)
            } else if #available(iOS 15.0, *) {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.26))
                    )
            } else {
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.84))
            }
        }
    }
}

private struct SettingsLiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return configuration.label
            .background(settingsBackground(isPressed: configuration.isPressed, shape: shape))
            .overlay(
                shape.strokeBorder(
                    Color.white.opacity(configuration.isPressed ? 0.38 : 0.22),
                    lineWidth: 1
                )
            )
            .clipShape(shape)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.08 : 0.14),
                radius: configuration.isPressed ? 8 : 14,
                x: 0,
                y: configuration.isPressed ? 4 : 8
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: configuration.isPressed)
    }

    @ViewBuilder
    private func settingsBackground(isPressed: Bool, shape: RoundedRectangle) -> some View {
        if #available(iOS 26.0, *) {
            shape
                .fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.42 : 0.22))
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

private struct PrimaryLiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        return configuration.label
            .background(primaryBackground(isPressed: configuration.isPressed, shape: shape))
            .overlay(
                shape.strokeBorder(
                    Color(UIColor.systemBlue).opacity(configuration.isPressed ? 0.46 : 0.3),
                    lineWidth: 1.4
                )
            )
            .clipShape(shape)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .shadow(
                color: Color(UIColor.systemBlue).opacity(configuration.isPressed ? 0.12 : 0.24),
                radius: configuration.isPressed ? 10 : 20,
                x: 0,
                y: configuration.isPressed ? 5 : 12
            )
            .animation(.spring(response: 0.24, dampingFraction: 0.76), value: configuration.isPressed)
    }

    @ViewBuilder
    private func primaryBackground(
        isPressed: Bool,
        shape: RoundedRectangle
    ) -> some View {
        if #available(iOS 26.0, *) {
            shape
                .fill(Color(UIColor.systemBlue).opacity(isPressed ? 0.2 : 0.12))
                .glassEffect(.regular.interactive(), in: shape)
        } else if #available(iOS 15.0, *) {
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.fill(Color(UIColor.systemBlue).opacity(isPressed ? 0.24 : 0.14))
                )
        } else {
            shape
                .fill(Color(UIColor.systemBlue).opacity(isPressed ? 0.2 : 0.12))
        }
    }
}

private struct GlassCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()

        return configuration.label
            .background(glassBackground(isPressed: configuration.isPressed, shape: shape))
            .overlay(
                shape.strokeBorder(
                    Color.white.opacity(configuration.isPressed ? 0.34 : 0.22),
                    lineWidth: 1
                )
            )
            .clipShape(shape)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }

    @ViewBuilder
    private func glassBackground(
        isPressed: Bool,
        shape: Capsule
    ) -> some View {
        if #available(iOS 26.0, *) {
            shape
                .fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.4 : 0.22))
                .glassEffect(.regular.interactive(), in: shape)
        } else if #available(iOS 15.0, *) {
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.36 : 0.2))
                )
        } else {
            shape
                .fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.84 : 0.64))
        }
    }
}

private struct LiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        return configuration.label
            .background(glassBackground(isPressed: configuration.isPressed, shape: shape))
            .overlay(
                shape.strokeBorder(
                    Color.white.opacity(configuration.isPressed ? 0.36 : 0.22),
                    lineWidth: 1
                )
            )
            .clipShape(shape)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? 0.025 : 0)
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.08 : 0.14),
                radius: configuration.isPressed ? 8 : 16,
                x: 0,
                y: configuration.isPressed ? 4 : 10
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }

    @ViewBuilder
    private func glassBackground(
        isPressed: Bool,
        shape: RoundedRectangle
    ) -> some View {
        if #available(iOS 26.0, *) {
            shape
                .fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.42 : 0.22))
                .glassEffect(.regular.interactive(), in: shape)
        } else if #available(iOS 15.0, *) {
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.38 : 0.22))
                )
        } else {
            shape
                .fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.84 : 0.64))
        }
    }
}
