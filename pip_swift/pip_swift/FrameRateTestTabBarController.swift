//
//  FrameRateTestTabBarController.swift
//  pip_swift
//

import UIKit
import SwiftUI

enum DemoFrameRatePreference {
    static let force120HzKey = "frameRateDemo.pageForce120Hz"
    static let didChangeNotification = Notification.Name("DemoFrameRatePreferenceDidChange")
    static var isHighRefreshEnabled: Bool {
        UserDefaults.standard.object(forKey: force120HzKey) as? Bool ?? true
    }
    static var targetFrameRate: Int { isHighRefreshEnabled ? 120 : 80 }
    static func configureForegroundRequest(
        _ displayLink: CADisplayLink,
        targetFrameRate: Int = 120,
        minimumFrameRateWhenDisabled: Int? = nil
    ) {
        if #available(iOS 15.0, *) {
            if isHighRefreshEnabled {
                let target = Float(min(targetFrameRate, UIScreen.main.maximumFramesPerSecond))
                displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: target, maximum: target, preferred: target)
            } else {
                // Match the released OFF policy without changing the PiP preference.
                let target = min(targetFrameRate, min(80, UIScreen.main.maximumFramesPerSecond))
                displayLink.preferredFrameRateRange = CAFrameRateRange(
                    minimum: Float(min(minimumFrameRateWhenDisabled ?? target, target)),
                    maximum: Float(target),
                    preferred: Float(target)
                )
            }
        } else {
            displayLink.preferredFramesPerSecond = isHighRefreshEnabled
                ? min(targetFrameRate, UIScreen.main.maximumFramesPerSecond)
                : min(targetFrameRate, min(80, UIScreen.main.maximumFramesPerSecond))
        }
    }
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: force120HzKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
    static func migrateLegacySettingIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "frameRateDemo.pageOnlyControlMigrated.v1"
        guard !defaults.bool(forKey: migrationKey) else { return }
        if defaults.object(forKey: force120HzKey) == nil {
            defaults.set(FrameRatePreference.isHighRefreshEnabled, forKey: force120HzKey)
        }
        // A previous demo OFF setting must not leave the compatibility PiP route disabled.
        defaults.set(true, forKey: FrameRatePreference.force120HzKey)
        defaults.set(true, forKey: migrationKey)
    }
}

enum FrameRatePreference {
    static let force120HzKey = "frameRateDemo.force120Hz"
    static let experimentProfileKey = "frameRateDemo.experimentProfile"
    private static let customMinimumKey = "frameRateDemo.customMinimum"
    private static let customMaximumKey = "frameRateDemo.customMaximum"
    private static let customPreferredKey = "frameRateDemo.customPreferred"
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

    // 帧率检测完美方案：关闭强制120时 preferred 必须回到 0，让系统自适应，避免误判和干涉其它 App。
    static func preferredFrameRateValue(target: Float) -> Float {
        isHighRefreshEnabled ? target : 0
    }

    static var experimentProfile: FrameRateExperimentProfile {
        get {
            guard
                let rawValue = UserDefaults.standard.string(forKey: experimentProfileKey),
                let profile = FrameRateExperimentProfile(rawValue: rawValue)
            else {
                return .followSwitch
            }
            return profile
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: experimentProfileKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    @available(iOS 15.0, *)
    static func frameRateRange(target: Float) -> CAFrameRateRange {
        // 帧率字段实验已暂停：固定回跟随强制120开关，避免历史实验档位继续影响测试。
        FrameRateExperimentProfile.followSwitch.frameRateRange(
            target: target,
            isHighRefreshEnabled: isHighRefreshEnabled,
            customValues: customValues
        )
    }

    static var previewTarget: Float {
        let maximumFramesPerSecond = Float(UIScreen.main.maximumFramesPerSecond)
        return isHighRefreshEnabled
            ? max(60, maximumFramesPerSecond)
            : min(Float(targetFrameRate), maximumFramesPerSecond)
    }

    static var customValues: FrameRateExperimentCustomValues {
        let defaults = UserDefaults.standard
        let minimum = defaults.object(forKey: customMinimumKey) as? Float ?? 30
        let maximum = defaults.object(forKey: customMaximumKey) as? Float ?? 120
        let preferred = defaults.object(forKey: customPreferredKey) as? Float ?? 0
        return FrameRateExperimentCustomValues(
            minimum: minimum,
            maximum: maximum,
            preferred: preferred
        )
    }

    static func cycleCustomValue(_ field: FrameRateExperimentCustomField) {
        let values = customValues
        switch field {
        case .minimum:
            let next = field.nextValue(after: values.minimum)
            saveCustomValues(FrameRateExperimentCustomValues(
                minimum: next,
                maximum: values.maximum,
                preferred: values.preferred
            ))
        case .maximum:
            let next = field.nextValue(after: values.maximum)
            saveCustomValues(FrameRateExperimentCustomValues(
                minimum: values.minimum,
                maximum: next,
                preferred: values.preferred
            ))
        case .preferred:
            let next = field.nextValue(after: values.preferred)
            saveCustomValues(FrameRateExperimentCustomValues(
                minimum: values.minimum,
                maximum: values.maximum,
                preferred: next
            ))
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    private static func saveCustomValues(_ values: FrameRateExperimentCustomValues) {
        UserDefaults.standard.set(values.minimum, forKey: customMinimumKey)
        UserDefaults.standard.set(values.maximum, forKey: customMaximumKey)
        UserDefaults.standard.set(values.preferred, forKey: customPreferredKey)
    }
}

enum FrameRateExperimentProfile: String, CaseIterable {
    case followSwitch
    case min0Max120Preferred0
    case min30Max120Preferred0
    case min0Max120Preferred120
    case min30Max120Preferred120
    case min0Max80Preferred0
    case min30Max80Preferred0
    case custom

    var title: String {
        switch self {
        case .followSwitch:
            return L10n.text("跟随强制120开关", "Follow Force-120 Switch")
        case .min0Max120Preferred0:
            return "minimum 0 / maximum 120 / preferred 0"
        case .min30Max120Preferred0:
            return "minimum 30 / maximum 120 / preferred 0"
        case .min0Max120Preferred120:
            return "minimum 0 / maximum 120 / preferred 120"
        case .min30Max120Preferred120:
            return "minimum 30 / maximum 120 / preferred 120"
        case .min0Max80Preferred0:
            return "minimum 0 / maximum 80 / preferred 0"
        case .min30Max80Preferred0:
            return "minimum 30 / maximum 80 / preferred 0"
        case .custom:
            return L10n.text("自定义字段", "Custom Fields")
        }
    }

    var shortTitle: String {
        switch self {
        case .followSwitch:
            return L10n.text("默认", "Default")
        case .min0Max120Preferred0:
            return "0/120/0"
        case .min30Max120Preferred0:
            return "30/120/0"
        case .min0Max120Preferred120:
            return "0/120/120"
        case .min30Max120Preferred120:
            return "30/120/120"
        case .min0Max80Preferred0:
            return "0/80/0"
        case .min30Max80Preferred0:
            return "30/80/0"
        case .custom:
            let values = FrameRatePreference.customValues
            return "\(values.display(values.minimum))/\(values.display(values.maximum))/\(values.display(values.preferred))"
        }
    }

    var next: FrameRateExperimentProfile {
        let profiles = Self.allCases
        guard let index = profiles.firstIndex(of: self) else { return .followSwitch }
        return profiles[profiles.index(after: index) == profiles.endIndex ? profiles.startIndex : profiles.index(after: index)]
    }

    @available(iOS 15.0, *)
    func frameRateRange(
        target: Float,
        isHighRefreshEnabled: Bool,
        customValues: FrameRateExperimentCustomValues
    ) -> CAFrameRateRange {
        switch self {
        case .followSwitch:
            return CAFrameRateRange(
                minimum: 30,
                maximum: target,
                preferred: isHighRefreshEnabled ? target : 0
            )
        case .min0Max120Preferred0:
            return CAFrameRateRange(minimum: 1, maximum: 120, preferred: 0)
        case .min30Max120Preferred0:
            return CAFrameRateRange(minimum: 30, maximum: 120, preferred: 0)
        case .min0Max120Preferred120:
            return CAFrameRateRange(minimum: 1, maximum: 120, preferred: 120)
        case .min30Max120Preferred120:
            return CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        case .min0Max80Preferred0:
            return CAFrameRateRange(minimum: 1, maximum: 80, preferred: 0)
        case .min30Max80Preferred0:
            return CAFrameRateRange(minimum: 30, maximum: 80, preferred: 0)
        case .custom:
            let values = customValues.effective(defaultTarget: target)
            return CAFrameRateRange(
                minimum: values.minimum,
                maximum: values.maximum,
                preferred: values.preferred
            )
        }
    }
}

struct FrameRateExperimentCustomValues: Equatable {
    static let targetSentinel: Float = -1

    var minimum: Float
    var maximum: Float
    var preferred: Float

    func effective(defaultTarget: Float) -> FrameRateExperimentCustomValues {
        var values = self
        values.minimum = resolved(values.minimum, target: defaultTarget)
        values.maximum = resolved(values.maximum, target: defaultTarget)
        values.preferred = values.preferred == 0 ? 0 : resolved(values.preferred, target: defaultTarget)
        // CAFrameRateRange(minimum: 0, ...) can crash on device. Use 1 fps as
        // the lowest safe approximation of "system decides as low as possible".
        values.minimum = max(1, values.minimum)
        values.maximum = max(1, values.maximum)
        if values.minimum > values.maximum {
            values.minimum = values.maximum
        }
        if values.preferred != 0 {
            values.preferred = min(max(values.preferred, values.minimum), values.maximum)
        }
        return values
    }

    var detailText: String {
        let requested = "请求 \(display(minimum))/\(display(maximum))/\(display(preferred))"
        let effectiveTarget = FrameRatePreference.previewTarget
        let effectiveValues = effective(defaultTarget: effectiveTarget)
        let applied = "实际 T\(display(effectiveTarget))/\(display(effectiveValues.minimum))/\(display(effectiveValues.maximum))/\(display(effectiveValues.preferred))"
        return "\(requested)，\(applied)"
    }

    func display(_ value: Float) -> String {
        if value == Self.targetSentinel {
            return "target"
        }
        if value == 0 {
            return L10n.text("自适应", "Auto")
        }
        return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func resolved(_ value: Float, target: Float) -> Float {
        value == Self.targetSentinel ? target : value
    }
}

enum FrameRateExperimentCustomField: CaseIterable {
    case minimum
    case maximum
    case preferred

    var title: String {
        switch self {
        case .minimum:
            return "MIN"
        case .maximum:
            return "MAX"
        case .preferred:
            return "PREF"
        }
    }

    private var candidates: [Float] {
        switch self {
        case .minimum:
            return [FrameRateExperimentCustomValues.targetSentinel, 1, 30, 60, 80, 90, 120]
        case .maximum:
            return [FrameRateExperimentCustomValues.targetSentinel, 1, 60, 80, 90, 120]
        case .preferred:
            return [FrameRateExperimentCustomValues.targetSentinel, 0, 1, 60, 80, 90, 120]
        }
    }

    func nextValue(after currentValue: Float) -> Float {
        guard let index = candidates.firstIndex(of: currentValue) else {
            return candidates.first ?? currentValue
        }
        let nextIndex = candidates.index(after: index)
        return candidates[nextIndex == candidates.endIndex ? candidates.startIndex : nextIndex]
    }
}

final class FrameRateTestTabBarController: UITabBarController, UITabBarControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        DiagnosticsRuntimeState.updateCurrentPage("帧率演示")

        viewControllers = [
            makePage(title: L10n.text("测试页面1-120", "Test 1-120"), contentPrefix: L10n.text("测试页面一", "Test Page 1"), targetFrameRate: 120, symbol: "1.circle", selectedSymbol: "1.circle.fill"),
            makePage(title: L10n.text("测试页面2-80", "Test 2-80"), contentPrefix: L10n.text("测试页面二", "Test Page 2"), targetFrameRate: 90, symbol: "2.circle", selectedSymbol: "2.circle.fill"),
            makePage(title: L10n.text("测试页面3-60", "Test 3-60"), contentPrefix: L10n.text("测试页面三", "Test Page 3"), targetFrameRate: 60, symbol: "3.circle", selectedSymbol: "3.circle.fill")
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
    @State private var isScrollActive = false

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                topBar

                FrameRateScrollableListView(
                    contentPrefix: contentPrefix,
                    isCollapsed: isCollapsed,
                    onScrollActivityChange: { isScrollActive = $0 }
                )
            }
        }
        .background(FrameRateDriverView(frameTick: $frameTick, targetFrameRate: isScrollActive ? targetFrameRate : 60))
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
                TextField(L10n.text("搜索", "Search"), text: $searchText)
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
    @AppStorage(DemoFrameRatePreference.force120HzKey) private var isHighRefreshEnabled = true
    @State private var frameTick = 0
    @State private var isScrollActive = false

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)

            VStack(alignment: .leading, spacing: 0) {
                PageHeaderTitle(title: L10n.frameRateDemo)

                Text(L10n.text("上下滑动体验80Hz与120Hz的区别，开关仅改变App前台页面的刷新请求，不影响后台悬浮窗。", "Scroll to compare 80 Hz and 120 Hz. The switch changes foreground app refresh requests only, not background PiP."))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, -6)
                    .padding(.bottom, 14)

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.text("App内120Hz", "In-app 120 Hz"))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(Color(UIColor.label))

                            Text(L10n.text("关闭后按旧正式版请求最高80Hz，仅影响App前台页面；悬浮窗不受影响", "Off requests up to 80 Hz as in earlier releases, affecting foreground app pages only; PiP is unchanged."))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }

                        Spacer()

                        Toggle("", isOn: forceRefreshBinding)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 18)
                    .frame(minHeight: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.84))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )

                    HStack(spacing: 10) {
                        frameBadge(title: "ON", value: "120Hz")
                        frameBadge(title: "OFF", value: "80Hz")
                        frameBadge(title: "MAX", value: "\(min(isHighRefreshEnabled ? 120 : 80, UIScreen.main.maximumFramesPerSecond))Hz")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                RootFrameRateListView(
                    contentPrefix: L10n.frameRateDemo,
                    targetFrameRate: isHighRefreshEnabled ? 120 : 80,
                    onScrollActivityChange: { isScrollActive = $0 }
                )
            }
        }
        .background(
            FrameRateDriverView(
                frameTick: $frameTick,
                targetFrameRate: isHighRefreshEnabled ? 120 : (isScrollActive ? 80 : 60)
            )
        )
    }

    private var forceRefreshBinding: Binding<Bool> {
        Binding(
            get: { isHighRefreshEnabled },
            set: { newValue in
                DiagnosticsRuntimeState.recordUserAction(newValue ? "App前台120Hz请求开启" : "App前台120Hz请求关闭")
                DemoFrameRatePreference.setEnabled(newValue)
                isHighRefreshEnabled = newValue
            }
        )
    }

    private func frameBadge(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .black))
                .foregroundColor(Color(UIColor.secondaryLabel))

            Text(value)
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
    let onScrollActivityChange: (Bool) -> Void
    @State private var lastScrollOffset: CGFloat?
    @State private var scrollIdleWorkItem: DispatchWorkItem?
    private let scrollCoordinateSpace = "RootFrameRateScroll"

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                FrameCadenceComparisonCard()

                ForEach(0..<36, id: \.self) { index in
                    twoLineItem(index: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .background(scrollOffsetReader)
        }
        .coordinateSpace(name: scrollCoordinateSpace)
        .onPreferenceChange(FrameRateScrollOffsetPreferenceKey.self, perform: handleScrollOffsetChange)
        .onDisappear {
            scrollIdleWorkItem?.cancel()
            onScrollActivityChange(false)
        }
    }

    private var scrollOffsetReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: FrameRateScrollOffsetPreferenceKey.self,
                value: proxy.frame(in: .named(scrollCoordinateSpace)).minY
            )
        }
    }

    private func handleScrollOffsetChange(_ offset: CGFloat) {
        defer { lastScrollOffset = offset }
        guard let lastScrollOffset, abs(offset - lastScrollOffset) > 0.5 else { return }
        onScrollActivityChange(true)
        scrollIdleWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            onScrollActivityChange(false)
        }
        scrollIdleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func twoLineItem(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(contentPrefix)-\(index + 1)")
                    .font(.system(size: 17, weight: .black))
                    .foregroundColor(Color(UIColor.label))

                Spacer()

                Text(targetFrameRate > 0 ? "\(targetFrameRate)Hz" : L10n.text("自适应", "Auto"))
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Color(UIColor.systemBlue))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(
                        Capsule()
                            .fill(Color(UIColor.systemBlue).opacity(0.12))
                    )
            }

            Text(L10n.text("测试测试测试测试测试", "Refresh rate test sample text"))
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

private struct FrameCadenceComparisonCard: View {
    @AppStorage(L10n.languageOverrideKey) private var languageOverrideRawValue = ""
    @AppStorage(DemoFrameRatePreference.force120HzKey) private var isHighRefreshEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("80Hz / 120Hz 同速动画对比", "80 Hz / 120 Hz Same-Speed Comparison"))
                .font(.system(size: 16, weight: .black))
                .foregroundColor(Color(UIColor.label))

            Text(L10n.text(
                "两个蓝色球速度一致；80Hz按较低频率更新位置，120Hz移动更连续。",
                "The two blue balls move at the same speed; 80 Hz updates position less often, while 120 Hz appears more continuous."
            ))
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Color(UIColor.secondaryLabel))
            .fixedSize(horizontal: false, vertical: true)

            TimelineView(.animation(minimumInterval: isHighRefreshEnabled ? 1.0 / 120.0 : 1.0 / 80.0, paused: false)) { context in
                VStack(spacing: 12) {
                    cadenceLane(label: "80Hz", sampleRate: 80, date: context.date)
                    cadenceLane(label: "120Hz", sampleRate: 120, date: context.date)
                }
            }
            .frame(height: 76)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.35), lineWidth: 1)
        )
    }

    private func cadenceLane(label: String, sampleRate: Double, date: Date) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Color(UIColor.systemBlue))
                .frame(width: 44, alignment: .trailing)

            GeometryReader { proxy in
                let sampledTime = floor(date.timeIntervalSinceReferenceDate * sampleRate) / sampleRate
                let cycle = sampledTime.truncatingRemainder(dividingBy: 4.0)
                let progress = cycle <= 2.0 ? cycle / 2.0 : (4.0 - cycle) / 2.0
                let travel = max(proxy.size.width - 22, 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(UIColor.systemBlue).opacity(0.12))
                        .frame(height: 7)

                    Circle()
                        .fill(Color(UIColor.systemBlue))
                        .frame(width: 22, height: 22)
                        .shadow(color: Color(UIColor.systemBlue).opacity(0.3), radius: 4, x: 0, y: 2)
                        .offset(x: travel * CGFloat(progress))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 28)
        }
    }
}

struct FrameRateScrollableListView: View {
    let contentPrefix: String
    let isCollapsed: Bool
    let onScrollActivityChange: (Bool) -> Void
    @State private var lastScrollOffset: CGFloat?
    @State private var scrollIdleWorkItem: DispatchWorkItem?
    private let scrollCoordinateSpace = "FrameRateScrollableList"

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
            .background(scrollOffsetReader)
        }
        .coordinateSpace(name: scrollCoordinateSpace)
        .onPreferenceChange(FrameRateScrollOffsetPreferenceKey.self, perform: handleScrollOffsetChange)
        .onDisappear {
            scrollIdleWorkItem?.cancel()
            onScrollActivityChange(false)
        }
    }

    private var visibleRows: Range<Int> {
        isCollapsed ? 0..<1 : 0..<36
    }

    private var scrollOffsetReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: FrameRateScrollOffsetPreferenceKey.self,
                value: proxy.frame(in: .named(scrollCoordinateSpace)).minY
            )
        }
    }

    private func handleScrollOffsetChange(_ offset: CGFloat) {
        defer { lastScrollOffset = offset }
        guard let lastScrollOffset, abs(offset - lastScrollOffset) > 0.5 else { return }
        onScrollActivityChange(true)
        scrollIdleWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            onScrollActivityChange(false)
        }
        scrollIdleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func testTextField(index: Int) -> some View {
        TextField("", text: .constant("\(contentPrefix)-\(index + 1) \(L10n.text("测试测试测试测试测试", "Refresh rate test sample text"))"))
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

private struct FrameRateScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FrameRateDriverView: UIViewRepresentable {
    private final class VisibilityView: UIView {
        var visibilityDidChange: (() -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            visibilityDidChange?()
        }
    }
    @Binding var frameTick: Int
    let targetFrameRate: Int

    func makeUIView(context: Context) -> UIView {
        let view = VisibilityView()
        context.coordinator.driverView = view
        view.visibilityDidChange = { [weak coordinator = context.coordinator] in
            coordinator?.updatePausedState()
        }
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        let displayLink = CADisplayLink(
            target: context.coordinator,
            selector: #selector(Coordinator.step)
        )
        configure(displayLink)
        displayLink.add(to: .main, forMode: .common)
        context.coordinator.displayLink = displayLink
        context.coordinator.configureDisplayLink = configure
        context.coordinator.installObservers()
        context.coordinator.updatePausedState()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.configureDisplayLink = configure
        if let displayLink = context.coordinator.displayLink {
            configure(displayLink)
            context.coordinator.updatePausedState()
        }
    }

    func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.displayLink?.invalidate()
        coordinator.displayLink = nil
        coordinator.configureDisplayLink = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(frameTick: $frameTick)
    }

    private func configure(_ displayLink: CADisplayLink) {
        DemoFrameRatePreference.configureForegroundRequest(
            displayLink,
            targetFrameRate: targetFrameRate,
            minimumFrameRateWhenDisabled: 30
        )
    }

    final class Coordinator {
        var displayLink: CADisplayLink?
        weak var driverView: UIView?
        var configureDisplayLink: ((CADisplayLink) -> Void)?
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
            center.addObserver(self, selector: #selector(updatePausedState), name: DemoFrameRatePreference.didChangeNotification, object: nil)
        }

        @objc func updatePausedState() {
            if let displayLink { configureDisplayLink?(displayLink) }
            displayLink?.isPaused = UIApplication.shared.applicationState != .active || driverView?.window == nil
        }

        @objc func step() {
            guard UIApplication.shared.applicationState == .active, driverView?.window != nil else {
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
