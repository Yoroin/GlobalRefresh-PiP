//
//  VersionViewController.swift
//  pip_swift
//

import UIKit
import SwiftUI
import SnapKit

enum DiagnosticsLogExporter {
    static func exportText() -> String {
        [
            AppDebugLogger.exportText(),
            PowerUsageLogger.exportText(),
            KeepAliveLogger.exportText()
        ].joined(separator: "\n\n==============================\n\n")
    }
}

final class VersionViewController: UIViewController {
    private var hostingController: UIHostingController<VersionPageView>?
    private var isDebugModeEnabled = AppDebugLogger.isDebugModeEnabled
    private var isDebugPanelVisible = false
    private var debugPanelResetToken = 0
    private var isIOS26AudioKeepAliveEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey) == nil {
                if let legacyPiPOnly = UserDefaults.standard.object(forKey: ViewController.userDefaultsIOS26PiPOnlyKeepAliveKey) as? Bool {
                    UserDefaults.standard.set(!legacyPiPOnly, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
                } else {
                    UserDefaults.standard.set(false, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
                }
            }
            return UserDefaults.standard.bool(forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DiagnosticsRuntimeState.updateCurrentPage("版本")
        setupSwiftUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageDidChange),
            name: L10n.languageDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DiagnosticsRuntimeState.updateCurrentPage("版本")
    }

    @objc private func handleLanguageDidChange() {
        updateSwiftUI()
    }

    private func setupSwiftUI() {
        let rootView = VersionPageView(
            isDebugModeEnabled: isDebugModeEnabled,
            isDebugPanelVisible: Binding(
                get: { [weak self] in self?.isDebugPanelVisible ?? false },
                set: { [weak self] newValue in self?.setDebugPanelVisible(newValue) }
            ),
            isIOS26AudioKeepAliveEnabled: isIOS26AudioKeepAliveEnabled,
            isDebugDiagnosticsEnabled: DebugDiagnosticsMonitor.isEnabled,
            debugPanelResetToken: debugPanelResetToken,
            onShowChangelog: { [weak self] in
                self?.presentChangelog()
            },
            onShowFAQ: { [weak self] in
                self?.presentFAQ()
            },
            onCopyDiagnosticsLog: { [weak self] in
                self?.copyDiagnosticsLog()
            },
            onSetDebugMode: { [weak self] newValue in
                self?.setDebugMode(newValue)
            },
            onRequestEnableDebugMode: { [weak self] in
                self?.confirmEnableDebugMode()
            },
            onSetIOS26AudioKeepAlive: { [weak self] newValue in
                self?.setIOS26AudioKeepAlive(newValue)
            }
        )
        let hostingController = UIHostingController(rootView: rootView)
        self.hostingController = hostingController

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.backgroundColor = .systemBackground
        hostingController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        hostingController.didMove(toParent: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isDebugPanelVisible = false
        debugPanelResetToken += 1
        updateSwiftUI()
    }

    func dismissTransientOverlays() {
        isDebugPanelVisible = false
        debugPanelResetToken += 1
        updateSwiftUI()
    }

    private func updateSwiftUI() {
        hostingController?.rootView = VersionPageView(
            isDebugModeEnabled: isDebugModeEnabled,
            isDebugPanelVisible: Binding(
                get: { [weak self] in self?.isDebugPanelVisible ?? false },
                set: { [weak self] newValue in self?.setDebugPanelVisible(newValue) }
            ),
            isIOS26AudioKeepAliveEnabled: isIOS26AudioKeepAliveEnabled,
            isDebugDiagnosticsEnabled: DebugDiagnosticsMonitor.isEnabled,
            debugPanelResetToken: debugPanelResetToken,
            onShowChangelog: { [weak self] in
                self?.presentChangelog()
            },
            onShowFAQ: { [weak self] in
                self?.presentFAQ()
            },
            onCopyDiagnosticsLog: { [weak self] in
                self?.copyDiagnosticsLog()
            },
            onSetDebugMode: { [weak self] newValue in
                self?.setDebugMode(newValue)
            },
            onRequestEnableDebugMode: { [weak self] in
                self?.confirmEnableDebugMode()
            },
            onSetIOS26AudioKeepAlive: { [weak self] newValue in
                self?.setIOS26AudioKeepAlive(newValue)
            }
        )
    }

    private func setDebugPanelVisible(_ isVisible: Bool) {
        guard isDebugPanelVisible != isVisible else { return }
        isDebugPanelVisible = isVisible
        updateSwiftUI()
    }

    private func presentChangelog() {
        DiagnosticsRuntimeState.recordUserAction("打开更新日志")
        let changelogController = ChangelogViewController()
        changelogController.configureAdaptivePageSheet(preferredHeightRatio: 0.58)
        present(changelogController, animated: true)
    }

    private func presentFAQ() {
        DiagnosticsRuntimeState.recordUserAction("打开常见问题")
        let faqController = FAQViewController()
        faqController.configureAdaptivePageSheet(preferredHeightRatio: 0.68)
        present(faqController, animated: true)
    }

    private func copyDiagnosticsLog() {
        DiagnosticsRuntimeState.recordUserAction("复制诊断日志")
        UIPasteboard.general.string = DiagnosticsLogExporter.exportText()
        let alert = UIAlertController(
            title: L10n.text("诊断日志已复制", "Diagnostics Copied"),
            message: L10n.text("可以直接粘贴发送给开发者", "You can paste it directly to the developer."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        present(alert, animated: true)
    }

    private func setDebugMode(_ isEnabled: Bool) {
        isDebugModeEnabled = isEnabled
        AppDebugLogger.isDebugModeEnabled = isEnabled
        if isEnabled {
            DiagnosticsRuntimeState.startAppStateTracking()
            DiagnosticsRuntimeState.refreshAppState()
            DiagnosticsRuntimeState.updateCurrentPage("版本")
            AppDebugLogger.resetLogs()
            KeepAliveLogger.resetLogs()
            MetricKitLogger.shared.resetLogs()
            PowerUsageLogger.startFreshStatistics()
            MetricKitLogger.shared.start()
            DebugDiagnosticsMonitor.setEnabled(true)
            AppDebugLogger.log("Debug mode enabled, diagnostics monitors enabled")
            AppDebugLogger.log(PerformanceDiagnosticsLogger.currentSnapshotText())
        } else {
            MetricKitLogger.shared.stop()
            DebugDiagnosticsMonitor.setEnabled(false)
            AppDebugLogger.resetLogs()
            KeepAliveLogger.resetLogs()
            MetricKitLogger.shared.resetLogs()
            PowerUsageLogger.resetStatistics()
        }
        updateSwiftUI()
    }

    private func confirmEnableDebugMode() {
        DiagnosticsRuntimeState.recordUserAction("请求开启调试模式")
        let alert = UIAlertController(
            title: L10n.text("打开调试模式可能引发不稳定因素，请谨慎开启", "Debug mode may introduce instability. Enable with care."),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel) { [weak self] _ in
            self?.isDebugPanelVisible = false
            self?.debugPanelResetToken += 1
            self?.updateSwiftUI()
        })
        alert.addAction(UIAlertAction(title: L10n.text("确认开启", "Enable"), style: .default) { [weak self] _ in
            DiagnosticsRuntimeState.recordUserAction("确认开启调试模式")
            self?.setDebugMode(true)
        })
        present(alert, animated: true)
    }

    private func setIOS26AudioKeepAlive(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "切换为音频强保活" : "切换为PiP低功耗保活")
        isIOS26AudioKeepAliveEnabled = isEnabled
        if !isEnabled {
            BackgroundTaskManager.shared.forceStopAndDeactivate()
            PowerUsageLogger.markKeepAliveStop()
        }
        NotificationCenter.default.post(name: ViewController.iOS26KeepAliveModeDidChangeNotification, object: nil)
        updateSwiftUI()
    }
}

private final class ChangelogViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let contentView = applyLegacyGlassSheetBackground()

        let titleLabel = UILabel()
        titleLabel.text = L10n.changelog
        titleLabel.font = .systemFont(ofSize: 24, weight: .black)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 1

        let stackView = UIStackView(arrangedSubviews: [
            makeSection(
                version: L10n.text("1.0.9 （26.7.8）", "1.0.9 (2026.7.8)"),
                items: [
                    L10n.text("注：此次更新重点解决问题，高刷作用字段回滚至1.0.7稳定版，解决部分iOS版本解锁120失效的问题；新增底层方案切换，解决b站弹幕和荒野乱斗卡顿，缺点无法完全隐藏最低1pt，原因，默认可隐藏悬浮窗底层会强拉120导致锁60的app卡顿，锁80的app不受影响", "Note: this update focuses on key fixes. The high-refresh driver fields have been rolled back to the stable 1.0.7 behavior to fix 120 Hz unlock failures on some iOS versions. Engine switching was added to address Bilibili danmaku and Brawl Stars stutter. The tradeoff is that the new route cannot fully hide and has a 1 pt minimum. The default fully hideable route forces 120 Hz at a lower level, which can stutter in apps locked to 60 Hz; apps locked to 80 Hz are not affected."),
                    L10n.text("新增首页按钮 一键0.1pt 用于悬浮窗吸附后快速调节高度", "Added the One-tap 0.1 pt home button for quickly adjusting the height after the floating window is docked."),
                    L10n.text("优化悬浮窗的组件，避免0.1pt时屏幕出现两个白点（仅对iOS16+生效）", "Optimized floating window components to avoid two white dots appearing on screen at 0.1 pt. This only applies to iOS 16+."),
                    L10n.text("优化悬浮窗隐藏后的资源占用：当高度调至 0.1pt 时，暂停文字滚动和时钟刷新，减少长期后台挂载时的无效开销和发热", "Optimized resource usage after hiding the floating window. When height is set to 0.1 pt, text scrolling and clock refresh are paused to reduce unnecessary long-running background work and heat."),
                    L10n.text("去除 后台中断通知beta 减少误报情况", "Removed the Background Interruption Alert beta feature to reduce false positives."),
                    L10n.text("优化深色模式切换逻辑，按钮移至首页", "Improved dark mode switching logic and moved the button to the home page."),
                    L10n.text("快捷指令尝试适配低版本iOS，如无法使用，请在更多设置-手动导入快捷指令使用", "Shortcuts now attempt to support older iOS versions. If they do not work, use More Settings > Manually Import Shortcuts."),
                    L10n.text("新增“底层切换”测试入口（日常用户请忽略）：更多设置-底层切换-新方案。新方案仅用于解决因部分游戏和弹幕自身锁60而与120帧率不同步导致的卡顿，表现为b站弹幕一快一慢以及荒野乱斗大厅偶尔掉帧，新方案PlayerLayer参考悬浮时钟受底层限制最低1pt，无法完全隐藏，视觉上会有一条细线，默认方案VideoCall仍保留0.1pt隐藏能力，非必要请默认使用老方案", "Added an Engine Switch testing entry (daily users can ignore it): More Settings > Engine Switch > New Route. The new PlayerLayer route is only for stutter caused by some games or danmaku being locked to 60 Hz and becoming unsynchronized with 120 Hz, such as Bilibili danmaku speeding up and slowing down or occasional Brawl Stars lobby drops. The PlayerLayer route follows Floating Clock behavior and is limited by the underlying framework to a 1 pt minimum, so it cannot fully hide and may show a thin line. The default VideoCall route still supports 0.1 pt hiding. Keep using the old route unless needed."),
                    L10n.text("增加英文适配", "Added English localization support."),
                    L10n.text("简化调试模式，优化逻辑，不打开调试模式时完全停止日志记录减少性能开销", "Simplified Debug Mode logic. When Debug Mode is off, logging is completely stopped to reduce performance overhead."),
                    L10n.text("优化帧率检测逻辑", "Optimized frame-rate detection logic."),
                    L10n.text("优化部分动画细节", "Optimized some animation details."),
                    L10n.text("默认启用原有文本悬浮窗、默认启用悬浮窗被挤通知（需要同意授权）、默认启用悬浮窗状态常驻、默认启用记忆悬浮窗高度", "Text floating window is enabled by default, PiP conflict alerts are enabled by default after notification permission is granted, persistent PiP status is enabled by default, and remembered PiP height is enabled by default."),
                    L10n.text("新增 手动填写高度", "Added manual height input."),
                    L10n.text("已知问题：直接用快捷指令一键开启悬浮窗隐藏会导致悬浮窗没有吸附到侧面，阻止熄屏，一般还是建议先启用悬浮窗，拖到侧面吸附后再点击一键0.1pt按钮", "Known issue: using a Shortcut to open and hide PiP in one step may leave the floating window undocked, which can prevent auto-lock. In general, open PiP first, drag it to the side until it docks, then tap the One-tap 0.1 pt button.")
                ]
            ),
            makeSection(
                version: L10n.text("1.0.8（26.6.19）", "1.0.8 (2026.6.19)"),
                items: [
                    L10n.text("使用 Xcode 27 beta 构建，适配 iOS 15-iOS 27", "Built with Xcode 27 beta, compatible with iOS 15 through iOS 27."),
                    L10n.text("新增悬浮窗时间、网速、帧率检测（因打开悬浮窗后全局默认120hz，帧率检测功能需要先临时关闭帧率演示的强制120hz开关）", "Added PiP clock, network speed, and frame-rate detection. Because opening PiP can enable global 120 Hz by default, temporarily turn off the Frame Rate Demo force-120 switch before using frame-rate detection."),
                    L10n.text("iOS 26 以下强制禁用时间悬浮窗，避免旧系统启用后导致全局120Hz失效；普通文本悬浮窗不受影响", "Clock PiP is disabled below iOS 26 to avoid breaking global 120 Hz on older systems. Text PiP is unaffected."),
                    L10n.text("首页更多设置新增 深色模式 开关，默认关闭时跟随系统设置，开启后固定使用深色模式", "Added a Dark Mode switch in Home > More. Off follows the system; on forces dark mode."),
                    L10n.text("首页更多设置新增 悬浮窗被挤通知 和 后台中断通知 beta 两个独立开关；被挤通知用于其他画中画挤掉悬浮窗时实时提醒（一般只开这个就够用了）。后台中断通知 beta 默认关闭，通过定时轮询和预排本地通知辅助判断后台是否仍存活；频率主要影响异常发现速度和误报风险，不代表耗电量线性增加", "Added separate PiP Conflict Alert and Background Alert beta switches in Home > More. Conflict alerts notify when another PiP app pushes this PiP away. Background Alert beta is off by default and uses polling plus scheduled local notifications to help detect background termination. Frequency mainly affects detection speed and false-positive risk, not battery use linearly."),
                    L10n.text("优化首页布局稳定性，修复部分状态切换后页面轻微错位", "Improved home layout stability and fixed slight shifts after some state changes."),
                    L10n.text("新增系统快捷指令：打开并隐藏悬浮窗、打开悬浮窗、隐藏悬浮窗，便于放在控制中心一键操作；添加入口为长按控制中心-新增快捷指令-选中全局高刷，控制中心添加快捷指令仅支持 iOS 18+（如果屏幕上出现两个点是因为悬浮窗的关闭按钮没有隐藏，让悬浮窗恢复正常大小后点一下即可，下次会自动隐藏）", "Added Shortcuts: Open and Hide, Open Floating Window, and Hide Floating Window for one-tap Control Center use. To add them, long-press Control Center, add a shortcut, then select Global Refresh. Control Center shortcut tiles require iOS 18+."),
                    L10n.text("新增悬浮窗状态常驻开关，便于查看存活时间", "Added a pinned PiP status switch for viewing runtime."),
                    L10n.text("适配深色模式桌面图标", "Added dark-mode app icon support."),
                    L10n.text("优化悬浮窗停止流程", "Improved the PiP stop flow."),
                    L10n.text("优化强制帧率演示页面描述，此开关目前开启和关闭都将影响悬浮窗的120hz功能", "Improved the force-refresh demo description. This switch currently affects the PiP 120 Hz behavior both when on and off.")
                ]
            ),
            makeSection(
                version: L10n.text("1.0.7（26.6.8）", "1.0.7 (2026.6.8)"),
                items: [
                    L10n.text("为了减少耗电量，经过实测对比后APP将默认启用为更为省电的仅PiP保活新方案，后台保活效果仍为显著，且解决了小部分场景下的音频冲突问题", "Switched the default to the lower-power PiP-only keep-alive mode after testing. Background stability remains strong while avoiding some audio conflicts."),
                    L10n.text("可通过版本号-下方或首页查看当前保活模式", "The current keep-alive mode is shown below the version number and on the home page."),
                    L10n.text("不再推荐使用老方案，如有需求可再自行前往调试模式-自由切换", "The old mode is no longer recommended, but it can still be selected in Debug Mode."),
                    L10n.text("首页新增悬浮窗状态检测，方便查看是否生效以及隐藏和是否被杀后台，点击可查看每次打开后的持续运行时间以及上次关闭时间，便于判断后台留存时间", "Added PiP status detection on the home page, including active/hidden state, runtime, and last stop time."),
                    L10n.text("首页停止滚动按钮移至二级菜单，防止误解", "Moved the stop-scrolling button into More Settings to reduce confusion.")
                ]
            ),
            makeSection(
                version: L10n.text("1.0.6（26.6.6）", "1.0.6 (2026.6.6)"),
                items: [
                    L10n.text("调试模式新增 保活方案切换 开关，可尝试切换为更省电的仅PiP保活方案，但后台留存率可能下降可能出现低版本兼容性问题，可自行选择", "Added a Debug Mode keep-alive switch for trying the lower-power PiP-only mode."),
                    L10n.text("修复关闭悬浮窗后进入后台可能自动重新开启的问题", "Fixed an issue where PiP could reopen automatically after being stopped and sent to the background."),
                    L10n.text("调试模式新增复制诊断日志功能，用于辅助排查耗电变化和推断后台保活中断时间段", "Added diagnostics copy support in Debug Mode for investigating battery changes and background interruptions.")
                ]
            ),
            makeSection(
                version: L10n.text("1.0.5（26.6.6）", "1.0.5 (2026.6.6)"),
                items: [
                    L10n.text("修复iOS16部分用户卡顿的问题，修复iOS16部分用户相机可能导致的闪退问题以及自定义悬浮窗高度不生效的问题（感谢两位老铁的崩溃日志和测试）", "Fixed stutter for some iOS 16 users, a possible camera-related crash, and custom PiP height issues."),
                    L10n.text("修复部分用户反馈的音频冲突问题", "Fixed audio conflict issues reported by some users."),
                    L10n.text("优化旧版iOS系统的UI，未适配液态玻璃的组件采用高斯模糊", "Improved the UI on older iOS versions with blur fallbacks for Liquid Glass-style components.")
                ]
            ),
            makeSection(
                version: L10n.text("1.0.4（26.6.4）", "1.0.4 (2026.6.4)"),
                items: [
                    L10n.text("修复低版本iOS设备闪退问题，已在iOS15.8设备调试通过", "Fixed crashes on older iOS devices, tested on iOS 15.8.")
                ]
            ),
            makeSection(
                version: L10n.text("1.0.3（26.6.4）", "1.0.3 (2026.6.4)"),
                items: [
                    L10n.text("对“滚动悬浮窗”增加默认记忆功能；首页新增 记忆悬浮窗高度 开关", "Added remembered scrolling PiP height, with a new Remember PiP Height switch on the home page."),
                    L10n.text("尝试修复iOS16低版本无法打开悬浮窗的问题", "Attempted to fix PiP startup issues on lower iOS 16 versions.")
                ]
            ),
            makeSection(
                version: L10n.text("1.0.2（26.6.3）", "1.0.2 (2026.6.3)"),
                items: [
                    L10n.text("调整自定义悬浮窗的最低值为0.1pt，可以做到完全隐藏悬浮窗", "Lowered the custom PiP height minimum to 0.1 pt so the floating window can be fully hidden.")
                ]
            ),
            makeSection(
                version: L10n.text("1.0.1（26.5.27）", "1.0.1 (2026.5.27)"),
                items: [
                    L10n.text("去除旋转窗口功能", "Removed the rotate-window feature."),
                    L10n.text("增加自定义悬浮窗高度功能，可通过滑块无级调节", "Added custom PiP height control with a smooth slider."),
                    L10n.text("增加关闭/开启滚动功能", "Added text scrolling on/off control.")
                ]
            ),
            makeSection(
                version: L10n.text("1.0.0（26.5.26）", "1.0.0 (2026.5.26)"),
                items: [
                    L10n.text("在原版基础上增加后台保活功能和修改悬浮窗大小", "Added background keep-alive and PiP size adjustment on top of the original project.")
                ]
            )
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 24

        let scrollView = UIScrollView()
        contentView.addSubview(titleLabel)
        contentView.addSubview(scrollView)
        scrollView.addSubview(stackView)

        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(contentView.safeAreaLayoutGuide).inset(24)
            make.top.equalTo(contentView.safeAreaLayoutGuide).offset(24)
        }
        scrollView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalTo(contentView.safeAreaLayoutGuide)
            make.top.equalTo(titleLabel.snp.bottom).offset(18)
        }
        stackView.snp.makeConstraints { make in
            make.leading.trailing.equalTo(scrollView.frameLayoutGuide).inset(24)
            make.top.bottom.equalTo(scrollView.contentLayoutGuide).inset(6)
        }
    }

    private func makeSection(version: String, items: [String]) -> UIView {
        let versionLabel = UILabel()
        versionLabel.text = version
        versionLabel.font = .systemFont(ofSize: 22, weight: .black)
        versionLabel.textColor = .label
        versionLabel.textAlignment = .left

        let itemStack = UIStackView()
        itemStack.axis = .vertical
        itemStack.spacing = 8

        for item in items {
            let label = UILabel()
            label.text = item
            label.font = .systemFont(ofSize: 16, weight: .semibold)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            itemStack.addArrangedSubview(label)
        }

        let sectionStack = UIStackView(arrangedSubviews: [versionLabel, itemStack])
        sectionStack.axis = .vertical
        sectionStack.spacing = 12
        return sectionStack
    }
}

private final class FAQViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let contentView = applyLegacyGlassSheetBackground()

        let titleLabel = UILabel()
        titleLabel.text = L10n.faq
        titleLabel.font = .systemFont(ofSize: 24, weight: .black)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .left

        let stackView = UIStackView(arrangedSubviews: [
            makeQuestion(
                question: L10n.text("1.这个APP的作用是什么？", "1. What does this app do?"),
                answer: L10n.text("通过将悬浮窗挂在侧面，解锁系统的1-120hz自适应刷新率，而非1-80hz，可以使流畅度得到提升，跟悬浮时钟是一个效果，同时增加了保活（实测挂一周都不会掉后台）和隐藏悬浮窗功能", "It docks a PiP floating window to the screen edge to unlock the system's 1-120 Hz adaptive refresh range instead of 1-80 Hz, improving smoothness. It also adds background keep-alive and hidden PiP support.")
            ),
            makeQuestion(
                question: L10n.text("2.生效后是一直120hz吗，会不会很耗电，怎么判断是否生效呢", "2. Does it stay at 120 Hz all the time?"),
                answer: L10n.text("滑动的时候最高120hz，静止的时候还是1hz。打开后，iOS的系统设置页面上下滑动自行观察。", "No. It can reach 120 Hz while scrolling, and still drops very low while idle. Open it and scroll in iOS Settings to observe the difference.")
            ),
            makeQuestion(
                question: L10n.text("3.60hz的手机和锁60hz的APP能生效吗", "3. Does it work on 60 Hz devices or apps locked to 60 Hz?"),
                answer: L10n.text("不行，只对锁定了1-80hz的APP生效，例如微博、b站、系统设置和其他系统应用等。腾讯全家桶和阿里全家桶均已自主适配120hz", "No. It mainly helps apps limited to 1-80 Hz, such as some system apps and apps like Weibo or Bilibili. Apps already adapted to 120 Hz do not need it.")
            ),
            makeQuestion(
                question: L10n.text("4.帧率演示页面是干嘛的", "4. What is the Frame Rate Demo page for?"),
                answer: L10n.text("可通过该页面的开关控制来对比80hz和120hz的区别，本app内所有页面帧率以及悬浮窗帧率受到该开关控制", "It lets you compare 80 Hz and 120 Hz. The switch affects the app pages and the floating window refresh behavior.")
            ),
            makeQuestion(
                question: L10n.text("5.后台能一直保活吗", "5. Can it stay alive in the background?"),
                answer: L10n.text("可以，实测挂几天后台都不会掉，除非因为内存不足或者被其他带有画中画功能的APP挤掉了悬浮窗，需要重新打开，例如短视频APP（可以去自行关掉画中画功能）", "In testing, it can stay alive for days. It may still stop if memory is low or another PiP app pushes it away, such as some short-video apps.")
            ),
            makeQuestion(
                question: L10n.text("6.停止/启用滚动悬浮窗有什么用", "6. What does PiP text scrolling do?"),
                answer: L10n.text("字面意思，停止悬浮窗的文本滚动，不影响120hz的解锁", "It only stops or starts the scrolling text inside the floating window. It does not affect 120 Hz unlocking.")
            ),
            makeQuestion(
                question: L10n.text("7.怎么完全隐藏悬浮窗", "7. How do I fully hide the floating window?"),
                answer: L10n.text("点击启用悬浮窗，拖至侧边吸附后将悬浮窗高度调节至0.1pt即可", "Enable the floating window, dock it to the edge, then set the PiP height to 0.1 pt.")
            ),
            makeQuestion(
                question: L10n.text("8.新旧保活模式有什么区别哪个更好", "8. Which keep-alive mode is better?"),
                answer: L10n.text("经过实测后更推荐新模式仅PiP保活方案作为默认方案，更为省电，跟老方案音频强保活对比保活率一致实测没有出现杀后台，并且避免了可能出现的部分用户反馈的音频冲突问题，当然也保留了选择空间，可自行前往调试模式切换", "The low-power PiP-only mode is recommended. In testing it keeps similar background stability while using less power and avoiding possible audio conflicts. You can still switch modes in Debug Mode.")
            ),
            makeQuestion(
                question: L10n.text("9.首页的底层切换按钮是干嘛的", "9. What does the Engine Switch button do?"),
                answer: L10n.text("因接到部分用户反馈，默认方案VideoCall虽然可以实现解锁120并完全隐藏，但是底层会因强拉120而导致部分锁60hz的游戏以及60hz的弹幕因帧率不同步而突发掉帧，因此提供底层切换按钮，切换新方案PlayerLayer后可以解决这个问题，但是因底层限制无法完全隐藏，即最低1pt，视觉上会有一条细线，可供自由选择", "Some users reported that although the default VideoCall route can unlock 120 Hz and fully hide the floating window, its lower-level forced 120 Hz behavior may cause sudden stutters in some games locked to 60 Hz or in 60 Hz danmaku because the frame rates are not synchronized. The Engine Switch provides an alternative. Switching to the new PlayerLayer route can solve this issue, but due to lower-level limits it cannot fully hide; the minimum is 1 pt, so a thin line may remain visible. Choose whichever route works best for you.")
            ),
            makeQuestion(
                question: L10n.text("10.为什么我发现有时候无法自动熄屏了", "10. Why does auto-lock sometimes stop working?"),
                answer: L10n.text("因为隐藏悬浮窗的时候没有把悬浮窗拖到侧面，屏幕上会一直有活动阻止熄屏，请拖动到侧面后再将高度调节至0.1pt", "This can happen if the floating window is hidden before it is docked to the side. Activity may remain on screen and prevent auto-lock. Drag it to the edge first, then adjust the height to 0.1 pt.")
            )
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 22

        let scrollView = UIScrollView()
        contentView.addSubview(titleLabel)
        contentView.addSubview(scrollView)
        scrollView.addSubview(stackView)

        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(contentView.safeAreaLayoutGuide).inset(24)
            make.top.equalTo(contentView.safeAreaLayoutGuide).offset(24)
        }
        scrollView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalTo(contentView.safeAreaLayoutGuide)
            make.top.equalTo(titleLabel.snp.bottom).offset(18)
        }
        stackView.snp.makeConstraints { make in
            make.leading.trailing.equalTo(scrollView.frameLayoutGuide).inset(24)
            make.top.bottom.equalTo(scrollView.contentLayoutGuide).inset(6)
        }
    }

    private func makeQuestion(question: String, answer: String) -> UIView {
        let questionLabel = UILabel()
        questionLabel.text = question
        questionLabel.font = .systemFont(ofSize: 18, weight: .black)
        questionLabel.textColor = .label
        questionLabel.numberOfLines = 0

        let answerLabel = UILabel()
        answerLabel.text = answer
        answerLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        answerLabel.textColor = .secondaryLabel
        answerLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [questionLabel, answerLabel])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }
}
