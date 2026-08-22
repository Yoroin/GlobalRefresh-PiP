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
        let expandedRouteHeight: CGFloat = isCompact ? 116 : 126
        let routeStatusHeight: CGFloat = 46
        return rowHeight * 3 + expandedRouteHeight + routeStatusHeight + (isCompact ? 7 : -3)
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
            .lineLimit(1)
            .minimumScaleFactor(0.72)
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
    @State private var isEngineRouteInfoVisible = false
    @State private var isShortcutInstallGuidePresented = false
    @State private var isShortcutRiskConfirmationPresented = false
    @State private var languageRefreshToken = 0
    @AppStorage(L10n.languageOverrideKey) private var languageOverrideRawValue = ""
    @AppStorage(PiPShortcutFeatureAccess.enabledKey) private var shortcutFeaturesEnabled = false
    @AppStorage(FrameRatePreference.experimentProfileKey) private var frameRateExperimentProfileRawValue = FrameRateExperimentProfile.followSwitch.rawValue
    @AppStorage("frameRateDemo.customMinimum") private var customFrameRateMinimum: Double = 30
    @AppStorage("frameRateDemo.customMaximum") private var customFrameRateMaximum: Double = 120
    @AppStorage("frameRateDemo.customPreferred") private var customFrameRatePreferred: Double = 0

    let pipHeight: String
    let keepAliveMode: String
    let keepAliveModeDescription: String
    let pipStatusTitle: String
    let pipStatusColor: UIColor
    let pipRunningDuration: String
    let pipStoppedAtText: String
    let pipRuntimeLabel: String
    let pipStoppedAtLabel: String
    let pipRuntimeStartedAt: Date?
    let overlayResetToken: Int
    let isScrollingEnabled: Bool
    let isClockModeEnabled: Bool
    let isClockModeAvailable: Bool
    let isDarkModeForced: Bool
    let isCurrentAppearanceDark: Bool
    let isPiPStoppedNotificationEnabled: Bool
    let isBackgroundInterruptionNotificationEnabled: Bool
    let keepAliveNotificationFrequency: KeepAliveNotificationProbeFrequency
    let keepsPiPStatusInfoPersistent: Bool
    let remembersPiPHeight: Bool
    let requiresPiPCloseConfirmation: Bool
    let hidesPiPWhenDocked: Bool
    let pipEngineRoute: PiPEngineRoute
    let isExtremeSilentModeEnabled: Bool
    let isContentExtremeModeEnabled: Bool
    let isSettingsExpanded: Bool
    let onTogglePiP: () -> Void
    let onStartAndHidePiP: () -> Void
    let onShowTutorial: () -> Void
    let onToggleStyle: () -> Void
    let onCustomizeHeight: () -> Void
    let onToggleScrolling: () -> Void
    let onSetClockMode: (Bool) -> Void
    let onToggleAppearanceMode: () -> Void
    let onSetPiPStoppedNotificationEnabled: (Bool) -> Void
    let onSetBackgroundInterruptionNotificationEnabled: (Bool) -> Void
    let onSetKeepAliveNotificationFrequency: (KeepAliveNotificationProbeFrequency) -> Void
    let onSetPiPStatusInfoPersistent: (Bool) -> Void
    let onToggleSettings: () -> Void
    let onDismissSettings: () -> Void
    let onSetRememberPiPHeight: (Bool) -> Void
    let onSetPiPCloseConfirmationRequired: (Bool) -> Void
    let onSetHidePiPWhenDocked: (Bool) -> Void
    let onSetPiPEngineRoute: (PiPEngineRoute) -> Void
    let onSetExtremeSilentModeEnabled: (Bool) -> Void
    let onSetContentExtremeModeEnabled: (Bool) -> Void

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
                    dismissEngineRouteInfoIfNeeded()
                    dismissSettingsIfNeeded()
                }

            if L10n.isBetaBuild {
                homeTestingWatermark
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

	            VStack(alignment: .leading, spacing: layout.homeOuterSpacing) {
	                homeHeader

	                VStack(spacing: layout.homeActionSpacing) {
                    ActionButton(title: L10n.text("使用教程", "Tutorial"), systemImage: "book") {
                        runAfterDismissingSettings(onShowTutorial)
                    }
                    ActionButton(title: L10n.text("修改悬浮窗样式", "Change Floating Style"), systemImage: "rectangle.compress.vertical") {
                        runAfterDismissingSettings(onToggleStyle)
                    }
                    ActionButton(title: L10n.text("自定义悬浮窗高度", "Custom PiP Height"), systemImage: "arrow.up.and.down", detail: pipHeight) {
                        runAfterDismissingSettings(onCustomizeHeight)
                    }

                    pipStatusRow
                }
                .padding(.horizontal, layout.homeActionHorizontalPadding)

                Spacer(minLength: layout.isCompact ? 8 : 18)

                VStack(spacing: layout.isCompact ? 9 : 12) {
                    StartAndHidePiPButton(title: startAndHidePiPButtonTitle) {
                        runAfterDismissingSettings(onStartAndHidePiP)
                    }
                    .offset(y: -5)

                    PrimaryPiPButton(title: isPiPActive ? L10n.text("关闭悬浮窗", "Stop PiP") : L10n.text("开启悬浮窗", "Enable PiP")) {
                        runAfterDismissingSettings(onTogglePiP)
                    }
                }
                    .frame(maxWidth: 286)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: -5)
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
                dismissEngineRouteInfoIfNeeded()
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

            if isEngineRouteInfoVisible {
                engineRouteInfoPopover
                    .id("engine-route-info-\(languageIdentity)")
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
        .onReceive(NotificationCenter.default.publisher(for: L10n.languageDidChangeNotification)) { _ in
            withAnimation(languageSwitchAnimation) {
                languageRefreshToken += 1
            }
        }
        .sheet(isPresented: $isShortcutInstallGuidePresented) {
            PiPShortcutInstallGuideView()
        }
        .alert(
            L10n.text("启用快捷指令风险确认", "Enable Shortcuts"),
            isPresented: $isShortcutRiskConfirmationPresented
        ) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.text("确认启用", "Enable")) {
                shortcutFeaturesEnabled = true
                PiPShortcutFeatureAccess.setEnabled(true)
                DiagnosticsRuntimeState.recordUserAction("确认启用快捷指令功能")
            }
        } message: {
            Text(L10n.text(
                "“打开并一键0.1pt”虽然方便，但可能在悬浮窗尚未吸附到屏幕侧边时直接隐藏，从而持续阻止自动熄屏。建议先打开悬浮窗并拖到侧边吸附，再执行“一键0.1pt”。确认后才会开放快捷指令安装入口并允许相关操作。",
                "Open and One-tap 0.1 pt can hide PiP before it docks to the screen edge, which may keep auto-lock from working. Open PiP, dock it to the side, then use One-tap 0.1 pt. Shortcut setup and actions become available only after you confirm."
            ))
        }
    }

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center) {
                Text(L10n.home)
                    .font(.system(size: layout.headerTitleSize, weight: .black, design: .rounded))
                    .foregroundColor(Color(UIColor.label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismissKeepAliveInfoIfNeeded()
                        dismissPiPStatusInfoIfNeededRespectingPersistence()
                        dismissNotificationFrequencyInfoIfNeeded()
                        dismissPiPStoppedNotificationInfoIfNeeded()
                        dismissEngineRouteInfoIfNeeded()
                        dismissSettingsIfNeeded()
                        onToggleAppearanceMode()
                    } label: {
                        AppearanceModeButton(
                            isDarkModeForced: isDarkModeForced,
                            isCurrentAppearanceDark: isCurrentAppearanceDark
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismissKeepAliveInfoIfNeeded()
                        dismissPiPStatusInfoIfNeededRespectingPersistence()
                        dismissNotificationFrequencyInfoIfNeeded()
                        onToggleSettings()
                    } label: {
                        SettingsGearButton(title: L10n.text("更多设置", "More"), isExpanded: isSettingsVisible)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 7) {
                Text(L10n.text("当前保活模式", "Keep-alive mode"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: true, vertical: false)

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
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
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
                .layoutPriority(1)

                Spacer(minLength: 0)
            }
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

    private var betaHomeNotice: some View {
        HStack(spacing: 4) {
            Text(L10n.text("测试版仅供测试用，包含实验性改动", "Beta build for testing only. Includes experimental changes."))
                .font(.system(size: layout.isCompact ? 13 : 14, weight: .black, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: layout.isCompact ? 13 : 14, weight: .bold))
        }
        .foregroundColor(Color(UIColor.systemRed))
        .padding(.leading, 11)
        .padding(.trailing, 9)
        .padding(.vertical, layout.isCompact ? 6 : 7)
        .frame(maxWidth: layout.isNarrow ? 246 : 268, minHeight: 30, alignment: .center)
        .background(homeStatusLabelBackground)
    }

    private var homeTestingWatermark: some View {
        GeometryReader { proxy in
            let rows = watermarkRows(for: proxy.size)
            let columns = watermarkColumns(for: proxy.size)
            ZStack {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        Text(L10n.text("测试用", "TEST"))
                            .font(.system(size: watermarkFontSize(for: proxy.size), weight: .black, design: .rounded))
                            .foregroundColor(Color(UIColor.systemRed).opacity(0.14))
                            .lineLimit(1)
                            .rotationEffect(.degrees(-24))
                            .position(
                                x: watermarkX(column: column, row: row, columns: columns, size: proxy.size),
                                y: watermarkY(row: row, rows: rows, size: proxy.size)
                            )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    private func watermarkFontSize(for size: CGSize) -> CGFloat {
        min(max(min(size.width, size.height) * 0.105, 34), 46)
    }

    private func watermarkRows(for size: CGSize) -> Int {
        max(4, Int((size.height / 150).rounded(.up)) + 1)
    }

    private func watermarkColumns(for size: CGSize) -> Int {
        max(3, Int((size.width / 210).rounded(.up)) + 1)
    }

    private func watermarkX(column: Int, row: Int, columns: Int, size: CGSize) -> CGFloat {
        let spacing = size.width / CGFloat(max(columns - 1, 1))
        let stagger = row.isMultiple(of: 2) ? 0 : spacing * 0.48
        return CGFloat(column) * spacing - spacing * 0.25 + stagger
    }

    private func watermarkY(row: Int, rows: Int, size: CGSize) -> CGFloat {
        let spacing = size.height / CGFloat(max(rows - 1, 1))
        return CGFloat(row) * spacing - spacing * 0.15
    }

    private var homeStatusLabelBackground: AnyView {
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

    private var engineRouteBadgeBackground: some View {
        let shape = Capsule()
        return shape
            .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.62))
            .overlay(
                shape.strokeBorder(Color(UIColor.systemBlue).opacity(0.2), lineWidth: 1)
            )
    }

    private var notificationBadgeColor: Color {
        isAnyNotificationEnabled
            ? Color(UIColor.systemGreen)
            : Color(UIColor.secondaryLabel)
    }

    private var isAnyNotificationEnabled: Bool {
        isPiPStoppedNotificationEnabled
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
        Color.clear
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                pipStatusRowContent
            }
    }

    private var pipStatusRowContent: some View {
        HStack(spacing: 8) {
            pipStatusTitleLabel
            pipStatusInfoButton
            notificationInfoButton
            engineRouteInfoButton
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .offset(x: isPiPStatusHiddenForLayout ? -10 : 0)
    }

    private var pipStatusTitleLabel: some View {
        Text(L10n.text("悬浮窗状态", "PiP status"))
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color(UIColor.secondaryLabel))
            .lineLimit(1)
            .minimumScaleFactor(0.92)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var pipStatusInfoButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismissKeepAliveInfoIfNeeded()
            dismissSettingsIfNeeded()
            withAnimation(.easeOut(duration: 0.16)) {
                isPiPStatusInfoVisible.toggle()
            }
        } label: {
            statusBadgeContent(title: pipStatusTitle, color: pipStatusColor)
        }
        .buttonStyle(.plain)
    }

    private var notificationInfoButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismissKeepAliveInfoIfNeeded()
            dismissPiPStatusInfoIfNeededRespectingPersistence()
            dismissSettingsIfNeeded()
            dismissEngineRouteInfoIfNeeded()
            if isPiPStoppedNotificationEnabled {
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
    }

    private var engineRouteInfoButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismissKeepAliveInfoIfNeeded()
            dismissPiPStatusInfoIfNeededRespectingPersistence()
            dismissNotificationFrequencyInfoIfNeeded()
            dismissPiPStoppedNotificationInfoIfNeeded()
            dismissSettingsIfNeeded()
            withAnimation(.easeOut(duration: 0.16)) {
                isEngineRouteInfoVisible.toggle()
            }
        } label: {
            engineRouteBadge
        }
        .buttonStyle(.plain)
    }

    private var isPiPStatusHiddenForLayout: Bool {
        pipStatusTitle == L10n.text("运行中-已隐藏", "Hidden")
            || pipStatusTitle.contains("已隐藏")
            || pipStatusTitle == "Hidden"
    }

    private func statusBadgeContent(title: String, color: UIColor) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundColor(Color(color))
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 26)
        .fixedSize(horizontal: true, vertical: false)
        .background(statusBadgeBackground)
    }

    private var keepAliveNotificationBadge: some View {
        HStack(spacing: 3) {
            Text(L10n.text("通知", "Notify"))
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.95)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: isAnyNotificationEnabled ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 10, height: 10, alignment: .center)
        }
        .foregroundColor(notificationBadgeColor)
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(height: 22)
        .background(notificationBadgeBackground)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
        .frame(minWidth: 48)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var engineRouteBadge: some View {
        HStack(spacing: 3) {
            Text(pipEngineRoute.technicalName)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .allowsTightening(true)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(Color(UIColor.systemBlue))
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(height: 22)
        .frame(minWidth: isPiPStatusHiddenForLayout ? 60 : 48)
        .background(engineRouteBadgeBackground)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var notificationFrequencyPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(L10n.text("后台中断通知模式", "Background interruption alerts"))
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(Color(UIColor.systemGreen))

            Text(L10n.text("当前：", "Current: ") + keepAliveNotificationFrequency.localizedTitle)
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
                Text(L10n.text("被挤通知已开启", "PiP conflict alert is on"))
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

    private var engineRouteInfoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: pipEngineRoute.iconName)
                    .font(.system(size: 15, weight: .bold))
                Text(pipEngineRoute.technicalName + L10n.text(" - 底层运行逻辑", " - Engine Runtime Logic"))
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(Color(UIColor.systemBlue))

            Text(pipEngineRoute.detailText)
                .font(.system(size: 12, weight: .semibold))
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
                    Text(frequency.localizedTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(UIColor.label))
                    Text(frequency.localizedDetail)
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

            Text(L10n.text("上次关闭时间：", "Last stopped: ") + pipStoppedAtText)
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

        var body: some View {
            Text(L10n.text("已运行时间：", "Runtime: ") + fallbackDuration)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
        }
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.text("高级设置", "Advanced Settings"))
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Color(UIColor.label))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    SettingsToggleRow(
                        title: L10n.text("记忆悬浮窗高度", "Save Height"),
                        systemImage: "slider.horizontal.3",
                        isOn: rememberHeightBinding,
                        allowsExpandedStatusText: true,
                        statusText: { isOn in
                            guard isOn else {
                                return L10n.text("每次打开使用默认高度", "Use the default height each time.")
                            }
                            if pipEngineRoute.usesPlayerLayer {
                                return L10n.text("下次打开自动恢复当前高度；新方案若记住1pt，会自动回显22pt，避免白线过细看不清楚", "Restore this height next time. In the new route, remembered 1 pt opens as 22 pt so the thin line remains visible.")
                            }
                            return L10n.text("下次打开自动恢复当前高度，0.1pt自动恢复44pt", "Restore this height next time. 0.1 pt restores to 44 pt automatically.")
                        }
                    )

                    EngineRoutePickerRow(selectedRoute: pipEngineRoute) { route in
                        guard route != pipEngineRoute else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismissPiPStatusInfoIfNeededRespectingPersistence()
                        onSetPiPEngineRoute(route)
                    }
                    .id("engine-picker-\(languageIdentity)")

                    EngineRouteStatusRow(route: pipEngineRoute)
                        .id("engine-status-\(languageIdentity)")

                    Divider()
                        .opacity(0.42)

                    SettingsToggleRow(
                        title: L10n.text("悬浮窗被挤通知", "PiP Conflict Alert"),
                        systemImage: "rectangle.on.rectangle.slash.fill",
                        isOn: pipStoppedNotificationBinding,
                        statusText: { _ in
                            L10n.text(
                                "用于在悬浮窗被其他画中画应用挤掉或被系统停止时通知你",
                                "Alerts you when another PiP app or the system stops the floating window."
                            )
                        }
                    )

                    Divider()
                        .opacity(0.42)

                    SettingsToggleRow(
                        title: L10n.text("快捷指令功能", "Shortcuts"),
                        systemImage: "exclamationmark.triangle.fill",
                        isOn: shortcutFeatureBinding,
                        allowsExpandedStatusText: true,
                        statusText: { isOn in
                            isOn
                                ? L10n.text(
                                    "已确认风险；可安装并使用快捷指令",
                                    "Risk confirmed. Shortcut setup and actions are available."
                                )
                                : L10n.text(
                                    "默认关闭；一键隐藏可能阻止自动熄屏，需确认风险后启用",
                                    "Off by default. One-tap hiding may prevent auto-lock and requires confirmation."
                                )
                        }
                    )

                    if shortcutFeaturesEnabled {
                        Divider()
                            .opacity(0.42)

                        SettingsActionRow(
                            title: L10n.text("快捷指令安装", "Shortcuts Setup"),
                            systemImage: "link.circle.fill",
                            statusText: L10n.text(
                                "通过 iCloud 链接导入；请先将悬浮窗拖到侧边吸附，再使用一键0.1pt",
                                "Import using iCloud links. Dock PiP to the side before using One-tap 0.1 pt."
                            )
                        ) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismissKeepAliveInfoIfNeeded()
                            dismissPiPStatusInfoIfNeededRespectingPersistence()
                            dismissNotificationFrequencyInfoIfNeeded()
                            dismissPiPStoppedNotificationInfoIfNeeded()
                            dismissEngineRouteInfoIfNeeded()
                            isShortcutInstallGuidePresented = true
                        }
                    }

                    Divider()
                        .opacity(0.42)

                    SettingsToggleRow(
                        title: L10n.text("防误触", "Confirm Before Closing"),
                        systemImage: "hand.raised.fill",
                        isOn: closeConfirmationBinding,
                        allowsExpandedStatusText: true,
                        statusText: { isOn in
                            isOn
                                ? L10n.text(
                                    "通过App首页关闭悬浮窗前需要再次确认，避免误触",
                                    "Requires confirmation before closing the floating window from the app's Home page."
                                )
                                : L10n.text(
                                    "首页关闭悬浮窗时立即执行",
                                    "Closes immediately from the app's Home page."
                                )
                        }
                    )

                    Divider()
                        .opacity(0.42)

                    SettingsToggleRow(
                        title: L10n.text("悬浮窗状态常驻", "Pin PiP Status"),
                        systemImage: "pin.fill",
                        isOn: pipStatusInfoPersistentBinding,
                        statusText: { isOn in
                            isOn ? L10n.text("使首页的悬浮窗状态时间常驻展示", "Keep PiP runtime visible on the home page.") : L10n.text("关闭后点开状态时间会按普通弹窗自动收起", "When off, the status panel auto-hides like a normal popover.")
                        }
                    )

                    Divider()
                        .opacity(0.42)

                    SettingsToggleRow(
                        title: L10n.text("时间悬浮窗", "Clock PiP"),
                        systemImage: "clock.fill",
                        isOn: clockModeBinding,
                        isEnabled: isClockModeAvailable && !pipEngineRoute.usesPlayerLayer,
                        statusText: { isOn in
                            if pipEngineRoute.usesPlayerLayer {
                                return L10n.text("新方案固定使用视频文本素材，暂不支持时间悬浮窗", "The new route uses fixed video text and does not support Clock PiP.")
                            }
                            guard isClockModeAvailable else {
                                return L10n.text("iOS 26 以下会导致120Hz失效，已强制禁用", "Disabled below iOS 26 because it may break 120 Hz.")
                            }
                            return isOn ? L10n.text("打开后悬浮窗显示时分秒", "Show hours, minutes, and seconds in PiP.") : L10n.text("关闭后恢复原有文本滚动内容", "Restore the original scrolling text content.")
                        }
                    )

                    Divider()
                        .opacity(0.42)

                    SettingsToggleRow(
                        title: L10n.text("悬浮窗内容滚动", "PiP Text Scrolling"),
                        systemImage: "text.alignleft",
                        isOn: scrollingBinding,
                        isEnabled: !isClockModeEnabled && !pipEngineRoute.usesPlayerLayer,
                        statusText: { _ in
                            if pipEngineRoute.usesPlayerLayer {
                                return L10n.text("新方案固定使用视频文本素材，内容滚动不可调节", "The new route uses fixed video text, so text scrolling is unavailable.")
                            }
                            return L10n.text("关闭后可停止文本滚动，仅防止晃眼，并不影响全局120，仅文本悬浮窗生效", "Stops text scrolling only. It does not affect 120 Hz and only applies to text PiP.")
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

    private var closeConfirmationBinding: Binding<Bool> {
        Binding(
            get: { requiresPiPCloseConfirmation },
            set: { newValue in
                guard newValue != requiresPiPCloseConfirmation else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                onSetPiPCloseConfirmationRequired(newValue)
            }
        )
    }

    private var shortcutFeatureBinding: Binding<Bool> {
        Binding(
            get: { shortcutFeaturesEnabled },
            set: { newValue in
                guard newValue != shortcutFeaturesEnabled else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if newValue {
                    isShortcutRiskConfirmationPresented = true
                } else {
                    shortcutFeaturesEnabled = false
                    PiPShortcutFeatureAccess.setEnabled(false)
                    DiagnosticsRuntimeState.recordUserAction("关闭快捷指令功能")
                }
            }
        )
    }

    private var playerLayerRouteBinding: Binding<Bool> {
        Binding(
            get: { pipEngineRoute.usesPlayerLayer },
            set: { newValue in
                guard newValue != pipEngineRoute.usesPlayerLayer else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                onSetPiPEngineRoute(newValue ? .playerLayerGenerated : .videoCall)
            }
        )
    }

    private var extremeSilentModeBinding: Binding<Bool> {
        Binding(
            get: { isExtremeSilentModeEnabled },
            set: { newValue in
                guard newValue != isExtremeSilentModeEnabled else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                onSetExtremeSilentModeEnabled(newValue)
            }
        )
    }

    private var contentExtremeModeBinding: Binding<Bool> {
        Binding(
            get: { isContentExtremeModeEnabled },
            set: { newValue in
                guard newValue != isContentExtremeModeEnabled else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                onSetContentExtremeModeEnabled(newValue)
            }
        )
    }

    private var frameRateExperimentProfile: FrameRateExperimentProfile {
        FrameRateExperimentProfile(rawValue: frameRateExperimentProfileRawValue) ?? .followSwitch
    }

    private var frameRateExperimentCustomValues: FrameRateExperimentCustomValues {
        FrameRateExperimentCustomValues(
            minimum: Float(customFrameRateMinimum),
            maximum: Float(customFrameRateMaximum),
            preferred: Float(customFrameRatePreferred)
        )
    }

    private var frameRateExperimentRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                FrameRatePreference.experimentProfile = frameRateExperimentProfile.next
                frameRateExperimentProfileRawValue = FrameRatePreference.experimentProfile.rawValue
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.below.rectangle")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 20, alignment: .center)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(L10n.text("帧率字段实验", "Frame Field Test"))
                                .font(.system(size: 14, weight: .bold))
                            if L10n.isBetaBuild {
                                Text("beta")
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .foregroundColor(Color(UIColor.systemRed))
                                    .padding(.horizontal, 5)
                                    .frame(height: 16)
                                    .background(Capsule().fill(Color(UIColor.systemRed).opacity(0.14)))
                                    .overlay(Capsule().strokeBorder(Color(UIColor.systemRed).opacity(0.35), lineWidth: 1))
                            }
                        }

                        Text(frameRateExperimentDetailText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 6)

                    Text(frameRateExperimentProfile.shortTitle)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Color(UIColor.systemBlue))
                        .padding(.horizontal, 8)
                        .frame(minHeight: 26)
                        .background(Capsule().fill(Color(UIColor.systemBlue).opacity(0.12)))
                }
                .foregroundColor(Color(UIColor.label))
                .padding(.horizontal, 3)
                .frame(minHeight: frameRateExperimentProfile == .custom ? 72 : 62)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if frameRateExperimentProfile == .custom {
                HStack(spacing: 7) {
                    frameRateCustomFieldButton(.minimum, value: frameRateExperimentCustomValues.minimum)
                    frameRateCustomFieldButton(.maximum, value: frameRateExperimentCustomValues.maximum)
                    frameRateCustomFieldButton(.preferred, value: frameRateExperimentCustomValues.preferred)
                }
                .padding(.leading, 33)
            }
        }
    }

    private var frameRateExperimentDetailText: String {
        if frameRateExperimentProfile == .custom {
            return frameRateExperimentCustomValues.detailText
        }
        return frameRateExperimentProfile.title
    }

    private func frameRateCustomFieldButton(_ field: FrameRateExperimentCustomField, value: Float) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            FrameRatePreference.cycleCustomValue(field)
            let values = FrameRatePreference.customValues
            customFrameRateMinimum = Double(values.minimum)
            customFrameRateMaximum = Double(values.maximum)
            customFrameRatePreferred = Double(values.preferred)
        } label: {
            VStack(spacing: 2) {
                Text(field.title)
                    .font(.system(size: 9, weight: .black, design: .rounded))
                Text(frameRateExperimentCustomValues.display(value))
                    .font(.system(size: 12, weight: .black, design: .rounded))
            }
            .foregroundColor(Color(UIColor.systemBlue))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(UIColor.systemBlue).opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }

    private var hideWhenDockedBinding: Binding<Bool> {
        Binding(
            get: { hidesPiPWhenDocked },
            set: { newValue in
                guard newValue != hidesPiPWhenDocked else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                onSetHidePiPWhenDocked(newValue)
            }
        )
    }

    private var scrollingBinding: Binding<Bool> {
        Binding(
            get: { pipEngineRoute.usesPlayerLayer ? false : isScrollingEnabled },
            set: { newValue in
                guard !pipEngineRoute.usesPlayerLayer else { return }
                guard !isClockModeEnabled else { return }
                guard newValue != isScrollingEnabled else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissPiPStatusInfoIfNeededRespectingPersistence()
                onToggleScrolling()
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
            get: { pipEngineRoute.usesPlayerLayer ? false : isClockModeEnabled },
            set: { newValue in
                guard !pipEngineRoute.usesPlayerLayer else { return }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + settingsDismissDelay) {
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

    private func dismissEngineRouteInfoIfNeeded() {
        guard isEngineRouteInfoVisible else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            isEngineRouteInfoVisible = false
        }
    }

    private func runAfterDismissingSettings(_ action: @escaping () -> Void) {
        dismissKeepAliveInfoIfNeeded()
        dismissPiPStatusInfoIfNeededRespectingPersistence()
        dismissNotificationFrequencyInfoIfNeeded()
        dismissPiPStoppedNotificationInfoIfNeeded()
        dismissEngineRouteInfoIfNeeded()
        guard isSettingsVisible || isSettingsExpanded else {
            action()
            return
        }

        animateSettingsVisibility(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + settingsDismissDelay) {
            onDismissSettings()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + settingsActionDelay) {
            action()
        }
    }

    private func animateSettingsVisibility(_ isVisible: Bool) {
        withAnimation(.easeInOut(duration: settingsDismissDelay)) {
            isSettingsVisible = isVisible
        }
    }

    private var settingsDismissDelay: TimeInterval { 0.18 }

    private var settingsActionDelay: TimeInterval { 0.2 }

    private var layout: AdaptiveLayoutMetrics { .current }

    private var languageSwitchAnimation: Animation {
        .interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)
    }

    private var languageIdentity: String {
        "\(L10n.currentLanguage.rawValue)-\(languageOverrideRawValue)-\(languageRefreshToken)"
    }

    private var startAndHidePiPButtonTitle: String {
        if pipEngineRoute.usesPlayerLayer {
            return L10n.text("一键1pt", "One-tap 1 pt")
        }
        return L10n.text("一键0.1pt", "One-tap 0.1 pt")
    }
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

private struct AppearanceModeButton: View {
    let isDarkModeForced: Bool
    let isCurrentAppearanceDark: Bool

    var body: some View {
        let shape = Circle()
        let iconName = isCurrentAppearanceDark ? "moon.fill" : "circle.lefthalf.filled"

        ZStack {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(isCurrentAppearanceDark ? Color(UIColor.systemIndigo) : Color(UIColor.label))
                .id(iconName)
                .transition(.opacity.combined(with: .scale(scale: 0.82)))
        }
        .frame(width: 42, height: 42)
        .background(glassBackground(shape: shape))
        .overlay(
            shape.strokeBorder(
                Color(UIColor.separator).opacity(isDarkModeForced ? 0.72 : 0.52),
                lineWidth: 1
            )
        )
        .clipShape(shape)
        .contentShape(shape)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isCurrentAppearanceDark)
        .accessibilityLabel(
            Text(
                isDarkModeForced
                    ? L10n.text("关闭强制深色，跟随系统", "Follow System Appearance")
                    : L10n.text("切换深色模式", "Switch Dark Mode")
            )
        )
    }

    private func glassBackground(shape: Circle) -> AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemBackground).opacity(isCurrentAppearanceDark ? 0.38 : 0.22))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }
        return AnyView(
            shape
                .fill(.regularMaterial)
                .overlay(
                    shape.fill(Color(UIColor.secondarySystemGroupedBackground).opacity(isCurrentAppearanceDark ? 0.54 : 0.38))
                )
        )
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

private struct VersionDescriptionFrameKey: PreferenceKey {
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
    let onRequestCacheCleanup: () -> Void
    let onRequestUpdateCheck: () -> Void
    let onRequestClearAllData: () -> Void
    let hasAvailableUpdate: Bool
    let hasCompletedUpdateCheck: Bool
    let hasUpdateCheckFailed: Bool
    let isCheckingForUpdate: Bool
    let isBetaUpdateChannelEnabled: Bool
    let onSetDebugMode: (Bool) -> Void
    let onRequestEnableDebugMode: () -> Void
    let onSetIOS26AudioKeepAlive: (Bool) -> Void
    let onSetBetaUpdateChannelEnabled: (Bool) -> Void
    @State private var isKeepAliveInfoVisible = false
    @State private var isBetaInfoVisible = false
    @State private var isDebugDiagnosticsInfoVisible = false
    @State private var isDebugPanelClosing = false
    @State private var displayedDebugModeEnabled: Bool
    @State private var displayedIOS26AudioKeepAliveEnabled: Bool
    @State private var displayedDebugDiagnosticsEnabled: Bool
    @State private var debugModeStatusLabelFrame: CGRect = .zero
    @State private var versionDescriptionFrame: CGRect = .zero
    @State private var suppressNextCacheTap = false
    @State private var languageRefreshToken = 0
    @AppStorage(L10n.languageOverrideKey) private var languageOverrideRawValue = ""

    init(
        isDebugModeEnabled: Bool,
        isDebugPanelVisible: Binding<Bool>,
        isIOS26AudioKeepAliveEnabled: Bool,
        isDebugDiagnosticsEnabled: Bool,
        debugPanelResetToken: Int,
        onShowChangelog: @escaping () -> Void,
        onShowFAQ: @escaping () -> Void,
        onCopyDiagnosticsLog: @escaping () -> Void,
        onRequestCacheCleanup: @escaping () -> Void,
        onRequestUpdateCheck: @escaping () -> Void,
        onRequestClearAllData: @escaping () -> Void,
        hasAvailableUpdate: Bool = false,
        hasCompletedUpdateCheck: Bool = false,
        hasUpdateCheckFailed: Bool = false,
        isCheckingForUpdate: Bool = false,
        isBetaUpdateChannelEnabled: Bool,
        onSetDebugMode: @escaping (Bool) -> Void,
        onRequestEnableDebugMode: @escaping () -> Void,
        onSetIOS26AudioKeepAlive: @escaping (Bool) -> Void,
        onSetBetaUpdateChannelEnabled: @escaping (Bool) -> Void
    ) {
        self.isDebugModeEnabled = isDebugModeEnabled
        _isDebugPanelVisible = isDebugPanelVisible
        self.isIOS26AudioKeepAliveEnabled = isIOS26AudioKeepAliveEnabled
        self.isDebugDiagnosticsEnabled = isDebugDiagnosticsEnabled
        self.debugPanelResetToken = debugPanelResetToken
        self.onShowChangelog = onShowChangelog
        self.onShowFAQ = onShowFAQ
        self.onCopyDiagnosticsLog = onCopyDiagnosticsLog
        self.onRequestCacheCleanup = onRequestCacheCleanup
        self.onRequestUpdateCheck = onRequestUpdateCheck
        self.onRequestClearAllData = onRequestClearAllData
        self.hasAvailableUpdate = hasAvailableUpdate
        self.hasCompletedUpdateCheck = hasCompletedUpdateCheck
        self.hasUpdateCheckFailed = hasUpdateCheckFailed
        self.isCheckingForUpdate = isCheckingForUpdate
        self.isBetaUpdateChannelEnabled = isBetaUpdateChannelEnabled
        self.onSetDebugMode = onSetDebugMode
        self.onRequestEnableDebugMode = onRequestEnableDebugMode
        self.onSetIOS26AudioKeepAlive = onSetIOS26AudioKeepAlive
        self.onSetBetaUpdateChannelEnabled = onSetBetaUpdateChannelEnabled
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
                PageHeaderTitle(title: L10n.about)

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    guard !suppressNextCacheTap else {
                        suppressNextCacheTap = false
                        return
                    }
                    dismissDebugPanel()
                    dismissKeepAliveInfoPanel()
                    dismissBetaInfoPanel()
                    dismissDebugDiagnosticsInfoPanel()
                    onRequestCacheCleanup()
                } label: {
                    CacheCleanupButton()
                }
                .buttonStyle(.plain)
                .help(L10n.cacheCleanupTitle)
                .accessibilityLabel(L10n.cacheCleanupTitle)
                .accessibilityHint(L10n.text("长按可清空全部数据并回到首次加载页面", "Long press to erase all app data and return to the first-launch screen"))
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 1.05, maximumDistance: 22)
                        .onEnded { _ in
                            suppressNextCacheTap = true
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            dismissDebugPanel()
                            dismissKeepAliveInfoPanel()
                            dismissBetaInfoPanel()
                            dismissDebugDiagnosticsInfoPanel()
                            onRequestClearAllData()
                        }
                )
                .padding(.trailing, 2)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismissDebugPanel()
                    dismissKeepAliveInfoPanel()
                    dismissBetaInfoPanel()
                    dismissDebugDiagnosticsInfoPanel()
                    withAnimation(languageSwitchAnimation) {
                        L10n.toggleLanguageOverride()
                    }
                } label: {
                    LanguageToggleButton(title: L10n.languageToggleTitle)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onShowChangelog()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .bold))
                        Text(L10n.changelog)
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
                Text(L10n.text("全局高刷悬浮窗", "Global Refresh PiP"))
                    .font(.system(size: layout.versionTitleSize, weight: .black, design: .rounded))
                    .foregroundColor(Color(UIColor.label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                VStack(spacing: 8) {
                    Text(L10n.text("当前版本", "Current Version"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))

	                    VStack(spacing: 7) {
	                        HStack(spacing: 8) {
	                            Text(L10n.versionDisplay)
	                                .font(.system(size: layout.versionNumberSize, weight: .bold, design: .rounded))
	                                .foregroundColor(Color(UIColor.label))
	                                .lineLimit(1)
	                                .fixedSize(horizontal: true, vertical: true)
	                                .layoutPriority(3)

                                if L10n.isBetaBuild {
                                    betaVersionBadge
                                }

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    dismissDebugPanel()
                                    dismissKeepAliveInfoPanel()
                                    dismissBetaInfoPanel()
                                    dismissDebugDiagnosticsInfoPanel()
                                    onRequestUpdateCheck()
                                } label: {
                                    UpdateCheckButton(
                                        hasUpdate: hasAvailableUpdate,
                                        isChecking: isCheckingForUpdate
                                    )
                                }
                                .buttonStyle(.plain)
                                .help(L10n.text("检查更新", "Check for Updates"))
                                .accessibilityLabel(L10n.text("检查更新", "Check for Updates"))
	                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(3)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onRequestUpdateCheck()
                        } label: {
                            let updateStatusColor = isCheckingForUpdate
                                ? Color(UIColor.systemGreen)
                                : hasUpdateCheckFailed
                                ? Color(UIColor.systemOrange)
                                : hasAvailableUpdate
                                ? Color(UIColor.systemRed)
                                : Color(UIColor.systemGreen)

                            let updateStatusText = isCheckingForUpdate
                                ? L10n.text("检测中", "Checking")
                                : hasUpdateCheckFailed
                                ? L10n.text("检查失败", "Check Failed")
                                : hasAvailableUpdate
                                ? L10n.text("检测到新版本", "New Version Available")
                                : hasCompletedUpdateCheck
                                ? L10n.text("当前已是最新版", "You're Up to Date")
                                : L10n.text("尚未检查", "Not Checked")

                            HStack(spacing: 5) {
                                Circle()
                                    .fill(updateStatusColor)
                                    .frame(width: 7, height: 7)
                                Text(updateStatusText)
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(updateStatusColor)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                Capsule()
                                    .fill(updateStatusColor.opacity(0.1))
                                    .overlay(
                                        Capsule().strokeBorder(
                                            updateStatusColor.opacity(0.32),
                                            lineWidth: 1
                                        )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isCheckingForUpdate)
                        .transaction { transaction in
                            transaction.animation = nil
                        }

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

                VersionDescriptionView(isCompact: layout.isCompact, languageIdentity: languageIdentity)
                    .id("version-description-\(languageIdentity)")
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: VersionDescriptionFrameKey.self,
                                value: proxy.frame(in: .named("versionPage"))
                            )
                        }
                    )

                if !layout.isCompact {
                    Color.clear
                        .frame(height: layout.versionReservedControlsHeight)
                        .padding(.top, layout.versionReservedControlsTopPadding)
                }

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
            if L10n.isBetaBuild {
                betaInfoPanel
            }
            debugDiagnosticsInfoPanel
        }
        .coordinateSpace(name: "versionPage")
        .animation(languageSwitchAnimation, value: languageRefreshToken)
        .onReceive(NotificationCenter.default.publisher(for: L10n.languageDidChangeNotification)) { _ in
            withAnimation(languageSwitchAnimation) {
                languageRefreshToken += 1
            }
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
        .onPreferenceChange(VersionDescriptionFrameKey.self) { frame in
            guard frame != .zero else { return }
            versionDescriptionFrame = frame
        }
    }

    private func toggleDebugPanel() {
        if isDebugPanelVisible {
            dismissDebugPanel()
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isDebugPanelClosing = false
        }
        withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)) {
            isDebugPanelVisible = true
        }
    }

    private func dismissDebugPanel() {
        guard isDebugPanelVisible else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isDebugPanelClosing = true
        }
        withAnimation(.easeInOut(duration: debugPanelDismissDelay)) {
            isDebugPanelVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + debugPanelDismissDelay + 0.03) {
            guard !isDebugPanelVisible else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isDebugPanelClosing = false
            }
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
        withAnimation(.easeOut(duration: 0.16)) {
            isDebugDiagnosticsInfoVisible = false
        }
    }

    private var debugPanelDismissDelay: TimeInterval { 0.18 }

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
        displayedIOS26AudioKeepAliveEnabled ? L10n.text("音频强保活", "Audio Keep-alive") : L10n.text("PiP保活-低功耗", "PiP Keep-alive")
    }

    private var keepAliveModeDescription: String {
        displayedIOS26AudioKeepAliveEnabled
            ? L10n.text("音频强保活，强力保活方案，缺点较为耗电，且小部分场景可能影响音频，已默认不再使用，仅适合超强保活且不在意耗电的需求用户", "Audio keep-alive is stronger but uses more power and may affect audio in some cases. It is no longer the default.")
            : L10n.text("新方案仅PiP保活，经实测较老方案更为省电，保活效果一致，并且解决音频冲突问题，优先推荐", "Low-power PiP keep-alive is recommended. In testing it keeps the same background stability while using less power and avoiding audio conflicts.")
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
                        Text(L10n.faq)
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
                title: L10n.text("复制诊断日志", "Copy Diagnostics"),
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
                Text(L10n.text("调试模式已开启", "Debug Mode On"))
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

	    private var betaVersionBadge: some View {
	        Button {
	            UIImpactFeedbackGenerator(style: .light).impactOccurred()
	            dismissDebugPanel()
	            dismissKeepAliveInfoPanel()
	            dismissDebugDiagnosticsInfoPanel()
	            withAnimation(.interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)) {
	                isBetaInfoVisible.toggle()
	            }
	        } label: {
	            HStack(spacing: 4) {
	                Text(L10n.text("测试版", "Beta"))
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
        .fixedSize(horizontal: true, vertical: false)
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
            if isDebugPanelVisible || isDebugPanelClosing {
                DebugModePanel(
                    isEnabled: displayedDebugModeEnabled,
                    isIOS26AudioKeepAliveEnabled: displayedIOS26AudioKeepAliveEnabled,
                    isBetaUpdateChannelEnabled: isBetaUpdateChannelEnabled,
                    onSetEnabled: setDebugMode,
                    onSetIOS26AudioKeepAlive: setIOS26AudioKeepAlive,
                    onSetBetaUpdateChannelEnabled: onSetBetaUpdateChannelEnabled,
                    isClosing: isDebugPanelClosing
                )
                .scaleEffect(isDebugPanelVisible ? 1 : 0.985, anchor: .top)
                .opacity(isDebugPanelVisible ? 1 : 0)
                .allowsHitTesting(isDebugPanelVisible && !isDebugPanelClosing)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                        removal: .opacity
                    )
                )
                .position(x: proxy.size.width / 2, y: debugPanelCenterY)
            }
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
                    Text(L10n.text("测试版", "Beta"))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(Color(UIColor.systemRed))

	                Text(L10n.text("仅做测试用", "For testing only."))
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
                Text(L10n.text("调试模式已开启", "Debug Mode On"))
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(Color(UIColor.systemRed))

            ScrollView(.vertical, showsIndicators: false) {
                Text(debugModeStatusDescription)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(width: debugDiagnosticsInfoPanelWidth, height: debugDiagnosticsInfoPanelHeight, alignment: .leading)
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

    private var fixedFAQRowCenterY: CGFloat {
        guard versionDescriptionFrame != .zero else {
            return layout.versionFAQRowCenterY
        }
        return max(layout.versionFAQRowCenterY, versionDescriptionFrame.maxY + 12 + 23)
    }

    private var languageSwitchAnimation: Animation {
        .interpolatingSpring(mass: 0.45, stiffness: 420, damping: 36, initialVelocity: 0.12)
    }

    private var languageIdentity: String {
        "\(L10n.currentLanguage.rawValue)-\(languageOverrideRawValue)-\(languageRefreshToken)"
    }

    private var keepAliveInfoPanelCenterY: CGFloat { layout.versionKeepAliveInfoCenterY }

    private var betaInfoPanelCenterY: CGFloat { layout.versionKeepAliveInfoCenterY - 46 }

	    private var debugDiagnosticsInfoPanelHeight: CGFloat {
	        if shouldShowDebugDiagnosticsStatus {
	            return layout.isCompact ? 176 : 164
	        }
	        return layout.isCompact ? 124 : 112
	    }

    private var debugDiagnosticsInfoPanelWidth: CGFloat {
        min(320, UIScreen.main.bounds.width - 28)
    }

    private var debugModeStatusDescription: String {
        if shouldShowDebugDiagnosticsStatus {
            return L10n.text("调试模式已开启，可复制诊断日志、切换保活方案。当前已合并记录线程与性能信息，会记录主线程响应、UI帧间隔异常、CPU、内存、线程状态、热状态、电量、当前页面、悬浮窗状态和最近操作，可帮助开发者分析卡死、发热和后台异常。关闭调试模式后会一起关闭。", "Debug mode is on. Diagnostics include thread and performance data for investigating freezes, heat, and background issues. Turning debug mode off disables this logging.")
        }
        return L10n.text("调试模式已开启，但诊断监控当前未运行。若不是刚切换状态，请关闭后重新开启调试模式。", "Debug mode is on, but diagnostics are not running. If this is not a transient state, turn Debug Mode off and on again.")
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

private struct CacheCleanupButton: View {
    var body: some View {
        let shape = Circle()
        Image(systemName: UIImage(systemName: "broom.fill") == nil ? "paintbrush.fill" : "broom.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(Color(UIColor.systemRed))
            .frame(width: 38, height: 38)
            .background(glassBackground(shape: shape))
            .overlay(
                shape.strokeBorder(Color(UIColor.separator).opacity(0.52), lineWidth: 1)
            )
            .clipShape(Circle())
            .contentShape(Circle())
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

private struct UpdateCheckButton: View {
    let hasUpdate: Bool
    let isChecking: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isChecking {
                RotatingRefreshIcon()
            } else {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(Color(UIColor.systemBlue))
                    .frame(width: 30, height: 30)
            }

            Circle()
                .fill(Color(UIColor.systemRed))
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color(UIColor.systemGroupedBackground), lineWidth: 2))
                .offset(x: 1, y: -1)
                .opacity(isChecking ? 0 : (hasUpdate ? 1 : 0))
        }
        .frame(width: 30, height: 30)
        .contentShape(Rectangle())
    }
}

private struct RotatingRefreshIcon: View {
    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: "arrow.clockwise.circle.fill")
            .font(.system(size: 21, weight: .semibold))
            .foregroundColor(Color(UIColor.systemBlue))
            .frame(width: 30, height: 30)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.72).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

private struct LanguageToggleButton: View {
    let title: String

    var body: some View {
        let shape = Circle()

        Text(title)
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundColor(Color(UIColor.systemBlue))
            .frame(width: 38, height: 38)
            .background(glassBackground(shape: shape))
            .overlay(
                shape.strokeBorder(
                    Color(UIColor.separator).opacity(0.52),
                    lineWidth: 1
                )
            )
            .clipShape(Circle())
            .contentShape(Circle())
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

private struct BetaCapsuleBadge: View {
    var body: some View {
        Text("beta")
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundColor(Color(UIColor.systemRed))
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Capsule().fill(Color(UIColor.systemRed).opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color(UIColor.systemRed).opacity(0.35), lineWidth: 1))
    }
}

private struct DebugModePanel: View {
    let isEnabled: Bool
    let isIOS26AudioKeepAliveEnabled: Bool
    let isBetaUpdateChannelEnabled: Bool
    let onSetEnabled: (Bool) -> Void
    let onSetIOS26AudioKeepAlive: (Bool) -> Void
    let onSetBetaUpdateChannelEnabled: (Bool) -> Void
    let isClosing: Bool
    @State private var displayedIsEnabled: Bool
    @State private var displayedIOS26AudioKeepAliveEnabled: Bool
    @State private var displayedBetaUpdateChannelEnabled: Bool

    init(
        isEnabled: Bool,
        isIOS26AudioKeepAliveEnabled: Bool,
        isBetaUpdateChannelEnabled: Bool,
        onSetEnabled: @escaping (Bool) -> Void,
        onSetIOS26AudioKeepAlive: @escaping (Bool) -> Void,
        onSetBetaUpdateChannelEnabled: @escaping (Bool) -> Void,
        isClosing: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.isIOS26AudioKeepAliveEnabled = isIOS26AudioKeepAliveEnabled
        self.isBetaUpdateChannelEnabled = isBetaUpdateChannelEnabled
        self.onSetEnabled = onSetEnabled
        self.onSetIOS26AudioKeepAlive = onSetIOS26AudioKeepAlive
        self.onSetBetaUpdateChannelEnabled = onSetBetaUpdateChannelEnabled
        self.isClosing = isClosing
        _displayedIsEnabled = State(initialValue: isEnabled)
        _displayedIOS26AudioKeepAliveEnabled = State(initialValue: isIOS26AudioKeepAliveEnabled)
        _displayedBetaUpdateChannelEnabled = State(initialValue: isBetaUpdateChannelEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 22, alignment: .center)
                Text(L10n.text("调试模式", "Debug Mode"))
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 10)
                Toggle("", isOn: immediateBinding)
                    .labelsHidden()
            }
            .frame(height: 32)

            Text(L10n.text("开启后记录卡顿、FPS、主线程、热状态与电量", "Records stutter, FPS, main thread, thermal state, and battery."))
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
                Text(L10n.text("保活方案切换", "Keep-alive Mode"))
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 10)
                    Toggle("", isOn: lowPowerPiPBinding)
                        .labelsHidden()
                }
                .frame(height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("开启：新方案仅PiP保活，经实测较老方案更为省电，保活效果一致，并且解决音频冲突问题，优先推荐", "On: low-power PiP keep-alive. Recommended."))
                    Text(L10n.text("关闭：音频强保活，强力保活方案，缺点较为耗电，且小部分场景可能影响音频，已默认不再使用，仅适合超强保活且不在意耗电的需求用户", "Off: audio keep-alive. Stronger but uses more power and may affect audio."))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)

            }

            Divider()
                .opacity(0.42)

            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 22, alignment: .center)
                Text(L10n.text("检测 Beta 版本更新", "Check Beta Updates"))
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 6)
                Toggle("", isOn: betaUpdateChannelBinding)
                    .labelsHidden()
            }
            .frame(minHeight: 32)

            Text(L10n.text(
                "无需开启调试模式。打开后会检查 GitHub 已发布的 Beta 版本；同版本正式版发布后优先提示正式版。",
                "Debug Mode is not required. Checks published GitHub Beta releases; a stable release supersedes its prerelease."
            ))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
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
        .onChange(of: isBetaUpdateChannelEnabled) { newValue in
            guard newValue != displayedBetaUpdateChannelEnabled else { return }
            displayedBetaUpdateChannelEnabled = newValue
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

    private var betaUpdateChannelBinding: Binding<Bool> {
        Binding(
            get: { displayedBetaUpdateChannelEnabled },
            set: { newValue in
                guard newValue != displayedBetaUpdateChannelEnabled else { return }
                displayedBetaUpdateChannelEnabled = newValue
                onSetBetaUpdateChannelEnabled(newValue)
            }
        )
    }

    private var panelBackground: AnyView {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if isClosing {
            return AnyView(
                shape
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.22))
            )
        }
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
    let languageIdentity: String

    var body: some View {
        VStack(spacing: isCompact ? 4 : 6) {
            Text(L10n.text("增加悬浮窗后台保活和修改侧边栏大小功能，", "Adds PiP background keep-alive and side-window sizing,"))
            Text(L10n.text("挂在侧边栏可保持系统全局120hz，", "keeps system-wide 120 Hz when docked to the edge,"))
            Text(L10n.text("适配ios26液态玻璃特性", "and supports iOS 26 Liquid Glass."))
            HStack(spacing: 0) {
                Text(L10n.text("原作者：", "Original: "))
                Link("CaiWanFeng", destination: URL(string: "https://github.com/CaiWanFeng/PiP")!)
                    .foregroundColor(Color(UIColor.systemBlue))
                Text(L10n.text("，完善：", ", maintained by "))
                Link("Yoroin", destination: URL(string: "http://www.coolapk.com/u/3233328")!)
                    .foregroundColor(Color(UIColor.systemBlue))
            }
        }
        .font(.system(size: isCompact ? 14 : 16, weight: .medium))
        .foregroundColor(Color(UIColor.secondaryLabel))
        .multilineTextAlignment(.center)
        .lineSpacing(isCompact ? 2 : 4)
        .fixedSize(horizontal: false, vertical: true)
        .id(languageIdentity)
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

private struct StartAndHidePiPButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: layout.isCompact ? 16 : 17, weight: .black))
                    .frame(width: 24, height: 24)

                Text(title)
                    .font(.system(size: layout.isCompact ? 15 : 16, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundColor(Color(UIColor.label))
            .padding(.horizontal, 8)
            .frame(width: layout.isNarrow ? 150 : 166)
            .frame(height: layout.isCompact ? 46 : 50)
        }
        .buttonStyle(SecondaryPrimaryGlassButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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

private struct PiPShortcutInstallGuideView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var copiedAction: PiPShortcutAction?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text(
                        "推荐使用 iCloud 快捷指令链接导入；导入时仍需系统确认。iOS 15 搜不到 App 动作，或 iOS 17 偶发 1004 时，用下方 URL 方式最稳。iOS18+请在控制中心-快捷指令-全局高刷添加，本页面功能适用于iOS15-iOS17。",
                        "Use iCloud Shortcuts links for setup. iOS still asks for confirmation. If iOS 15 cannot find app actions, or iOS 17 shows 1004, use the URL fallback below. On iOS 18+, add Global Refresh from Control Center > Shortcuts. This page is for iOS 15 to iOS 17."
                    ))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        ForEach(PiPShortcutInstallLinks.installableActions, id: \.self) { action in
                            shortcutInstallRow(action)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
            .navigationTitle(L10n.text("快捷指令安装", "Shortcuts Setup"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button(L10n.text("完成", "Done")) {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }

    private func shortcutInstallRow(_ action: PiPShortcutAction) -> some View {
        let iCloudURL = PiPShortcutInstallLinks.iCloudURL(for: action)
        let fallbackURLString = PiPShortcutInstallLinks.fallbackURLString(for: action)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: action.setupIconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(UIColor.systemBlue))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.setupTitle)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Color(UIColor.label))
                    Text(action.setupDescription)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Text(fallbackURLString)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(UIColor.tertiarySystemGroupedBackground))
                )

            HStack(spacing: 8) {
                Button {
                    guard let iCloudURL else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    UIApplication.shared.open(iCloudURL)
                } label: {
                    Text(iCloudURL == nil ? L10n.text("待填链接", "No Link") : L10n.text("导入", "Import"))
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(ShortcutInstallButtonStyle(color: Color(UIColor.systemBlue)))
                .disabled(iCloudURL == nil)
                .opacity(iCloudURL == nil ? 0.45 : 1)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    UIPasteboard.general.string = fallbackURLString
                    withAnimation(.easeOut(duration: 0.14)) {
                        copiedAction = action
                    }
                } label: {
                    Text(copiedAction == action ? L10n.text("已复制", "Copied") : L10n.text("复制URL", "Copy URL"))
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(ShortcutInstallButtonStyle(color: Color(UIColor.systemGreen)))
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.42), lineWidth: 1)
        )
    }
}

private struct ShortcutInstallButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        return configuration.label
            .foregroundColor(.white)
            .background(shape.fill(color.opacity(configuration.isPressed ? 0.72 : 0.9)))
            .clipShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct SettingsActionRow: View {
    let title: String
    let systemImage: String
    let statusText: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 20, alignment: .center)

                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(UIColor.label))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(.horizontal, 3)
            .frame(minHeight: AdaptiveLayoutMetrics.current.isCompact ? 66 : 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension PiPShortcutAction {
    var setupTitle: String {
        switch self {
        case .startFloatingWindow:
            return L10n.text("打开悬浮窗", "Open Floating Window")
        case .hideFloatingWindow:
            return L10n.text("隐藏悬浮窗", "Hide Floating Window")
        case .startAndHideFloatingWindow:
            return L10n.text("打开并隐藏悬浮窗", "Open and Hide")
        }
    }

    var setupDescription: String {
        switch self {
        case .startFloatingWindow:
            return L10n.text("只打开悬浮窗", "Opens PiP only.")
        case .hideFloatingWindow:
            return L10n.text("将已运行的悬浮窗缩小隐藏", "Shrinks the active PiP.")
        case .startAndHideFloatingWindow:
            return L10n.text("打开后自动缩小，适合控制中心一键使用", "Opens PiP and shrinks it for one-tap Control Center use.")
        }
    }

    var setupIconName: String {
        switch self {
        case .startFloatingWindow:
            return "pip.enter"
        case .hideFloatingWindow:
            return "eye.slash.fill"
        case .startAndHideFloatingWindow:
            return "pip.remove"
        }
    }
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
	    let allowsExpandedStatusText: Bool
	    let statusText: ((Bool) -> String)?

    init(
        title: String,
        titleSuffix: String? = nil,
        systemImage: String,
	        isOn: Binding<Bool>,
	        isEnabled: Bool = true,
	        controlStyle: ControlStyle = .toggle,
	        allowsExpandedStatusText: Bool = false,
	        statusText: ((Bool) -> String)? = nil
	    ) {
        self.title = title
        self.titleSuffix = titleSuffix
        self.systemImage = systemImage
        self.isOn = isOn
	        self.isEnabled = isEnabled
	        self.controlStyle = controlStyle
	        self.allowsExpandedStatusText = allowsExpandedStatusText
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
                            .foregroundColor(Color(UIColor.systemRed))
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(Capsule().fill(Color(UIColor.systemRed).opacity(0.14)))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(UIColor.systemRed).opacity(0.35), lineWidth: 1)
                            )
                    }
                }

                if let statusText {
	                    Text(statusText(isOn.wrappedValue))
	                        .font(.system(size: allowsExpandedStatusText ? 12 : Style.descriptionSize, weight: .semibold))
	                        .foregroundColor(Color(UIColor.secondaryLabel))
	                        .lineLimit(allowsExpandedStatusText ? nil : 3)
	                        .minimumScaleFactor(allowsExpandedStatusText ? 1 : 0.8)
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
		        return statusText == nil
		            ? (layout.isCompact ? 46 : 50)
		            : (layout.isCompact ? 66 : 72)
	    }

    private var layout: AdaptiveLayoutMetrics { .current }

}

private extension PiPEngineRoute {
    static var selectableCases: [PiPEngineRoute] {
        [.videoCall, .playerLayerGenerated]
    }

    var displayTitle: String {
        switch self {
        case .videoCall:
            return L10n.text("默认方案", "Default")
        case .playerLayerGenerated:
            return L10n.text("新方案", "New")
        case .referenceIPA:
            return L10n.text("参考方案", "Reference")
        case .referenceIPAPure:
            return L10n.text("纯净参考", "Pure Ref")
        }
    }

    var statusTitle: String {
        switch self {
        case .videoCall:
            return L10n.text("当前：VideoCall 默认方案", "Current: VideoCall default")
        case .playerLayerGenerated:
            return L10n.text("当前：PlayerLayer 新方案", "Current: PlayerLayer new")
        case .referenceIPA:
            return L10n.text("当前：PlayerLayer 参考方案", "Current: PlayerLayer reference")
        case .referenceIPAPure:
            return L10n.text("当前：PlayerLayer 纯净参考", "Current: PlayerLayer pure reference")
        }
    }

    var technicalName: String {
        switch self {
        case .videoCall:
            return "VideoCall"
        case .playerLayerGenerated:
            return "PlayerLayer"
        case .referenceIPA:
            return "PlayerLayer Reference"
        case .referenceIPAPure:
            return "PlayerLayer PureRef"
        }
    }

    var shortBadge: String {
        switch self {
        case .videoCall:
            return L10n.text("原", "Old")
        case .playerLayerGenerated:
            return L10n.text("新", "New")
        case .referenceIPA:
            return L10n.text("参考", "Ref")
        case .referenceIPAPure:
            return L10n.text("纯", "Pure")
        }
    }

    var iconName: String {
        switch self {
        case .videoCall:
            return "checkmark.shield.fill"
        case .playerLayerGenerated:
            return "film.stack.fill"
        case .referenceIPA:
            return "rectangle.stack.fill"
        case .referenceIPAPure:
            return "sparkles.tv.fill"
        }
    }

    var iconPointSize: CGFloat {
        switch self {
        case .videoCall:
            return 16
        case .playerLayerGenerated, .referenceIPA, .referenceIPAPure:
            return 14
        }
    }

    var detailText: String {
        switch self {
        case .videoCall:
            return L10n.text("VideoCall默认方案，支持0.1pt隐藏，但受限底层限制，部分锁60的游戏/弹幕可能会因帧率不同步导致卡顿，不影响其他正常场景，建议日常使用", "VideoCall default. Supports 0.1 pt hiding. Due to underlying limitations, some 60 Hz locked games/danmaku may stutter from refresh mismatch, but normal scenes are unaffected. Recommended for daily use.")
        case .playerLayerGenerated:
            return L10n.text("PlayerLayer新尝试方案，参考悬浮时钟逻辑，解决部分锁60的游戏和弹幕卡顿，但是受限底层，最小1pt无法完全隐藏，视觉上会有一条细线，按需选择。", "PlayerLayer experimental route. Inspired by Floating Clock and intended to reduce stutter in some 60 Hz games/danmaku. Minimum is 1 pt, so it cannot fully hide and may leave a thin line.")
        case .referenceIPA:
            return L10n.text("PlayerLayer参考方案，使用悬浮时钟预置比例素材铺成长时间轴，减少0.1秒循环seek干扰，测试是否更接近参考IPA表现。", "PlayerLayer reference route. Uses Floating Clock preset-ratio material stretched onto a long timeline to reduce 0.1s loop seek noise and compare against the reference IPA.")
        case .referenceIPAPure:
            return L10n.text("方案4纯净参考：只使用悬浮时钟预置比例素材和PlayerLayer启动链路，不使用动态生成视频、悬浮窗文字覆盖和内容刷新，用来做最干净的参考IPA对照测试。", "Plan 4 pure reference. Uses only Floating Clock preset-ratio material and the PlayerLayer startup path, with no generated video, text overlay, or content refresh. Intended as the cleanest reference IPA comparison.")
        }
    }
}

private struct EngineRoutePickerRow: View {
    let selectedRoute: PiPEngineRoute
    let onSelect: (PiPEngineRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 20, alignment: .center)

                Text(L10n.text("底层切换", "Engine Switch"))
                    .font(.system(size: 14, weight: .bold))

                if L10n.isBetaBuild {
                    Text("beta")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(Color(UIColor.systemRed))
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Capsule().fill(Color(UIColor.systemRed).opacity(0.14)))
                        .overlay(Capsule().strokeBorder(Color(UIColor.systemRed).opacity(0.35), lineWidth: 1))
                }
            }

            Text(selectedRoute.detailText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(PiPEngineRoute.selectableCases, id: \.self) { route in
                    Button {
                        onSelect(route)
                    } label: {
                        Text(route.displayTitle)
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                            .foregroundColor(route == selectedRoute ? .white : Color(UIColor.systemBlue))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                Capsule()
                                    .fill(route == selectedRoute ? Color(UIColor.systemBlue) : Color(UIColor.systemBlue).opacity(0.10))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(UIColor.systemBlue).opacity(route == selectedRoute ? 0 : 0.28), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 3)
        .frame(minHeight: layout.isCompact ? 116 : 126)
    }

    private var layout: AdaptiveLayoutMetrics { .current }
}

private struct EngineRouteStatusRow: View {
    let route: PiPEngineRoute

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: route.iconName)
                .font(.system(size: route.iconPointSize, weight: .bold))
                .foregroundColor(Color(UIColor.systemRed))
                .frame(width: 20, height: 20, alignment: .center)

            HStack(spacing: 6) {
                Text(route.statusTitle)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Color(UIColor.label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(1)

                Text(route.shortBadge)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(Color(UIColor.systemRed)))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 3)
    }
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

private struct SecondaryPrimaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return configuration.label
            .background(background(isPressed: configuration.isPressed, shape: shape))
            .overlay(
                shape.strokeBorder(
                    Color(UIColor.systemBlue).opacity(configuration.isPressed ? 0.38 : 0.24),
                    lineWidth: 1.1
                )
            )
            .clipShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(
                color: Color(UIColor.systemBlue).opacity(configuration.isPressed ? 0.08 : 0.16),
                radius: configuration.isPressed ? 7 : 12,
                x: 0,
                y: configuration.isPressed ? 3 : 7
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }

    private func background(isPressed: Bool, shape: RoundedRectangle) -> AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(
                shape
                    .fill(Color(UIColor.systemBlue).opacity(isPressed ? 0.16 : 0.08))
                    .glassEffect(.regular.interactive(), in: shape)
            )
        }

        return AnyView(
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.fill(Color(UIColor.systemBlue).opacity(isPressed ? 0.18 : 0.1))
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
