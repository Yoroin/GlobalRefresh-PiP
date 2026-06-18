//
//  PiPViews.swift
//  pip_swift
//

import SwiftUI
import UIKit
import Combine

private struct AdaptiveLayoutMetrics {
    static var current: AdaptiveLayoutMetrics {
        AdaptiveLayoutMetrics(size: UIScreen.main.bounds.size)
    }

    let size: CGSize

    private var shortSide: CGFloat { min(size.width, size.height) }
    private var longSide: CGFloat { max(size.width, size.height) }

    var isNarrow: Bool { shortSide <= 340 }
    var isCompactHeight: Bool { longSide <= 620 }
    var isCompact: Bool { isNarrow || isCompactHeight }

    var headerTitleSize: CGFloat { isCompact ? 30 : 34 }
    var headerHorizontalPadding: CGFloat { isNarrow ? 16 : 20 }
    var headerTopPadding: CGFloat { isCompact ? 12 : 22 }
    var headerBottomPadding: CGFloat { isCompact ? 6 : 12 }

    var homeOuterSpacing: CGFloat { isCompact ? 10 : 18 }
    var homeActionSpacing: CGFloat { isCompact ? 8 : 14 }
    var homeActionHorizontalPadding: CGFloat { isNarrow ? 12 : 20 }
    var homeContainerHorizontalPadding: CGFloat { isNarrow ? 4 : 8 }
    var homePrimaryBottomPadding: CGFloat { isCompact ? 16 : 40 }
    var homePrimaryHorizontalPadding: CGFloat { isNarrow ? 18 : 28 }
    var homeKeepAliveInfoTop: CGFloat { isCompact ? 98 : 116 }
    var homeSettingsTop: CGFloat { isCompact ? 66 : 82 }
    var homeSettingsTrailing: CGFloat { isNarrow ? 12 : 20 }
    var homePiPStatusInfoTop: CGFloat {
        isCompact ? min(354, max(300, longSide - 214)) : 406
    }

    var versionContentTopPadding: CGFloat { isCompact ? 70 : 104 }
    var versionHorizontalPadding: CGFloat { isNarrow ? 18 : 28 }
    var versionMainSpacing: CGFloat { isCompact ? 13 : 24 }
    var versionTitleSize: CGFloat { isCompact ? 28 : 34 }
    var versionNumberSize: CGFloat { isCompact ? 27 : 32 }
    var versionDividerPadding: CGFloat { isNarrow ? 34 : 52 }
    var versionReservedControlsHeight: CGFloat { isCompact ? 0 : 46 }
    var versionReservedControlsTopPadding: CGFloat { isCompact ? 0 : 24 }
    var versionCopyLogRowHeight: CGFloat { isCompact ? 44 : 54 }
    var versionFAQRowCenterY: CGFloat { isCompact ? min(410, max(372, longSide - 158)) : 452 }
    var versionKeepAliveInfoCenterY: CGFloat { isCompact ? 266 : 318 }
    var panelWidth300: CGFloat { min(300, shortSide - 24) }
    var homeSettingsPanelWidth: CGFloat { min(270, shortSide - 24) }
    var settingsVisibleOptionsHeight: CGFloat {
        let rowHeight: CGFloat = isCompact ? 66 : 72
        return rowHeight * 4.5 + 60
    }
    var infoPanelWidth282: CGFloat { min(282, shortSide - 24) }
    var infoPanelWidth254: CGFloat { min(254, shortSide - 24) }

}

struct PageHeaderTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: layout.headerTitleSize, weight: .black, design: .rounded))
            .foregroundColor(Color(UIColor.label))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.headerHorizontalPadding)
            .padding(.top, layout.headerTopPadding)
            .padding(.bottom, layout.headerBottomPadding)
    }

    private var layout: AdaptiveLayoutMetrics { .current }
}

struct PiPHomeView: View {
    @Binding var isPiPActive: Bool
    @Binding var isPiPStatusInfoVisible: Bool
    @State private var isSettingsVisible = false
    @State private var isKeepAliveInfoVisible = false
    @State private var isNotificationFrequencyInfoVisible = false
    @State private var isPiPStoppedNotificationInfoVisible = false

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
    let isDarkModeForced: Bool
    let isPiPStoppedNotificationEnabled: Bool
    let isBackgroundInterruptionNotificationEnabled: Bool
    let keepAliveNotificationFrequency: KeepAliveNotificationProbeFrequency
    let keepsPiPStatusInfoPersistent: Bool
    let remembersPiPHeight: Bool
    let isSettingsExpanded: Bool
    let onTogglePiP: () -> Void
    let onShowTutorial: () -> Void
    let onToggleStyle: () -> Void
    let onCustomizeHeight: () -> Void
    let onToggleScrolling: () -> Void
    let onSetClockMode: (Bool) -> Void
    let onSetDarkModeForced: (Bool) -> Void
    let onSetPiPStoppedNotificationEnabled: (Bool) -> Void
    let onSetBackgroundInterruptionNotificationEnabled: (Bool) -> Void
    let onSetKeepAliveNotificationFrequency: (KeepAliveNotificationProbeFrequency) -> Void
    let onSetPiPStatusInfoPersistent: (Bool) -> Void
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
                    dismissPiPStatusInfoIfNeededRespectingPersistence()
                    dismissNotificationFrequencyInfoIfNeeded()
                    dismissPiPStoppedNotificationInfoIfNeeded()
                    dismissSettingsIfNeeded()
                }

            VStack(alignment: .leading, spacing: layout.homeOuterSpacing) {
                homeHeader

                VStack(spacing: layout.homeActionSpacing) {
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
                .padding(.horizontal, layout.homeActionHorizontalPadding)

                Spacer(minLength: layout.isCompact ? 8 : 18)

                PrimaryPiPButton(title: isPiPActive ? "关闭悬浮窗" : "开启悬浮窗") {
                    runAfterDismissingSettings(onTogglePiP)
                }
                    .frame(maxWidth: 286)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, layout.homePrimaryHorizontalPadding)
                    .padding(.bottom, layout.homePrimaryBottomPadding)
            }
            .padding(.horizontal, layout.homeContainerHorizontalPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeepAliveInfoIfNeeded()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                dismissNotificationFrequencyInfoIfNeeded()
                dismissPiPStoppedNotificationInfoIfNeeded()
                dismissSettingsIfNeeded()
            }

            keepAliveInfoPopover
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, layout.homeKeepAliveInfoTop)
                .padding(.leading, layout.headerHorizontalPadding)
                .opacity(isKeepAliveInfoVisible ? 1 : 0)
                .scaleEffect(isKeepAliveInfoVisible ? 1 : 0.92, anchor: .topLeading)
                .allowsHitTesting(isKeepAliveInfoVisible)
                .accessibilityHidden(!isKeepAliveInfoVisible)
                .zIndex(9)

            if isPiPStatusInfoVisible {
                pipStatusInfoPopover
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, layout.homePiPStatusInfoTop)
                    .padding(.horizontal, layout.headerHorizontalPadding)
                    .transition(.opacity)
                    .zIndex(9)
            }

            if isNotificationFrequencyInfoVisible {
                notificationFrequencyPopover
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, layout.headerHorizontalPadding)
                    .transition(.opacity)
                    .zIndex(9)
            }

            if isPiPStoppedNotificationInfoVisible {
                pipStoppedNotificationPopover
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, layout.headerHorizontalPadding)
                    .transition(.opacity)
                    .zIndex(9)
            }

            settingsPopover
                .padding(.top, layout.homeSettingsTop)
                .padding(.trailing, layout.homeSettingsTrailing)
                .opacity(isSettingsVisible ? 1 : 0)
                .scaleEffect(isSettingsVisible ? 1 : 0.985, anchor: .topTrailing)
                .blur(radius: isSettingsVisible ? 0 : 6)
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
            dismissPiPStatusInfoIfNeededRespectingPersistence()
            dismissNotificationFrequencyInfoIfNeeded()
            dismissPiPStoppedNotificationInfoIfNeeded()
            dismissSettingsIfNeeded()
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("首页")
                    .font(.system(size: layout.headerTitleSize, weight: .black, design: .rounded))
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
                            Image(systemName: "questionmark.circle.fill")
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
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                dismissNotificationFrequencyInfoIfNeeded()
                onToggleSettings()
            } label: {
                SettingsGearButton(title: "更多设置", isExpanded: isSettingsVisible)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, layout.headerHorizontalPadding)
        .padding(.top, layout.headerTopPadding)
        .padding(.bottom, layout.headerBottomPadding)
    }

    private var keepAliveModeBadgeBackground: AnyView {
        let shape = Capsule()
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.22))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.36)))
                .overlay(shape.strokeBorder(legacyGlassStrokeColor, lineWidth: 1))
        )
    }

    private var statusBadgeBackground: some View {
        let shape = Capsule()
        return shape
            .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.62))
            .overlay(
                shape.strokeBorder(
                    Color(pipStatusColor).opacity(isPiPActive ? 0.28 : 0.16),
                    lineWidth: 1
                )
            )
    }

    private var notificationBadgeBackground: some View {
        let shape = Capsule()
        return shape
            .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.62))
            .overlay(
                shape.strokeBorder(notificationBadgeColor.opacity(isAnyNotificationEnabled ? 0.24 : 0.18), lineWidth: 1)
            )
    }

    private var notificationBadgeColor: Color {
        isAnyNotificationEnabled
            ? Color(UIColor.systemGreen)
            : Color(UIColor.secondaryLabel)
    }

    private var isAnyNotificationEnabled: Bool {
        isPiPStoppedNotificationEnabled || isBackgroundInterruptionNotificationEnabled
    }

    private var keepAliveInfoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
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
        .frame(width: layout.infoPanelWidth282, alignment: .leading)
        .background(settingsPopoverBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(adaptiveGlassStrokeColor, lineWidth: 1)
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
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(Color(pipStatusColor))
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(height: 26)
                .background(statusBadgeBackground)
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissKeepAliveInfoIfNeeded()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                dismissSettingsIfNeeded()
                if isBackgroundInterruptionNotificationEnabled {
                    dismissPiPStoppedNotificationInfoIfNeeded()
                    withAnimation(.easeOut(duration: 0.16)) {
                        isNotificationFrequencyInfoVisible.toggle()
                    }
                } else if isPiPStoppedNotificationEnabled {
                    dismissNotificationFrequencyInfoIfNeeded()
                    withAnimation(.easeOut(duration: 0.16)) {
                        isPiPStoppedNotificationInfoVisible.toggle()
                    }
                } else {
                    dismissNotificationFrequencyInfoIfNeeded()
                    dismissPiPStoppedNotificationInfoIfNeeded()
                }
            } label: {
                keepAliveNotificationBadge
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var keepAliveNotificationBadge: some View {
        HStack(spacing: 3) {
            Text("通知")
                .font(.system(size: 11, weight: .bold))
            Image(systemName: isAnyNotificationEnabled ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(notificationBadgeColor)
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(height: 22)
        .background(notificationBadgeBackground)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private var notificationFrequencyPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("后台中断通知模式")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(Color(UIColor.systemGreen))

            Text("当前：\(keepAliveNotificationFrequency.title)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))

                VStack(spacing: 7) {
                    ForEach(KeepAliveNotificationProbeFrequency.allCases, id: \.self) { frequency in
                        notificationFrequencyButton(frequency)
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: layout.infoPanelWidth282, alignment: .leading)
        .background(settingsPopoverBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(adaptiveGlassStrokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
    }

    private var pipStoppedNotificationPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.on.rectangle.slash.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("被挤通知已开启")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(Color(UIColor.systemGreen))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: layout.infoPanelWidth254, alignment: .leading)
        .background(settingsPopoverBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(adaptiveGlassStrokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
    }

    private func notificationFrequencyButton(_ frequency: KeepAliveNotificationProbeFrequency) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSetKeepAliveNotificationFrequency(frequency)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: keepAliveNotificationFrequency == frequency ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(
                        keepAliveNotificationFrequency == frequency
                            ? Color(UIColor.systemGreen)
                            : Color(UIColor.tertiaryLabel)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(frequency.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(UIColor.label))
                    Text(frequency.detail)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        keepAliveNotificationFrequency == frequency
                            ? Color(UIColor.systemGreen).opacity(0.12)
                            : Color(UIColor.secondarySystemGroupedBackground).opacity(0.18)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var pipStatusInfoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
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
        .frame(width: layout.infoPanelWidth254, alignment: .leading)
        .background(settingsPopoverBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(adaptiveGlassStrokeColor, lineWidth: 1)
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
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
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
        VStack(alignment: .leading, spacing: 7) {
            Text("高级设置")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Color(UIColor.label))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    SettingsToggleRow(
                        title: "记忆悬浮窗高度",
                        systemImage: "slider.horizontal.3",
                        isOn: rememberHeightBinding,
                        statusText: { isOn in
                            isOn ? "下次打开自动恢复当前高度，0.1pt自动恢复44pt" : "每次打开使用默认高度"
                        }
                    )

                    Divider()
                        .opacity(0.42)

                    SettingsToggleRow(
                        title: "悬浮窗被挤通知",
                        systemImage: "rectangle.on.rectangle.slash.fill",
                        isOn: pipStoppedNotificationBinding,
                        statusText: { _ in
                            "被其他画中画应用挤掉时发送通知"
                        }
                    )

                    Divider()
                        .opacity(0.42)

                    SettingsToggleRow(
                        title: "后台中断通知",
                        titleSuffix: "beta",
                        systemImage: "bell.badge.fill",
                        isOn: backgroundInterruptionNotificationBinding,
                        statusText: { _ in
                            "轮询检测后台中断，可能晚报或者误报，用于检测后台被杀的场景"
                        }
                    )

                    Divider()
                        .opacity(0.42)

                    SettingsToggleRow(
                        title: "悬浮窗状态常驻",
                        systemImage: "pin.fill",
                        isOn: pipStatusInfoPersistentBinding,
                        statusText: { isOn in
                            isOn ? "使首页的悬浮窗状态时间常驻展示" : "关闭后点开状态时间会按普通弹窗自动收起"
                        }
                    )

                    Divider()
                        .opacity(0.42)

                    SettingsToggleRow(
                        title: "时间悬浮窗",
                        systemImage: "clock.fill",
                        isOn: clockModeBinding,
                        statusText: { isOn in
                            isOn ? "打开后悬浮窗显示时分秒" : "关闭后恢复原有文本滚动内容"
                        }
                    )

                    Divider()
                        .opacity(0.42)

                    SettingsToggleRow(
                        title: "悬浮窗内容滚动",
                        systemImage: "text.alignleft",
                        isOn: scrollingBinding,
                        isEnabled: !isClockModeEnabled,
                        statusText: { _ in
                            "关闭后可停止文本滚动，仅防止晃眼，并不影响全局120，仅文本悬浮窗生效"
                        }
                    )

                    Divider()
                        .opacity(0.42)

                    SettingsToggleRow(
                        title: "强制深色模式",
                        systemImage: "moon.fill",
                        isOn: darkModeBinding,
                        controlStyle: .checkbox,
                        statusText: { isOn in
                            isOn ? "开启后固定使用深色模式" : "默认关闭，跟随系统设置"
                        }
                    )
                }
            }
            .frame(maxHeight: layout.settingsVisibleOptionsHeight)
        }
        .padding(14)
        .frame(width: layout.homeSettingsPanelWidth)
        .background(settingsPopoverBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(adaptiveGlassStrokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    private var settingsPopoverBackground: AnyView {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.08))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.28)))
        )
    }

    private var rememberHeightBinding: Binding<Bool> {
        Binding(
            get: { remembersPiPHeight },
            set: { newValue in
                guard newValue != remembersPiPHeight else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                onSetRememberPiPHeight(newValue)
            }
        )
    }

    private var scrollingBinding: Binding<Bool> {
        Binding(
            get: { isScrollingEnabled },
            set: { newValue in
                guard !isClockModeEnabled else { return }
                guard newValue != isScrollingEnabled else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                onToggleScrolling()
            }
        )
    }

    private var darkModeBinding: Binding<Bool> {
        Binding(
            get: { isDarkModeForced },
            set: { newValue in
                guard newValue != isDarkModeForced else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    onSetDarkModeForced(newValue)
                }
            }
        )
    }

    private var pipStoppedNotificationBinding: Binding<Bool> {
        Binding(
            get: { isPiPStoppedNotificationEnabled },
            set: { newValue in
                guard newValue != isPiPStoppedNotificationEnabled else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                onSetPiPStoppedNotificationEnabled(newValue)
            }
        )
    }

    private var backgroundInterruptionNotificationBinding: Binding<Bool> {
        Binding(
            get: { isBackgroundInterruptionNotificationEnabled },
            set: { newValue in
                guard newValue != isBackgroundInterruptionNotificationEnabled else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                onSetBackgroundInterruptionNotificationEnabled(newValue)
            }
        )
    }

    private var clockModeBinding: Binding<Bool> {
        Binding(
            get: { isClockModeEnabled },
            set: { newValue in
                guard newValue != isClockModeEnabled else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                onSetClockMode(newValue)
            }
        )
    }

    private var pipStatusInfoPersistentBinding: Binding<Bool> {
        Binding(
            get: { keepsPiPStatusInfoPersistent },
            set: { newValue in
                guard newValue != keepsPiPStatusInfoPersistent else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if !newValue {
                    dismissPiPStatusInfoIfNeeded(force: true)
                }
                onSetPiPStatusInfoPersistent(newValue)
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
        dismissPiPStatusInfoIfNeeded(force: false)
    }

    private func dismissPiPStatusInfoIfNeededRespectingPersistence() {
        guard !keepsPiPStatusInfoPersistent else { return }
        dismissPiPStatusInfoIfNeeded(force: false)
    }

    private func dismissPiPStatusInfoIfNeeded(force: Bool) {
        guard force || !keepsPiPStatusInfoPersistent else { return }
        guard isPiPStatusInfoVisible else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            isPiPStatusInfoVisible = false
        }
    }

    private func dismissNotificationFrequencyInfoIfNeeded() {
        guard isNotificationFrequencyInfoVisible else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            isNotificationFrequencyInfoVisible = false
        }
    }

    private func dismissPiPStoppedNotificationInfoIfNeeded() {
        guard isPiPStoppedNotificationInfoVisible else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            isPiPStoppedNotificationInfoVisible = false
        }
    }

    private func runAfterDismissingSettings(_ action: @escaping () -> Void) {
        dismissKeepAliveInfoIfNeeded()
        dismissPiPStatusInfoIfNeededRespectingPersistence()
        dismissNotificationFrequencyInfoIfNeeded()
        dismissPiPStoppedNotificationInfoIfNeeded()
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
        withAnimation(.easeInOut(duration: 0.18)) {
            isSettingsVisible = isVisible
        }
    }

    private var layout: AdaptiveLayoutMetrics { .current }
}

private struct SettingsGearButton: View {
    let title: String
    let isExpanded: Bool

    var body: some View {
        let shape = Capsule()

        HStack(spacing: 7) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .bold))
            Text(title)
                .font(.system(size: layout.isCompact ? 15 : 16, weight: .bold))
                .lineLimit(1)
        }
            .foregroundColor(Color(UIColor.label))
            .padding(.leading, 12)
            .padding(.trailing, 13)
            .frame(height: 42)
            .background(gearGlassBackground(shape: shape))
            .overlay(
                shape
                    .strokeBorder(
	                        Color(UIColor.separator).opacity(isExpanded ? 0.72 : 0.52),
                        lineWidth: 1
                    )
            )
            .clipShape(shape)
            .contentShape(shape)
    }

    private func gearGlassBackground(shape: Capsule) -> AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemBackground).opacity(isExpanded ? 0.4 : 0.22))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.regularMaterial)
                .overlay(
                    shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isExpanded ? 0.56 : 0.4))
                )
        )
    }

    private var layout: AdaptiveLayoutMetrics { .current }
}

private struct SettingsGlassContainer: ViewModifier {
    let cornerRadius: CGFloat
    var isActive = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return content
            .background(glassBackground(shape: shape))
    }

    private func glassBackground(shape: RoundedRectangle) -> AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color.white.opacity(isActive ? 0.1 : 0.06))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.regularMaterial)
                .overlay(
                    shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isActive ? 0.34 : 0.2))
                )
        )
    }
}

private struct DebugModeStatusLabelFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        guard next != .zero else { return }
        value = next
    }
}

struct VersionPageView: View {
    let isDebugModeEnabled: Bool
    @Binding var isDebugPanelVisible: Bool
    let isIOS26AudioKeepAliveEnabled: Bool
    let isDebugDiagnosticsEnabled: Bool
    let debugPanelResetToken: Int
    let onShowChangelog: () -> Void
    let onShowFAQ: () -> Void
    let onCopyDiagnosticsLog: () -> Void
    let onSetDebugMode: (Bool) -> Void
    let onRequestEnableDebugMode: () -> Void
    let onSetIOS26AudioKeepAlive: (Bool) -> Void
    @State private var isKeepAliveInfoVisible = false
    @State private var isBetaInfoVisible = false
    @State private var isDebugDiagnosticsInfoVisible = false
    @State private var displayedDebugModeEnabled: Bool
    @State private var displayedIOS26AudioKeepAliveEnabled: Bool
    @State private var displayedDebugDiagnosticsEnabled: Bool
    @State private var debugModeStatusLabelFrame: CGRect = .zero

    init(
        isDebugModeEnabled: Bool,
        isDebugPanelVisible: Binding<Bool>,
        isIOS26AudioKeepAliveEnabled: Bool,
        isDebugDiagnosticsEnabled: Bool,
        debugPanelResetToken: Int,
        onShowChangelog: @escaping () -> Void,
        onShowFAQ: @escaping () -> Void,
        onCopyDiagnosticsLog: @escaping () -> Void,
        onSetDebugMode: @escaping (Bool) -> Void,
        onRequestEnableDebugMode: @escaping () -> Void,
        onSetIOS26AudioKeepAlive: @escaping (Bool) -> Void
    ) {
        self.isDebugModeEnabled = isDebugModeEnabled
        _isDebugPanelVisible = isDebugPanelVisible
        self.isIOS26AudioKeepAliveEnabled = isIOS26AudioKeepAliveEnabled
        self.isDebugDiagnosticsEnabled = isDebugDiagnosticsEnabled
        self.debugPanelResetToken = debugPanelResetToken
        self.onShowChangelog = onShowChangelog
        self.onShowFAQ = onShowFAQ
        self.onCopyDiagnosticsLog = onCopyDiagnosticsLog
        self.onSetDebugMode = onSetDebugMode
        self.onRequestEnableDebugMode = onRequestEnableDebugMode
        self.onSetIOS26AudioKeepAlive = onSetIOS26AudioKeepAlive
        _displayedDebugModeEnabled = State(initialValue: isDebugModeEnabled)
        _displayedIOS26AudioKeepAliveEnabled = State(initialValue: isIOS26AudioKeepAliveEnabled)
        _displayedDebugDiagnosticsEnabled = State(initialValue: isDebugDiagnosticsEnabled)
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    dismissDebugPanel()
                    dismissKeepAliveInfoPanel()
                    dismissBetaInfoPanel()
                    dismissDebugDiagnosticsInfoPanel()
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

            VStack(spacing: layout.versionMainSpacing) {
                Text("全局高刷悬浮窗")
                    .font(.system(size: layout.versionTitleSize, weight: .black, design: .rounded))
                    .foregroundColor(Color(UIColor.label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                VStack(spacing: 8) {
                    Text("当前版本")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))

                    VStack(spacing: 7) {
                        HStack(spacing: 8) {
                            Text("1.0.8")
                                .font(.system(size: layout.versionNumberSize, weight: .bold, design: .rounded))
                                .foregroundColor(Color(UIColor.label))
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismissDebugPanel()
                            dismissDebugDiagnosticsInfoPanel()
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
                    .padding(.horizontal, layout.versionDividerPadding)

                VersionDescriptionView(isCompact: layout.isCompact)

                Color.clear
                    .frame(height: layout.versionReservedControlsHeight)
                    .padding(.top, layout.versionReservedControlsTopPadding)

                if !layout.isCompact {
                    copyDiagnosticsLogButton
                        .frame(height: layout.versionCopyLogRowHeight)
                    if shouldShowDebugModeStatus {
                        debugStatusLabels
                    }
                }
            }
            .padding(.horizontal, layout.versionHorizontalPadding)
            .padding(.top, layout.versionContentTopPadding)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(nil, value: displayedDebugModeEnabled)

            fixedFAQButtons
            if layout.isCompact {
                fixedCompactDiagnosticsControls
            }
            fixedDebugPanel
            keepAliveInfoPanel
            betaInfoPanel
            debugDiagnosticsInfoPanel
        }
        .onChange(of: isDebugModeEnabled) { newValue in
            guard newValue != displayedDebugModeEnabled else { return }
            displayedDebugModeEnabled = newValue
            if !newValue {
                dismissDebugDiagnosticsInfoPanel()
            }
        }
        .onChange(of: isIOS26AudioKeepAliveEnabled) { newValue in
            guard newValue != displayedIOS26AudioKeepAliveEnabled else { return }
            displayedIOS26AudioKeepAliveEnabled = newValue
        }
        .onChange(of: isDebugDiagnosticsEnabled) { newValue in
            guard newValue != displayedDebugDiagnosticsEnabled else { return }
            displayedDebugDiagnosticsEnabled = newValue
            if !newValue {
                dismissDebugDiagnosticsInfoPanel()
            }
        }
        .onChange(of: debugPanelResetToken) { _ in
            dismissDebugPanel()
            dismissKeepAliveInfoPanel()
            dismissBetaInfoPanel()
            dismissDebugDiagnosticsInfoPanel()
        }
        .onPreferenceChange(DebugModeStatusLabelFrameKey.self) { frame in
            guard frame != .zero else { return }
            debugModeStatusLabelFrame = frame
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

    private func dismissBetaInfoPanel() {
        guard isBetaInfoVisible else { return }
        withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)) {
            isBetaInfoVisible = false
        }
    }

    private func dismissDebugDiagnosticsInfoPanel() {
        guard isDebugDiagnosticsInfoVisible else { return }
        withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)) {
            isDebugDiagnosticsInfoVisible = false
        }
    }

    private func setDebugMode(_ isEnabled: Bool) {
        if isEnabled {
            onRequestEnableDebugMode()
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedDebugModeEnabled = false
            }
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
        dismissBetaInfoPanel()
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

    private var copyDiagnosticsLogButton: some View {
        HStack(spacing: 10) {
            CopyLogButton(
                title: "复制诊断日志",
                systemImage: "doc.text.magnifyingglass"
            ) {
                dismissDebugPanel()
                dismissKeepAliveInfoPanel()
                dismissDebugDiagnosticsInfoPanel()
                onCopyDiagnosticsLog()
            }
        }
        .opacity(displayedDebugModeEnabled ? 1 : 0)
        .allowsHitTesting(displayedDebugModeEnabled)
    }

    private var debugModeStatusLabel: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismissDebugPanel()
            dismissKeepAliveInfoPanel()
            withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)) {
                isDebugDiagnosticsInfoVisible.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text("调试模式已开启")
                    .font(.system(size: 12, weight: .bold))
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(Color(UIColor.systemRed))
            .padding(.leading, 9)
            .padding(.trailing, 7)
            .frame(height: 24)
            .background(diagnosticsStatusBackground)
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DebugModeStatusLabelFrameKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        )
    }

    private var debugStatusLabels: some View {
        debugModeStatusLabel
    }

    private var fixedCopyDiagnosticsLogButton: some View {
        GeometryReader { proxy in
            copyDiagnosticsLogButton
                .frame(height: layout.versionCopyLogRowHeight)
                .position(x: proxy.size.width / 2, y: fixedFAQRowCenterY - 58)
        }
        .zIndex(4.5)
    }

    private var fixedCompactDiagnosticsControls: some View {
        GeometryReader { proxy in
            VStack(spacing: 6) {
                copyDiagnosticsLogButton
                    .frame(height: layout.versionCopyLogRowHeight)
                if shouldShowDebugModeStatus {
                    debugStatusLabels
                }
            }
            .frame(height: compactDiagnosticsControlsHeight)
            .position(x: proxy.size.width / 2, y: fixedFAQRowCenterY - compactDiagnosticsControlsYOffset)
        }
        .zIndex(4.55)
    }

    private var debugDiagnosticsInfoPanel: some View {
        GeometryReader { proxy in
            debugDiagnosticsInfoPanelContent
                .scaleEffect(isDebugDiagnosticsInfoVisible ? 1 : 0.92, anchor: .bottom)
                .opacity(isDebugDiagnosticsInfoVisible ? 1 : 0)
                .allowsHitTesting(isDebugDiagnosticsInfoVisible)
                .position(
                    x: proxy.size.width / 2,
                    y: debugDiagnosticsInfoPanelCenterY(in: proxy)
                )
        }
        .zIndex(7)
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
            .position(x: proxy.size.width / 2, y: debugPanelCenterY)
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
            .frame(width: layout.infoPanelWidth282, alignment: .leading)
            .background(infoPanelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(adaptiveGlassStrokeColor, lineWidth: 1)
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

    private var betaInfoPanel: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("测试版")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(Color(UIColor.systemRed))

                Text("仅测试使用，非正式版，可能带有不稳定因素")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: layout.infoPanelWidth254, alignment: .leading)
            .background(infoPanelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(adaptiveGlassStrokeColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
            .scaleEffect(isBetaInfoVisible ? 1 : 0.92, anchor: .top)
            .opacity(isBetaInfoVisible ? 1 : 0)
            .allowsHitTesting(isBetaInfoVisible)
            .position(x: proxy.size.width / 2, y: betaInfoPanelCenterY)
        }
        .zIndex(6)
    }

    private var debugDiagnosticsInfoPanelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .bold))
                Text("调试模式已开启")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(Color(UIColor.systemRed))

            Text(debugModeStatusDescription)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: layout.infoPanelWidth282, height: debugDiagnosticsInfoPanelHeight, alignment: .leading)
        .background(infoPanelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(adaptiveGlassStrokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
        .zIndex(6.2)
    }

    private var shouldShowDebugDiagnosticsStatus: Bool {
        displayedDebugModeEnabled && displayedDebugDiagnosticsEnabled
    }

    private var shouldShowDebugModeStatus: Bool {
        displayedDebugModeEnabled
    }

    private var compactStatusLabelCount: Int {
        shouldShowDebugModeStatus ? 1 : 0
    }

    private var compactDiagnosticsControlsHeight: CGFloat {
        layout.versionCopyLogRowHeight + CGFloat(compactStatusLabelCount) * 30 + (compactStatusLabelCount > 1 ? 6 : 0)
    }

    private var compactDiagnosticsControlsYOffset: CGFloat {
        58 + CGFloat(compactStatusLabelCount) * 13
    }

    private var debugModeStatusLabelTopY: CGFloat {
        let controlsCenterY = fixedFAQRowCenterY - compactDiagnosticsControlsYOffset
        return controlsCenterY - compactDiagnosticsControlsHeight / 2 + layout.versionCopyLogRowHeight + 6
    }

    private func debugDiagnosticsInfoPanelCenterY(in proxy: GeometryProxy) -> CGFloat {
        let labelTopY = debugModeStatusLabelFrame == .zero
            ? debugModeStatusLabelTopY
            : debugModeStatusLabelFrame.minY
        let preferredCenterY = labelTopY - 10 - debugDiagnosticsInfoPanelHeight / 2
        let minimumCenterY = proxy.safeAreaInsets.top + debugDiagnosticsInfoPanelHeight / 2 + 8
        return max(preferredCenterY, minimumCenterY)
    }

    private var fixedFAQRowCenterY: CGFloat { layout.versionFAQRowCenterY }

    private var keepAliveInfoPanelCenterY: CGFloat { layout.versionKeepAliveInfoCenterY }

    private var betaInfoPanelCenterY: CGFloat { layout.versionKeepAliveInfoCenterY - 46 }

    private var debugDiagnosticsInfoPanelHeight: CGFloat {
        if shouldShowDebugDiagnosticsStatus {
            return layout.isCompact ? 150 : 138
        }
        return layout.isCompact ? 132 : 122
    }

    private var debugModeStatusDescription: String {
        if shouldShowDebugDiagnosticsStatus {
            return "调试模式已开启，可复制诊断日志、切换保活方案。当前已合并记录线程与性能信息，会记录主线程响应、UI帧间隔异常、CPU、内存、线程状态、热状态、电量、当前页面、悬浮窗状态和最近操作，可帮助开发者分析卡死、发热和后台异常。关闭调试模式后会一起关闭。"
        }
        return "调试模式已开启，可复制诊断日志、切换保活方案。线程与性能日志会随调试模式自动开启，用于分析卡死、发热和后台异常。"
    }

    private var debugPanelCenterY: CGFloat {
        let normalY = fixedFAQRowCenterY + 54 + debugPanelCenterOffset
        guard layout.isCompact else { return normalY }
        let maxY = layout.size.height - (displayedDebugModeEnabled ? 126 : 74)
        return min(normalY, maxY)
    }

    private var debugPanelCenterOffset: CGFloat {
        displayedDebugModeEnabled ? 92 : 48
    }

    private var versionFlagBackground: AnyView {
        let shape = Capsule()
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.22))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.36)))
                .overlay(shape.strokeBorder(legacyGlassStrokeColor, lineWidth: 1))
        )
    }

    private var betaVersionBadgeBackground: AnyView {
        let shape = Capsule()
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.systemRed).opacity(0.12))
                    .glassEffect(.regular.interactive(), in: shape)
                    .overlay(shape.strokeBorder(Color(UIColor.systemRed).opacity(0.36), lineWidth: 1))
            )
        }
        return AnyView(
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color(UIColor.systemRed).opacity(0.12)))
                .overlay(shape.strokeBorder(Color(UIColor.systemRed).opacity(0.36), lineWidth: 1))
        )
    }

    private var diagnosticsStatusBackground: AnyView {
        let shape = Capsule()
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.systemRed).opacity(0.08))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color(UIColor.systemRed).opacity(0.08)))
                .overlay(shape.strokeBorder(Color(UIColor.systemRed).opacity(0.34), lineWidth: 1))
        )
    }

    private var infoPanelBackground: AnyView {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.08))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.36)))
        )
    }

    private var layout: AdaptiveLayoutMetrics { .current }
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

    private func debugGlassBackground(shape: Circle) -> AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isExpanded ? 0.36 : 0.22))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.regularMaterial)
                .overlay(shape.fill(Color(UIColor.secondarySystemBackground).opacity(isExpanded ? 0.54 : 0.38)))
        )
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

    private func glassBackground(shape: Circle) -> AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.22))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.regularMaterial)
                .overlay(shape.fill(Color(UIColor.secondarySystemBackground).opacity(0.38)))
        )
    }
}

private struct CopyLogButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button {
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

            Text("开启后可复制诊断日志、切换保活方案")
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
        .frame(width: AdaptiveLayoutMetrics.current.panelWidth300)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(adaptiveGlassStrokeColor, lineWidth: 1)
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

    private var panelBackground: AnyView {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.08))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.28)))
        )
    }
}

private struct VersionDescriptionView: View {
    var isCompact = false

    var body: some View {
        VStack(spacing: isCompact ? 4 : 6) {
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
        .font(.system(size: isCompact ? 14 : 16, weight: .medium))
        .foregroundColor(Color(UIColor.secondaryLabel))
        .multilineTextAlignment(.center)
        .lineSpacing(isCompact ? 2 : 4)
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
                        .font(.system(size: layout.isCompact ? 19 : 21, weight: .black))
                }
                .frame(width: layout.isCompact ? 40 : 44, height: layout.isCompact ? 40 : 44)

                Text(title)
                    .font(.system(size: layout.isCompact ? 18 : 19, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity)

                Color.clear
                    .frame(width: layout.isCompact ? 40 : 44, height: layout.isCompact ? 40 : 44)
            }
            .foregroundColor(Color(UIColor.label))
            .padding(.horizontal, layout.isNarrow ? 14 : 16)
            .frame(maxWidth: 286)
            .frame(height: layout.isCompact ? 62 : 72)
        }
        .buttonStyle(PrimaryLiquidGlassButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var layout: AdaptiveLayoutMetrics { .current }
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
                        .font(.system(size: layout.isCompact ? 17 : 18, weight: .semibold))
                }
                .frame(width: layout.isCompact ? 34 : 38, height: layout.isCompact ? 34 : 38)

                Text(title)
                    .font(.system(size: layout.isCompact ? 16 : 17, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .font(.system(size: layout.isCompact ? 14 : 15, weight: .black, design: .rounded))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .foregroundColor(isEnabled ? Color(UIColor.label) : Color(UIColor.tertiaryLabel))
            .padding(.horizontal, layout.isNarrow ? 14 : 18)
            .frame(maxWidth: .infinity)
            .frame(height: layout.isCompact ? 56 : 66)
        }
        .buttonStyle(LiquidGlassButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var layout: AdaptiveLayoutMetrics { .current }
}

private struct SettingsToggleRow: View {
    enum ControlStyle {
        case toggle
        case checkbox
    }

    private enum Style {
        static let iconSize: CGFloat = 14
        static let iconWidth: CGFloat = 20
        static let titleSize: CGFloat = 14
        static let suffixSize: CGFloat = 9
        static let descriptionSize: CGFloat = 11
    }

    let title: String
    let titleSuffix: String?
    let systemImage: String
    let isOn: Binding<Bool>
    let isEnabled: Bool
    let controlStyle: ControlStyle
    let statusText: ((Bool) -> String)?

    init(
        title: String,
        titleSuffix: String? = nil,
        systemImage: String,
        isOn: Binding<Bool>,
        isEnabled: Bool = true,
        controlStyle: ControlStyle = .toggle,
        statusText: ((Bool) -> String)? = nil
    ) {
        self.title = title
        self.titleSuffix = titleSuffix
        self.systemImage = systemImage
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.controlStyle = controlStyle
        self.statusText = statusText
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: Style.iconSize, weight: .bold))
                        .frame(width: Style.iconWidth, alignment: .center)

                    Text(title)
                        .font(.system(size: Style.titleSize, weight: .bold))
                        .foregroundColor(Color(UIColor.label))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if let titleSuffix {
                        Text(titleSuffix)
                            .font(.system(size: Style.suffixSize, weight: .black, design: .rounded))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(Capsule().fill(Color(UIColor.tertiarySystemFill)))
                    }
                }

                if let statusText {
                    Text(statusText(isOn.wrappedValue))
                        .font(.system(size: Style.descriptionSize, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 6)

            controlView
        }
        .disabled(!isEnabled)
        .foregroundColor(isEnabled ? Color(UIColor.label) : Color(UIColor.tertiaryLabel))
        .padding(.horizontal, 3)
        .frame(minHeight: rowMinHeight)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.54)
    }

    @ViewBuilder
    private var controlView: some View {
        switch controlStyle {
        case .toggle:
            Toggle("", isOn: isOn)
                .labelsHidden()
        case .checkbox:
            Button {
                guard isEnabled else { return }
                isOn.wrappedValue.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(isOn.wrappedValue ? Color(UIColor.systemBlue) : Color(UIColor.tertiarySystemFill))
                    Circle()
                        .stroke(Color(UIColor.separator).opacity(isOn.wrappedValue ? 0 : 0.8), lineWidth: 1)
                    if isOn.wrappedValue {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var rowMinHeight: CGFloat {
        statusText == nil
            ? (layout.isCompact ? 46 : 50)
            : (layout.isCompact ? 66 : 72)
    }

    private var layout: AdaptiveLayoutMetrics { .current }

}

private struct SettingsLiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return configuration.label
            .background(settingsBackground(isPressed: configuration.isPressed, shape: shape))
            .overlay(
                shape.strokeBorder(
                    adaptiveGlassStrokeColor.opacity(configuration.isPressed ? 1 : 0.86),
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

    private func settingsBackground(isPressed: Bool, shape: RoundedRectangle) -> AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.42 : 0.22))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.38 : 0.22))
                )
        )
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

    private func primaryBackground(
        isPressed: Bool,
        shape: RoundedRectangle
    ) -> AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.systemBlue).opacity(isPressed ? 0.2 : 0.12))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.fill(Color(UIColor.systemBlue).opacity(isPressed ? 0.24 : 0.14))
                )
        )
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

    private func glassBackground(
        isPressed: Bool,
        shape: Capsule
    ) -> AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.4 : 0.22))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.regularMaterial)
                .overlay(
                    shape.fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.54 : 0.38))
                )
        )
    }

    private func legacyStrokeColor(isPressed: Bool) -> Color {
        if #available(iOS 26.0, *) {
            return Color.white.opacity(isPressed ? 0.34 : 0.22)
        }
        return legacyGlassStrokeColor.opacity(isPressed ? 1 : 0.86)
    }
}

private var legacyGlassStrokeColor: Color {
    Color(UIColor.separator).opacity(0.62)
}

private var adaptiveGlassStrokeColor: Color {
    if #available(iOS 26.0, *) {
        return Color.white.opacity(0.22)
    }
    return legacyGlassStrokeColor
}

private struct LiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        return configuration.label
            .background(glassBackground(isPressed: configuration.isPressed, shape: shape))
            .overlay(
                shape.strokeBorder(
                    adaptiveGlassStrokeColor.opacity(configuration.isPressed ? 1 : 0.86),
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

    private func glassBackground(
        isPressed: Bool,
        shape: RoundedRectangle
    ) -> AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.42 : 0.22))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.fill(Color(UIColor.secondarySystemBackground).opacity(isPressed ? 0.38 : 0.22))
                )
        )
    }
}
