//
//  PiPViews.swift
//  pip_swift
//

import SwiftUI
import UIKit
import Combine

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
    @State private var isKeepAliveInfoVisible = false
    @State private var isPiPStatusInfoVisible = false

    let pipHeight: String
    let keepAliveMode: String
    let pipStatusTitle: String
    let pipStatusColor: UIColor
    let pipRunningDuration: String
    let pipStoppedAtText: String
    let pipRuntimeStartedAt: Date?
    let overlayResetToken: Int
    let isScrollingEnabled: Bool
    let isClockModeEnabled: Bool
    let remembersPiPHeight: Bool
    let isSettingsExpanded: Bool
    let onTogglePiP: () -> Void
    let onShowTutorial: () -> Void
    let onToggleStyle: () -> Void
    let onCustomizeHeight: () -> Void
    let onToggleScrolling: () -> Void
    let onSetClockMode: (Bool) -> Void
    let onToggleSettings: () -> Void
    let onDismissSettings: () -> Void
    let onSetRememberPiPHeight: (Bool) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeepAliveInfoIfNeeded()
                    dismissPiPStatusInfoIfNeeded()
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

                    pipStatusRow
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
                dismissKeepAliveInfoIfNeeded()
                dismissPiPStatusInfoIfNeeded()
                dismissSettingsIfNeeded()
            }

            keepAliveInfoPopover
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 116)
                .padding(.leading, 20)
                .opacity(isKeepAliveInfoVisible ? 1 : 0)
                .scaleEffect(isKeepAliveInfoVisible ? 1 : 0.92, anchor: .topLeading)
                .allowsHitTesting(isKeepAliveInfoVisible)
                .accessibilityHidden(!isKeepAliveInfoVisible)
                .zIndex(9)

            if isPiPStatusInfoVisible {
                pipStatusInfoPopover
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 406)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
                    .zIndex(9)
            }

            settingsPopover
                .padding(.top, 82)
                .padding(.trailing, 20)
                .opacity(isSettingsVisible ? 1 : 0)
                .scaleEffect(isSettingsVisible ? 1 : 0.92, anchor: .topTrailing)
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
        .onChange(of: overlayResetToken) { _ in
            dismissKeepAliveInfoIfNeeded()
            dismissPiPStatusInfoIfNeeded()
            dismissSettingsIfNeeded()
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("首页")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(Color(UIColor.label))

                HStack(spacing: 7) {
                    Text("当前保活模式")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismissSettingsIfNeeded()
                        withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)) {
                            isKeepAliveInfoVisible.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(keepAliveMode)
                                .font(.system(size: 13, weight: .bold))
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(Color(UIColor.systemBlue))
                        .padding(.leading, 10)
                        .padding(.trailing, 8)
                        .frame(height: 26)
                        .background(keepAliveModeBadgeBackground)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissKeepAliveInfoIfNeeded()
                dismissPiPStatusInfoIfNeeded()
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

    private var keepAliveModeBadgeBackground: some View {
        let shape = Capsule()
        return Group {
            if #available(iOS 26.0, *) {
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.22))
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

    private var keepAliveInfoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(keepAliveMode)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(Color(UIColor.systemBlue))

            Text(keepAliveModeDescription)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 282, alignment: .leading)
        .background(settingsPopoverBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
    }

    private var pipStatusRow: some View {
        HStack(spacing: 8) {
            Text("悬浮窗状态")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissKeepAliveInfoIfNeeded()
                dismissSettingsIfNeeded()
                withAnimation(.easeOut(duration: 0.16)) {
                    isPiPStatusInfoVisible.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(pipStatusTitle)
                        .font(.system(size: 13, weight: .bold))
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(Color(pipStatusColor))
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(height: 26)
                .background(keepAliveModeBadgeBackground)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var pipStatusInfoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(pipStatusTitle)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(Color(pipStatusColor))

            PiPRuntimeText(
                startedAt: pipRuntimeStartedAt,
                fallbackDuration: pipRunningDuration
            )
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundColor(Color(UIColor.secondaryLabel))
            .fixedSize(horizontal: false, vertical: true)

            Text("上次关闭时间：\(pipStoppedAtText)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 254, alignment: .leading)
        .background(settingsPopoverBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
    }

    private struct PiPRuntimeText: View {
        let startedAt: Date?
        let fallbackDuration: String
        @State private var now = Date()

        var body: some View {
            Text("已运行时间：\(displayText)")
                .onReceive(timer) { date in
                    guard startedAt != nil else { return }
                    now = date
                }
        }

        private var timer: Publishers.Autoconnect<Timer.TimerPublisher> {
            Timer.publish(every: 1, on: .main, in: .default).autoconnect()
        }

        private var displayText: String {
            guard let startedAt else {
                return fallbackDuration
            }
            let duration = max(0, now.timeIntervalSince(startedAt))
            let totalSeconds = max(0, Int(duration.rounded(.down)))
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
    }

    private var keepAliveModeDescription: String {
        keepAliveMode == "音频强保活"
            ? "音频强保活，强力保活方案，缺点较为耗电，且小部分场景可能影响音频，已默认不再使用，仅适合超强保活且不在意耗电的需求用户"
            : "新方案仅PiP保活，经实测较老方案更为省电，保活效果一致，并且解决音频冲突问题，优先推荐"
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Color(UIColor.label))

            SettingsToggleRow(
                title: "记忆悬浮窗高度",
                systemImage: "slider.horizontal.3",
                isOn: rememberHeightBinding,
                statusText: { isOn in
                    isOn ? "下次打开自动恢复当前高度" : "每次打开使用默认高度"
                }
            )

            Text("高度记忆为0.1pt时，可能无法直接启用悬浮窗，因此会自动恢复成44pt")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            SettingsToggleRow(
                title: "悬浮窗内容滚动",
                systemImage: "text.line.first.and.arrowtriangle.forward",
                isOn: scrollingBinding
            )

            Text("关闭后可停止文本滚动，仅防止晃眼，并不影响全局120")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            SettingsToggleRow(
                title: "文本悬浮窗",
                systemImage: "text.alignleft",
                isOn: textModeBinding,
                statusText: { isOn in
                    isOn ? "悬浮窗显示默认文本" : "悬浮窗显示当前时间"
                }
            )
        }
        .padding(16)
        .frame(width: 306)
        .background(settingsPopoverBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    private var settingsPopoverBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Group {
            if #available(iOS 26.0, *) {
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.08))
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

    private var rememberHeightBinding: Binding<Bool> {
        Binding(
            get: { remembersPiPHeight },
            set: { newValue in
                guard newValue != remembersPiPHeight else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeeded()
                onSetRememberPiPHeight(newValue)
            }
        )
    }

    private var scrollingBinding: Binding<Bool> {
        Binding(
            get: { isScrollingEnabled },
            set: { newValue in
                guard newValue != isScrollingEnabled else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeeded()
                onToggleScrolling()
            }
        )
    }

    private var textModeBinding: Binding<Bool> {
        Binding(
            get: { !isClockModeEnabled },
            set: { newValue in
                let shouldEnableClock = !newValue
                guard shouldEnableClock != isClockModeEnabled else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeeded()
                onSetClockMode(shouldEnableClock)
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

    private func dismissKeepAliveInfoIfNeeded() {
        guard isKeepAliveInfoVisible else { return }
        withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)) {
            isKeepAliveInfoVisible = false
        }
    }

    private func dismissPiPStatusInfoIfNeeded() {
        guard isPiPStatusInfoVisible else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            isPiPStatusInfoVisible = false
        }
    }

    private func runAfterDismissingSettings(_ action: @escaping () -> Void) {
        dismissKeepAliveInfoIfNeeded()
        dismissPiPStatusInfoIfNeeded()
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
        withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)) {
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
	                        Color(UIColor.separator).opacity(isExpanded ? 0.72 : 0.52),
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
                .fill(Color(UIColor.secondarySystemBackground).opacity(isExpanded ? 0.4 : 0.22))
                .glassEffect(.regular.interactive(), in: shape)
        } else if #available(iOS 15.0, *) {
            shape
	                .fill(.regularMaterial)
	                .overlay(
	                    shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isExpanded ? 0.56 : 0.4))
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
    let isIOS26AudioKeepAliveEnabled: Bool
    let debugPanelResetToken: Int
    let onShowChangelog: () -> Void
    let onShowFAQ: () -> Void
    let onCopyDiagnosticsLog: () -> Void
    let onToggleDebugDiagnostics: () -> Void
    let onSetDebugMode: (Bool) -> Void
    let onRequestEnableDebugMode: () -> Void
    let onSetIOS26AudioKeepAlive: (Bool) -> Void
    @State private var isDebugPanelVisible = false
    @State private var isKeepAliveInfoVisible = false
    @State private var displayedDebugModeEnabled: Bool
    @State private var displayedIOS26AudioKeepAliveEnabled: Bool

    init(
        isDebugModeEnabled: Bool,
        isIOS26AudioKeepAliveEnabled: Bool,
        debugPanelResetToken: Int,
        onShowChangelog: @escaping () -> Void,
        onShowFAQ: @escaping () -> Void,
        onCopyDiagnosticsLog: @escaping () -> Void,
        onToggleDebugDiagnostics: @escaping () -> Void,
        onSetDebugMode: @escaping (Bool) -> Void,
        onRequestEnableDebugMode: @escaping () -> Void,
        onSetIOS26AudioKeepAlive: @escaping (Bool) -> Void
    ) {
        self.isDebugModeEnabled = isDebugModeEnabled
        self.isIOS26AudioKeepAliveEnabled = isIOS26AudioKeepAliveEnabled
        self.debugPanelResetToken = debugPanelResetToken
        self.onShowChangelog = onShowChangelog
        self.onShowFAQ = onShowFAQ
        self.onCopyDiagnosticsLog = onCopyDiagnosticsLog
        self.onToggleDebugDiagnostics = onToggleDebugDiagnostics
        self.onSetDebugMode = onSetDebugMode
        self.onRequestEnableDebugMode = onRequestEnableDebugMode
        self.onSetIOS26AudioKeepAlive = onSetIOS26AudioKeepAlive
        _displayedDebugModeEnabled = State(initialValue: isDebugModeEnabled)
        _displayedIOS26AudioKeepAliveEnabled = State(initialValue: isIOS26AudioKeepAliveEnabled)
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    dismissDebugPanel()
                    dismissKeepAliveInfoPanel()
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

                    VStack(spacing: 7) {
                        Text("1.0.7")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(Color(UIColor.label))

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismissDebugPanel()
                            withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)) {
                                isKeepAliveInfoVisible.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(keepAliveModeTitle)
                                    .font(.system(size: 12, weight: .bold))
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(Color(UIColor.systemBlue))
                            .padding(.leading, 9)
                            .padding(.trailing, 7)
                            .frame(height: 24)
                            .background(versionFlagBackground)
                        }
                        .buttonStyle(.plain)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                }

                Divider()
                    .padding(.horizontal, 52)

                VersionDescriptionView()

                Color.clear
                    .frame(height: 46)
                    .padding(.top, 24)

                HStack(spacing: 10) {
                    CopyLogButton(
                        title: "复制诊断日志",
                        systemImage: "doc.text.magnifyingglass",
                        onLongPress: {
                            dismissDebugPanel()
                            onToggleDebugDiagnostics()
                        }
                    ) {
                        dismissDebugPanel()
                        onCopyDiagnosticsLog()
                    }
                }
                .opacity(displayedDebugModeEnabled ? 1 : 0)
                .allowsHitTesting(displayedDebugModeEnabled)
                .frame(height: 54)
            }
            .padding(.horizontal, 28)
            .padding(.top, 104)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(nil, value: displayedDebugModeEnabled)

            fixedFAQButtons
            fixedDebugPanel
            keepAliveInfoPanel
        }
        .onChange(of: isDebugModeEnabled) { newValue in
            guard newValue != displayedDebugModeEnabled else { return }
            displayedDebugModeEnabled = newValue
        }
        .onChange(of: isIOS26AudioKeepAliveEnabled) { newValue in
            guard newValue != displayedIOS26AudioKeepAliveEnabled else { return }
            displayedIOS26AudioKeepAliveEnabled = newValue
        }
        .onChange(of: debugPanelResetToken) { _ in
            dismissDebugPanel()
            dismissKeepAliveInfoPanel()
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

    private func dismissKeepAliveInfoPanel() {
        guard isKeepAliveInfoVisible else { return }
        withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)) {
            isKeepAliveInfoVisible = false
        }
    }

    private func setDebugMode(_ isEnabled: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedDebugModeEnabled = isEnabled
        }
        if isEnabled {
            displayedDebugModeEnabled = false
            onRequestEnableDebugMode()
        } else {
            onSetDebugMode(false)
        }
    }

    private func setIOS26AudioKeepAlive(_ isEnabled: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedIOS26AudioKeepAliveEnabled = isEnabled
        }
        onSetIOS26AudioKeepAlive(isEnabled)
    }

    private func openGitHubLink() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DiagnosticsRuntimeState.recordUserAction("打开GitHub")
        dismissKeepAliveInfoPanel()
        dismissDebugPanel()
        if let url = URL(string: "https://github.com/Yoroin/GlobalRefresh-PiP") {
            UIApplication.shared.open(url)
        }
    }

    private var keepAliveModeTitle: String {
        displayedIOS26AudioKeepAliveEnabled ? "音频强保活" : "PiP保活-低功耗"
    }

    private var keepAliveModeDescription: String {
        displayedIOS26AudioKeepAliveEnabled
            ? "音频强保活，强力保活方案，缺点较为耗电，且小部分场景可能影响音频，已默认不再使用，仅适合超强保活且不在意耗电的需求用户"
            : "新方案仅PiP保活，经实测较老方案更为省电，保活效果一致，并且解决音频冲突问题，优先推荐"
    }

    private var fixedFAQButtons: some View {
        GeometryReader { proxy in
            HStack(spacing: 10) {
                Button {
                    openGitHubLink()
                } label: {
                    GitHubLinkIcon()
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismissKeepAliveInfoPanel()
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
                    dismissKeepAliveInfoPanel()
                    toggleDebugPanel()
                } label: {
                    DebugModeButton(isExpanded: isDebugPanelVisible)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 46)
            .position(x: proxy.size.width / 2, y: fixedFAQRowCenterY)
        }
        .zIndex(4)
    }

    private var fixedDebugPanel: some View {
        GeometryReader { proxy in
            DebugModePanel(
                isEnabled: displayedDebugModeEnabled,
                isIOS26AudioKeepAliveEnabled: displayedIOS26AudioKeepAliveEnabled,
                onSetEnabled: setDebugMode,
                onSetIOS26AudioKeepAlive: setIOS26AudioKeepAlive
            )
            .scaleEffect(isDebugPanelVisible ? 1 : 0.92, anchor: .top)
            .opacity(isDebugPanelVisible ? 1 : 0)
            .allowsHitTesting(isDebugPanelVisible)
            .position(x: proxy.size.width / 2, y: fixedFAQRowCenterY + 54 + debugPanelCenterOffset)
        }
        .zIndex(5)
    }

    private var keepAliveInfoPanel: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text(keepAliveModeTitle)
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(Color(UIColor.systemBlue))

                Text(keepAliveModeDescription)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 282, alignment: .leading)
            .background(infoPanelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
            .scaleEffect(isKeepAliveInfoVisible ? 1 : 0.92, anchor: .top)
            .opacity(isKeepAliveInfoVisible ? 1 : 0)
            .allowsHitTesting(isKeepAliveInfoVisible)
            .position(x: proxy.size.width / 2, y: keepAliveInfoPanelCenterY)
        }
        .zIndex(6)
    }

    private var fixedFAQRowCenterY: CGFloat { 452 }

    private var keepAliveInfoPanelCenterY: CGFloat { 318 }

    private var debugPanelCenterOffset: CGFloat {
        displayedDebugModeEnabled ? 92 : 48
    }

    private var versionFlagBackground: some View {
        let shape = Capsule()
        return Group {
            if #available(iOS 26.0, *) {
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.22))
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

    private var infoPanelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Group {
            if #available(iOS 26.0, *) {
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.08))
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
	                    Color(UIColor.separator).opacity(isExpanded ? 0.72 : 0.52),
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
                .fill(.regularMaterial)
                .overlay(shape.fill(Color(UIColor.secondarySystemBackground).opacity(isExpanded ? 0.54 : 0.38)))
        } else {
            shape.fill(Color(UIColor.secondarySystemBackground).opacity(isExpanded ? 0.84 : 0.64))
        }
    }
}

private struct GitHubLinkIcon: View {
    var body: some View {
        let shape = Circle()

        Image("github-mark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundColor(Color(UIColor.label))
            .frame(width: 25, height: 25)
        .frame(width: 44, height: 44)
        .background(glassBackground(shape: shape))
        .overlay(
            shape.strokeBorder(
                Color(UIColor.separator).opacity(0.52),
                lineWidth: 1
            )
        )
        .clipShape(Circle())
        .contentShape(Circle())
        .accessibilityLabel("GitHub")
    }

    @ViewBuilder
    private func glassBackground(shape: Circle) -> some View {
        if #available(iOS 26.0, *) {
            shape
                .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.22))
                .glassEffect(.regular.interactive(), in: shape)
        } else if #available(iOS 15.0, *) {
            shape
                .fill(.regularMaterial)
                .overlay(shape.fill(Color(UIColor.secondarySystemBackground).opacity(0.38)))
        } else {
            shape.fill(Color(UIColor.secondarySystemBackground).opacity(0.64))
        }
    }
}

private struct CopyLogButton: View {
    let title: String
    let systemImage: String
    var onLongPress: (() -> Void)?
    let action: () -> Void
    @State private var didLongPress = false

    var body: some View {
        Button {
            if didLongPress {
                didLongPress = false
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            .foregroundColor(Color(UIColor.systemBlue))
            .padding(.horizontal, 12)
            .frame(maxWidth: 152)
            .frame(height: 44)
        }
        .buttonStyle(GlassCapsuleButtonStyle())
        .simultaneousGesture(
            LongPressGesture()
                .onEnded { _ in
                    didLongPress = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLongPress?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        didLongPress = false
                    }
                }
        )
    }
}

private struct DebugModePanel: View {
    let isEnabled: Bool
    let isIOS26AudioKeepAliveEnabled: Bool
    let onSetEnabled: (Bool) -> Void
    let onSetIOS26AudioKeepAlive: (Bool) -> Void
    @State private var displayedIsEnabled: Bool
    @State private var displayedIOS26AudioKeepAliveEnabled: Bool

    init(
        isEnabled: Bool,
        isIOS26AudioKeepAliveEnabled: Bool,
        onSetEnabled: @escaping (Bool) -> Void,
        onSetIOS26AudioKeepAlive: @escaping (Bool) -> Void
    ) {
        self.isEnabled = isEnabled
        self.isIOS26AudioKeepAliveEnabled = isIOS26AudioKeepAliveEnabled
        self.onSetEnabled = onSetEnabled
        self.onSetIOS26AudioKeepAlive = onSetIOS26AudioKeepAlive
        _displayedIsEnabled = State(initialValue: isEnabled)
        _displayedIOS26AudioKeepAliveEnabled = State(initialValue: isIOS26AudioKeepAliveEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 22, alignment: .center)
                Text("调试模式")
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 10)
                Toggle("", isOn: immediateBinding)
                    .labelsHidden()
            }
            .frame(height: 32)

            Text("开启后显示调试、耗电和系统指标日志按钮")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if displayedIsEnabled {
                Divider()
                    .opacity(0.42)

                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 22, alignment: .center)
                    Text("保活方案切换")
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 10)
                    Toggle("", isOn: lowPowerPiPBinding)
                        .labelsHidden()
                }
                .frame(height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("开启：新方案仅PiP保活，经实测较老方案更为省电，保活效果一致，并且解决音频冲突问题，优先推荐")
                    Text("关闭：音频强保活，强力保活方案，缺点较为耗电，且小部分场景可能影响音频，已默认不再使用，仅适合超强保活且不在意耗电的需求用户")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundColor(Color(UIColor.label))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 300)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
        .onChange(of: isEnabled) { newValue in
            guard newValue != displayedIsEnabled else { return }
            displayedIsEnabled = newValue
        }
        .onChange(of: isIOS26AudioKeepAliveEnabled) { newValue in
            guard newValue != displayedIOS26AudioKeepAliveEnabled else { return }
            displayedIOS26AudioKeepAliveEnabled = newValue
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

    private var lowPowerPiPBinding: Binding<Bool> {
        Binding(
            get: { !displayedIOS26AudioKeepAliveEnabled },
            set: { newValue in
                let audioKeepAliveEnabled = !newValue
                guard audioKeepAliveEnabled != displayedIOS26AudioKeepAliveEnabled else { return }
                displayedIOS26AudioKeepAliveEnabled = audioKeepAliveEnabled
                onSetIOS26AudioKeepAlive(audioKeepAliveEnabled)
            }
        )
    }

    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Group {
            if #available(iOS 26.0, *) {
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.08))
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
    let statusText: ((Bool) -> String)?
    @State private var displayedIsOn: Bool

    init(
        title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        statusText: ((Bool) -> String)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.statusText = statusText
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

                if let statusText {
                    Text(statusText(displayedIsOn))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: immediateBinding)
                .labelsHidden()
        }
        .foregroundColor(Color(UIColor.label))
        .padding(.horizontal, 4)
        .frame(height: statusText == nil ? 52 : 76)
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
	                    legacyStrokeColor(isPressed: configuration.isPressed),
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
	                .fill(.regularMaterial)
	                .overlay(
	                    shape.fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.54 : 0.38))
	                )
        } else {
            shape
                .fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.84 : 0.64))
        }
    }

    private func legacyStrokeColor(isPressed: Bool) -> Color {
        if #available(iOS 26.0, *) {
            return Color.white.opacity(isPressed ? 0.34 : 0.22)
        }
        return Color(UIColor.separator).opacity(isPressed ? 0.72 : 0.52)
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
