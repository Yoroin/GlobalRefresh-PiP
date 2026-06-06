//
//  VersionViewController.swift
//  pip_swift
//

import UIKit
import SwiftUI
import SnapKit

final class VersionViewController: UIViewController {
    private var hostingController: UIHostingController<VersionPageView>?
    private var isDebugModeEnabled = AppDebugLogger.isDebugModeEnabled
    private var debugPanelResetToken = 0
    private var isIOS26AudioKeepAliveEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey) == nil {
                if let legacyPiPOnly = UserDefaults.standard.object(forKey: ViewController.userDefaultsIOS26PiPOnlyKeepAliveKey) as? Bool {
                    UserDefaults.standard.set(!legacyPiPOnly, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
                } else {
                    UserDefaults.standard.set(true, forKey: ViewController.userDefaultsIOS26AudioKeepAliveKey)
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
        setupSwiftUI()
    }

    private func setupSwiftUI() {
        let rootView = VersionPageView(
            isDebugModeEnabled: isDebugModeEnabled,
            isIOS26AudioKeepAliveEnabled: isIOS26AudioKeepAliveEnabled,
            debugPanelResetToken: debugPanelResetToken,
            onShowChangelog: { [weak self] in
                self?.presentChangelog()
            },
            onShowFAQ: { [weak self] in
                self?.presentFAQ()
            },
            onCopyDebugLog: { [weak self] in
                self?.copyDebugLog()
            },
            onCopyPowerLog: { [weak self] in
                self?.copyPowerLog()
            },
            onCopyMetricLog: { [weak self] in
                self?.copyMetricLog()
            },
            onCopyKeepAliveLog: { [weak self] in
                self?.copyKeepAliveLog()
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
        debugPanelResetToken += 1
        updateSwiftUI()
    }

    private func updateSwiftUI() {
        hostingController?.rootView = VersionPageView(
            isDebugModeEnabled: isDebugModeEnabled,
            isIOS26AudioKeepAliveEnabled: isIOS26AudioKeepAliveEnabled,
            debugPanelResetToken: debugPanelResetToken,
            onShowChangelog: { [weak self] in
                self?.presentChangelog()
            },
            onShowFAQ: { [weak self] in
                self?.presentFAQ()
            },
            onCopyDebugLog: { [weak self] in
                self?.copyDebugLog()
            },
            onCopyPowerLog: { [weak self] in
                self?.copyPowerLog()
            },
            onCopyMetricLog: { [weak self] in
                self?.copyMetricLog()
            },
            onCopyKeepAliveLog: { [weak self] in
                self?.copyKeepAliveLog()
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

    private func presentChangelog() {
        let changelogController = ChangelogViewController()
        changelogController.configureAdaptivePageSheet(preferredHeightRatio: 0.58)
        present(changelogController, animated: true)
    }

    private func presentFAQ() {
        let faqController = FAQViewController()
        faqController.configureAdaptivePageSheet(preferredHeightRatio: 0.68)
        present(faqController, animated: true)
    }

    private func copyDebugLog() {
        AppDebugLogger.copyToPasteboard()
        let alert = UIAlertController(title: "调试日志已复制", message: "可以直接粘贴发送给开发者", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func copyPowerLog() {
        PowerUsageLogger.copyToPasteboard()
        let alert = UIAlertController(title: "耗电日志已复制", message: "可以直接粘贴发送给开发者", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func copyMetricLog() {
        MetricKitLogger.shared.copyToPasteboard()
        let alert = UIAlertController(title: "系统指标日志已复制", message: "MetricKit 通常需要约24小时生成数据，若暂无指标可稍后再试", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func copyKeepAliveLog() {
        KeepAliveLogger.copyToPasteboard()
        let alert = UIAlertController(title: "保活日志已复制", message: "可以直接粘贴发送给开发者", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func setDebugMode(_ isEnabled: Bool) {
        isDebugModeEnabled = isEnabled
        AppDebugLogger.isDebugModeEnabled = isEnabled
        updateSwiftUI()
    }

    private func confirmEnableDebugMode() {
        let alert = UIAlertController(
            title: "打开调试模式可能引发不稳定因素，请谨慎开启",
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认开启", style: .default) { [weak self] _ in
            self?.setDebugMode(true)
        })
        present(alert, animated: true)
    }

    private func setIOS26AudioKeepAlive(_ isEnabled: Bool) {
        isIOS26AudioKeepAliveEnabled = isEnabled
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
                version: "1.0.0（26.5.26）",
                items: ["在原版基础上增加后台保活功能和修改悬浮窗大小"]
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
                version: "1.0.2（26.6.3）",
                items: [
                    "调整自定义悬浮窗的最低值为0.1pt，可以做到完全隐藏悬浮窗"
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
                version: "1.0.4（26.6.4）",
                items: [
                    "修复低版本iOS设备闪退问题，已在iOS15.8设备调试通过"
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
                version: "1.0.6（26.6.6）",
                items: [
                    "调试模式新增 保活方案切换 开关，可尝试切换为更省电的仅PiP保活方案，但后台留存率可能下降可能出现低版本兼容性问题，可自行选择",
                    "修复关闭悬浮窗后进入后台可能自动重新开启的问题",
                    "调试模式新增复制耗电日志和系统指标日志功能，用于辅助排查耗电变化；新增复制保活日志功能，用于辅助推断后台保活中断时间段"
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
                answer: "在没有打开悬浮窗的时候，可以通过该页面的开关控制，以及上下滑动，体验一下80hz和120hz的区别"
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
