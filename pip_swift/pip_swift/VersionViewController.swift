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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DiagnosticsRuntimeState.updateCurrentPage("版本")
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
        let alert = UIAlertController(title: "诊断日志已复制", message: "可以直接粘贴发送给开发者", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
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
            AppDebugLogger.log("Debug mode enabled")
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
            title: "打开调试模式可能引发不稳定因素，请谨慎开启",
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.isDebugPanelVisible = false
            self?.debugPanelResetToken += 1
            self?.updateSwiftUI()
        })
        alert.addAction(UIAlertAction(title: "确认开启", style: .default) { [weak self] _ in
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
        titleLabel.text = "更新日志"
        titleLabel.font = .systemFont(ofSize: 24, weight: .black)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .left

        let stackView = UIStackView(arrangedSubviews: [
            makeSection(
                version: "1.0.8 beta4（26.6.15）",
                items: [
                    "帧率检测改进：降帧率响应更快（120→80仅3帧确认），升帧至120适度延迟（10帧+0.35秒），其他升帧5帧+0.12秒",
                    "帧率检测支持扩展档位：30/45/60/75/80/90/100/120Hz，可识别90Hz等中间帧率",
                    "帧率检测规范化：距离标准值5Hz内吸附，否则四舍五入至5的倍数",
                    "使用 Xcode 27 beta 重新构建，适配 iOS 15-iOS 27",
                    "首页右上角二级菜单新增 深色模式 开关，默认关闭时跟随系统设置，开启后固定使用深色模式",
                    "首页新增 后台中断通知 beta，默认低频30分钟检测一次，可切换为高频1分钟或超高频20秒检测",
                    "优化主刷新驱动、悬浮窗滚动文本驱动和后台中断通知刷新计时器，滑动时避开 tracking mode",
                    "优化后台中断通知状态机，减少控制中心、通知中心等场景的误报或漏报",
                    "优化首页布局稳定性，修复部分状态切换后页面轻微错位",
                    "新增系统快捷指令：开关悬浮窗、隐藏悬浮窗",
                    "优化快捷指令冷启动路由",
                    "优化悬浮窗停止流程",
                    "新增PiP过渡状态兜底恢复"
                ]
            ),
            makeSection(
                version: "1.0.7（26.6.8）",
                items: [
                    "为了减少耗电量，经过实测对比后APP将默认启用为更为省电的仅PiP保活新方案，后台保活效果仍为显著，且解决了小部分场景下的音频冲突问题",
                    "可通过版本号-下方或首页查看当前保活模式",
                    "不再推荐使用老方案，如有需求可再自行前往调试模式-自由切换",
                    "首页新增悬浮窗状态检测，方便查看是否生效以及隐藏和是否被杀后台，点击可查看每次打开后的持续运行时间以及上次关闭时间，便于判断后台留存时间",
                    "首页停止滚动按钮移至二级菜单，防止误解"
                ]
            ),
            makeSection(
                version: "1.0.6（26.6.6）",
                items: [
                    "调试模式新增 保活方案切换 开关，可尝试切换为更省电的仅PiP保活方案，但后台留存率可能下降可能出现低版本兼容性问题，可自行选择",
                    "修复关闭悬浮窗后进入后台可能自动重新开启的问题",
                    "调试模式新增复制诊断日志功能，用于辅助排查耗电变化和推断后台保活中断时间段"
                ]
            ),
            makeSection(
                version: "1.0.5（26.6.6）",
                items: [
                    "修复iOS16部分用户卡顿的问题，修复iOS16部分用户相机可能导致的闪退问题以及自定义悬浮窗高度不生效的问题（感谢两位老铁的崩溃日志和测试）",
                    "修复部分用户反馈的音频冲突问题",
                    "优化旧版iOS系统的UI，未适配液态玻璃的组件采用高斯模糊"
                ]
            ),
            makeSection(
                version: "1.0.4（26.6.4）",
                items: [
                    "修复低版本iOS设备闪退问题，已在iOS15.8设备调试通过"
                ]
            ),
            makeSection(
                version: "1.0.3（26.6.4）",
                items: [
                    "对“滚动悬浮窗”增加默认记忆功能；首页新增 记忆悬浮窗高度 开关",
                    "尝试修复iOS16低版本无法打开悬浮窗的问题"
                ]
            ),
            makeSection(
                version: "1.0.2（26.6.3）",
                items: [
                    "调整自定义悬浮窗的最低值为0.1pt，可以做到完全隐藏悬浮窗"
                ]
            ),
            makeSection(
                version: "1.0.1（26.5.27）",
                items: [
                    "去除旋转窗口功能",
                    "增加自定义悬浮窗高度功能，可通过滑块无级调节",
                    "增加关闭/开启滚动功能"
                ]
            ),
            makeSection(
                version: "1.0.0（26.5.26）",
                items: [
                    "在原版基础上增加后台保活功能和修改悬浮窗大小"
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
        titleLabel.text = "常见问题"
        titleLabel.font = .systemFont(ofSize: 24, weight: .black)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .left

        let stackView = UIStackView(arrangedSubviews: [
            makeQuestion(
                question: "1.这个APP的作用是什么？",
                answer: "通过将悬浮窗挂在侧面，解锁系统的1-120hz自适应刷新率，而非1-80hz，可以使流畅度得到提升，跟悬浮时钟是一个效果"
            ),
            makeQuestion(
                question: "2.生效后是一直120hz吗，会不会很耗电",
                answer: "滑动的时候最高120hz，静止的时候还是1hz"
            ),
            makeQuestion(
                question: "3.60hz的手机和锁60hz的APP能生效吗",
                answer: "不行，只对锁定了1-80hz的APP生效，例如微博、b站、系统桌面、系统设置等。腾讯全家桶和阿里全家桶均已自主适配120hz"
            ),
            makeQuestion(
                question: "4.帧率演示页面是干嘛的",
                answer: "可通过该页面的开关控制来对比80hz和120hz的区别，本app内所有页面帧率以及悬浮窗帧率受到该开关控制"
            ),
            makeQuestion(
                question: "5.后台能一直保活吗",
                answer: "可以，实测挂几天后台都不会掉，除非因为内存不足或者被其他带有画中画功能的APP挤掉了悬浮窗，需要重新打开，例如短视频APP（可以去自行关掉画中画功能）"
            ),
            makeQuestion(
                question: "6.停止/启用滚动悬浮窗有什么用",
                answer: "字面意思，停止悬浮窗的文本滚动，不影响120hz的解锁"
            ),
            makeQuestion(
                question: "7.怎么完全隐藏悬浮窗",
                answer: "点击启用悬浮窗，拖至侧边吸附后将悬浮窗高度调节至0.1pt即可"
            ),
            makeQuestion(
                question: "8.新旧保活模式有什么区别哪个更好",
                answer: "经过实测后更推荐新模式仅PiP保活方案作为默认方案，更为省电，跟老方案音频强保活对比保活率一致实测没有出现杀后台，并且避免了可能出现的部分用户反馈的音频冲突问题，当然也保留了选择空间，可自行前往调试模式切换"
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
