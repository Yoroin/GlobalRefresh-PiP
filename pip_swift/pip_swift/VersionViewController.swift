//
//  VersionViewController.swift
//  pip_swift
//

import UIKit
import SwiftUI
import SnapKit

private func updateVersionFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
    let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
    guard let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded) else {
        return baseFont
    }
    return UIFont(descriptor: roundedDescriptor, size: size)
}

enum DiagnosticsLogExporter {
    static func exportText() -> String {
        [
            AppDebugLogger.exportText(),
            PowerUsageLogger.exportText(),
            KeepAliveLogger.exportText()
        ].joined(separator: "\n\n==============================\n\n")
    }
}

struct AppUpdateInfo {
    let version: String
    let notes: String
    let releaseURL: URL
    let releaseNotes: [String]
    let cloudDriveURL: URL
    let githubReleasesURL: URL

    var latestVersion: String { version }
}

enum AppUpdateChecker {
    private struct Release: Decodable {
        let tagName: String
        let body: String?
        let htmlURL: URL
        let isDraft: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
            case isDraft = "draft"
        }
    }

    private static let updateRepository = "Yoroin/GlobalRefresh-PiP"
    private static let latestReleaseAPI = URL(
        string: "https://api.github.com/repos/\(updateRepository)/releases/latest"
    )!
    private static let allReleasesAPI = URL(
        string: "https://api.github.com/repos/\(updateRepository)/releases?per_page=30"
    )!
    private static let cloudDriveURL = URL(string: "https://1811629626.share.123pan.cn/123pan/KDFRVv-UEPfh")!
    private static let githubReleasesURL = URL(string: "https://github.com/\(updateRepository)/releases")!
    private static let updateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }()

    static func check(
        includePrereleases: Bool = false,
        completion: @escaping (Result<AppUpdateInfo?, Error>) -> Void
    ) {
        let endpoint = includePrereleases ? allReleasesAPI : latestReleaseAPI
        guard var endpointComponents = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              let requestURL = {
                  endpointComponents.queryItems = (endpointComponents.queryItems ?? []) + [
                      URLQueryItem(name: "_gr_cache_buster", value: UUID().uuidString)
                  ]
                  return endpointComponents.url
              }() else {
            DispatchQueue.main.async { completion(.failure(UpdateCheckError.invalidEndpoint)) }
            return
        }

        var request = URLRequest(url: requestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GlobalRefresh-PiP", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        updateSession.dataTask(with: request) { data, response, error in
            let result: Result<AppUpdateInfo?, Error>
            if let error {
                result = .failure(error)
            } else if let httpResponse = response as? HTTPURLResponse,
                      !(200..<300).contains(httpResponse.statusCode) {
                result = .failure(UpdateCheckError.httpStatus(httpResponse.statusCode))
            } else if let data {
                do {
                    let release: Release
                    if includePrereleases {
                        let releases = try JSONDecoder().decode([Release].self, from: data)
                            .filter { !$0.isDraft }
                        guard let newestRelease = releases.max(by: {
                            isNewer(normalizedVersion($1.tagName), than: normalizedVersion($0.tagName))
                        }) else {
                            throw UpdateCheckError.invalidResponse
                        }
                        release = newestRelease
                    } else {
                        release = try JSONDecoder().decode(Release.self, from: data)
                    }

                    let remoteVersion = normalizedVersion(release.tagName)
                    let localVersion = normalizedVersion(
                        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                    )
                    let update: AppUpdateInfo? = isNewer(remoteVersion, than: localVersion)
                        ? AppUpdateInfo(
                            version: remoteVersion,
                            notes: release.body ?? "",
                            releaseURL: release.htmlURL,
                            releaseNotes: releaseNotes(from: release.body ?? ""),
                            cloudDriveURL: cloudDriveURL,
                            githubReleasesURL: githubReleasesURL
                        )
                        : nil
                    result = .success(update)
                } catch {
                    result = .failure(error)
                }
            } else {
                result = .failure(UpdateCheckError.invalidResponse)
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }.resume()
    }

    private static func normalizedVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }

    private static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateValue = parsedVersion(candidate)
        let currentValue = parsedVersion(current)
        let count = max(candidateValue.parts.count, currentValue.parts.count)
        for index in 0..<count {
            let lhs = index < candidateValue.parts.count ? candidateValue.parts[index] : 0
            let rhs = index < currentValue.parts.count ? currentValue.parts[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        if candidateValue.suffix == currentValue.suffix { return false }

        let candidateStage = releaseStage(candidateValue.suffix)
        let currentStage = releaseStage(currentValue.suffix)
        if candidateStage.rank != currentStage.rank {
            return candidateStage.rank > currentStage.rank
        }

        let candidateSuffixNumbers = numericGroups(candidateValue.suffix)
        let currentSuffixNumbers = numericGroups(currentValue.suffix)
        let suffixCount = max(candidateSuffixNumbers.count, currentSuffixNumbers.count)
        for index in 0..<suffixCount {
            let lhs = index < candidateSuffixNumbers.count ? candidateSuffixNumbers[index] : 0
            let rhs = index < currentSuffixNumbers.count ? currentSuffixNumbers[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return candidateStage.normalizedSuffix.localizedStandardCompare(currentStage.normalizedSuffix) == .orderedDescending
    }

    private static func releaseStage(_ suffix: String) -> (rank: Int, normalizedSuffix: String) {
        let normalized = suffix
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_. "))
        if normalized.hasPrefix("hotfix") || normalized.hasPrefix("fix") {
            return (rank: 5, normalizedSuffix: normalized)
        }
        if normalized.isEmpty { return (rank: 4, normalizedSuffix: normalized) }
        if normalized.hasPrefix("rc") { return (rank: 3, normalizedSuffix: normalized) }
        if normalized.hasPrefix("beta") || normalized.hasPrefix("b") {
            return (rank: 2, normalizedSuffix: normalized)
        }
        if normalized.hasPrefix("alpha") || normalized.hasPrefix("a") {
            return (rank: 1, normalizedSuffix: normalized)
        }
        return (rank: 0, normalizedSuffix: normalized)
    }

    private static func parsedVersion(_ value: String) -> (parts: [Int], suffix: String) {
        let normalized = normalizedVersion(value).lowercased()
        var core = ""
        var suffix = ""
        var reachedSuffix = false
        for character in normalized {
            if !reachedSuffix, character.isNumber || character == "." {
                core.append(character)
            } else {
                reachedSuffix = true
                suffix.append(character)
            }
        }
        let parts = core.split(separator: ".").map { Int($0) ?? 0 }
        return (parts.isEmpty ? [0] : parts, suffix: suffix)
    }

    private static func numericGroups(_ value: String) -> [Int] {
        value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    private static func releaseNotes(from body: String) -> [String] {
        let lines = body.components(separatedBy: .newlines)
        var isReadingUpdateSection = false
        var notes: [String] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("## ") {
                if isReadingUpdateSection { break }
                isReadingUpdateSection = line.contains("更新内容") || line.lowercased().contains("what's new")
                continue
            }
            guard isReadingUpdateSection else { continue }
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { continue }
            let note = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { notes.append(note) }
        }

        return notes.isEmpty
            ? [L10n.text("请前往发布页面查看完整更新内容", "Open the release page to view the full changelog.")]
            : notes
    }

    enum UpdateCheckError: LocalizedError {
        case invalidEndpoint
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return "更新地址无效"
            case .invalidResponse: return "更新服务返回无效响应"
            case let .httpStatus(status): return "更新服务 HTTP \(status)"
            }
        }
    }
}

final class VersionViewController: UIViewController {
    private static let betaUpdateChannelKey = "globalRefresh.updateChannel.includePrereleases"
    private static let skippedUpdateVersionKey = "globalRefresh.updateCheck.skippedVersion"

    private var hostingController: UIHostingController<VersionPageView>?
    private var isDebugModeEnabled = AppDebugLogger.isDebugModeEnabled
    private var isDebugPanelVisible = false
    private var debugPanelResetToken = 0
    private var isCheckingForUpdate = false
    private var hasCompletedUpdateCheck = false
    private var hasUpdateCheckFailed = false
    private var availableUpdate: AppUpdateInfo?
    private var isBetaUpdateChannelEnabled = UserDefaults.standard.bool(forKey: betaUpdateChannelKey)
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
        checkForUpdates(presentResult: false)
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
            onRequestCacheCleanup: { [weak self] in
                self?.requestCacheCleanup()
            },
            onRequestUpdateCheck: { [weak self] in
                self?.requestUpdateCheck()
            },
            onRequestClearAllData: { [weak self] in
                self?.requestClearAllData()
            },
            hasAvailableUpdate: availableUpdate != nil,
            hasCompletedUpdateCheck: hasCompletedUpdateCheck,
            hasUpdateCheckFailed: hasUpdateCheckFailed,
            isCheckingForUpdate: isCheckingForUpdate,
            isBetaUpdateChannelEnabled: isBetaUpdateChannelEnabled,
            onSetDebugMode: { [weak self] newValue in
                self?.setDebugMode(newValue)
            },
            onRequestEnableDebugMode: { [weak self] in
                self?.confirmEnableDebugMode()
            },
            onSetIOS26AudioKeepAlive: { [weak self] newValue in
                self?.setIOS26AudioKeepAlive(newValue)
            },
            onSetBetaUpdateChannelEnabled: { [weak self] newValue in
                self?.setBetaUpdateChannelEnabled(newValue)
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
            onRequestCacheCleanup: { [weak self] in
                self?.requestCacheCleanup()
            },
            onRequestUpdateCheck: { [weak self] in
                self?.requestUpdateCheck()
            },
            onRequestClearAllData: { [weak self] in
                self?.requestClearAllData()
            },
            hasAvailableUpdate: availableUpdate != nil,
            hasCompletedUpdateCheck: hasCompletedUpdateCheck,
            hasUpdateCheckFailed: hasUpdateCheckFailed,
            isCheckingForUpdate: isCheckingForUpdate,
            isBetaUpdateChannelEnabled: isBetaUpdateChannelEnabled,
            onSetDebugMode: { [weak self] newValue in
                self?.setDebugMode(newValue)
            },
            onRequestEnableDebugMode: { [weak self] in
                self?.confirmEnableDebugMode()
            },
            onSetIOS26AudioKeepAlive: { [weak self] newValue in
                self?.setIOS26AudioKeepAlive(newValue)
            },
            onSetBetaUpdateChannelEnabled: { [weak self] newValue in
                self?.setBetaUpdateChannelEnabled(newValue)
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

    private func setBetaUpdateChannelEnabled(_ isEnabled: Bool) {
        guard isBetaUpdateChannelEnabled != isEnabled else { return }
        isBetaUpdateChannelEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.betaUpdateChannelKey)
        availableUpdate = nil
        hasCompletedUpdateCheck = false
        hasUpdateCheckFailed = false
        updateSwiftUI()
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启Beta版本更新检测" : "关闭Beta版本更新检测")
        checkForUpdates(presentResult: false)
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

    private func requestCacheCleanup() {
        DiagnosticsRuntimeState.recordUserAction("请求清理缓存")
        let alert = UIAlertController(
            title: L10n.text("清理缓存", "Clear Cache"),
            message: L10n.text(
                "将清理临时素材、过期缓存和生成的视频缓存，不会删除应用设置。",
                "This removes temporary assets, expired cache entries, and generated video cache. App settings are kept."
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.text("清理", "Clear"), style: .destructive) { [weak self] _ in
            CacheCleanupManager.clearManually { [weak self] report in
                let message = report.hasChanges
                    ? L10n.text(
                        "已清理 \(report.removedItems) 项，释放约 \(ByteCountFormatter.string(fromByteCount: report.freedBytes, countStyle: .file))。",
                        "Removed \(report.removedItems) item(s), freeing about \(ByteCountFormatter.string(fromByteCount: report.freedBytes, countStyle: .file))."
                    )
                    : L10n.text("没有发现可清理的缓存。", "No removable cache was found.")
                let result = UIAlertController(
                    title: L10n.text("清理完成", "Cache Cleared"),
                    message: message,
                    preferredStyle: .alert
                )
                result.addAction(UIAlertAction(title: L10n.ok, style: .default))
                self?.present(result, animated: true)
            }
        })
        present(alert, animated: true)
    }

    private func requestClearAllData() {
        DiagnosticsRuntimeState.recordUserAction("请求清空全部应用数据")
        let alert = UIAlertController(
            title: L10n.cacheCleanupTitle,
            message: L10n.cacheCleanupMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.cacheCleanupConfirm, style: .destructive) { [weak self] _ in
            guard let self else { return }
            CacheCleanupManager.resetAllAppData()
            let result = UIAlertController(
                title: L10n.cacheCleanupCompleted,
                message: L10n.text("应用数据已清空，返回首页后会重新进入首次使用流程。", "App data was cleared. The first-launch flow will appear when Home is shown again."),
                preferredStyle: .alert
            )
            result.addAction(UIAlertAction(title: L10n.ok, style: .default))
            self.present(result, animated: true)
        })
        present(alert, animated: true)
    }

    private func requestUpdateCheck() {
        checkForUpdates(presentResult: true)
    }

    private func checkForUpdates(presentResult: Bool) {
        guard !isCheckingForUpdate else { return }

        isCheckingForUpdate = true
        hasCompletedUpdateCheck = false
        hasUpdateCheckFailed = false
        availableUpdate = nil
        UIView.performWithoutAnimation {
            updateSwiftUI()
        }
        DiagnosticsRuntimeState.recordUserAction(
            presentResult ? "手动检查应用更新" : "进入版本页自动检查更新"
        )

        AppUpdateChecker.check(includePrereleases: isBetaUpdateChannelEnabled) { [weak self] result in
            guard let self else { return }
            self.isCheckingForUpdate = false

            switch result {
            case .success(let update):
                self.hasCompletedUpdateCheck = true
                self.hasUpdateCheckFailed = false
                let skippedVersion = UserDefaults.standard.string(forKey: Self.skippedUpdateVersionKey)
                let shouldSuppressSkippedUpdate = !presentResult
                    && update?.latestVersion == skippedVersion
                if shouldSuppressSkippedUpdate {
                    self.availableUpdate = nil
                    AppDebugLogger.log("自动检查忽略已跳过版本：\(skippedVersion ?? "unknown")")
                } else {
                    self.availableUpdate = update
                    if presentResult || (update != nil && update?.latestVersion != skippedVersion) {
                        UserDefaults.standard.removeObject(forKey: Self.skippedUpdateVersionKey)
                    }
                }
            case .failure:
                self.hasCompletedUpdateCheck = false
                self.hasUpdateCheckFailed = true
                self.availableUpdate = nil
            }

            UIView.performWithoutAnimation {
                self.updateSwiftUI()
            }

            guard presentResult else { return }
            self.presentUpdateCheckResult(result)
        }
    }

    private func skipUpdate(_ update: AppUpdateInfo) {
        UserDefaults.standard.set(update.latestVersion, forKey: Self.skippedUpdateVersionKey)
        if availableUpdate?.latestVersion == update.latestVersion {
            availableUpdate = nil
        }
        hasCompletedUpdateCheck = true
        hasUpdateCheckFailed = false
        UIView.performWithoutAnimation {
            updateSwiftUI()
        }
        DiagnosticsRuntimeState.recordUserAction("跳过版本更新：\(update.latestVersion)")
        AppDebugLogger.log("已跳过版本更新：\(update.latestVersion)")
    }

    private func presentUpdateCheckResult(_ result: Result<AppUpdateInfo?, Error>) {
        switch result {
        case .success(nil):
            present(UpdateStatusViewController(), animated: true)
        case let .success(update?):
            present(
                UpdateAvailableViewController(
                    update: update,
                    onSkipUpdate: { [weak self] skippedUpdate in
                        self?.skipUpdate(skippedUpdate)
                    }
                ),
                animated: true
            )
        case let .failure(error):
            let alert = UIAlertController(
                title: L10n.text("检查更新失败", "Update Check Failed"),
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.ok, style: .cancel))
            present(alert, animated: true)
        }
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

struct AppChangelogSection {
    let version: String
    let items: [String]
}

enum AppChangelogCatalog {
    static var latest: AppChangelogSection {
        AppChangelogSection(
            version: L10n.text("1.1.0（26.8.22）", "1.1.0 (2026.8.22)"),
            items: [
                L10n.text("版本页新增手动清理缓存按钮；长按可清空全部应用数据并重新进入首次使用流程", "Added manual cache cleanup on the Version page; long press to reset all app data and return to first-time setup."),
                L10n.text("新增自动缓存清理，首次安装、覆盖更新和日常启动时会清理过期临时素材", "Added automatic cleanup of expired temporary assets on install, update, and normal launch."),
                L10n.text("清理并限制动态悬浮窗视频缓存，修复部分用户存储占用持续增长的问题", "Cleaned up and limited generated floating-window video caches to prevent storage usage from continuously growing for some users."),
                L10n.text("快捷指令改为默认关闭的风险功能，确认可能阻止自动熄屏后才开放安装和使用", "Shortcuts are now opt-in and require confirmation because one-tap hiding may prevent auto-lock."),
                L10n.text("新增应用内 GitHub Releases 版本检测，不会自动下载或修改 App", "Added in-app GitHub Releases version checking; the app is never downloaded or modified automatically."),
                L10n.text("帧率演示新增 80Hz 与 120Hz 同速动画对比，并保留两个蓝色球", "Added same-speed 80 Hz and 120 Hz animation comparison while keeping the two blue balls."),
                L10n.text("新增首次启动动画与使用教程，通知权限在引导结束后申请", "Added a first-launch animation and tutorial; notification permission is requested after onboarding."),
                L10n.text("新增首页本次更新弹窗，可进入完整更新日志", "Added a What's New popup on Home with access to the full changelog."),
                L10n.text("优化更新日志、常见问题等弹窗的背景、圆角和滚动显示", "Improved the backgrounds, corners, and scrolling of Changelog and FAQ sheets."),
                L10n.text("统一中英文状态、运行时间和更新提示文案", "Improved Chinese and English status, runtime, and update messages."),
                L10n.text("修复 iOS 26 以下切换深浅色模式后界面图标可能消失的问题", "Fixed interface icons disappearing after appearance changes below iOS 26."),
                L10n.text("深浅色模式检测仅在 App 前台运行，进入后台后停止轮询", "Appearance detection runs only in the foreground."),
                L10n.text("覆盖更新后默认关闭调试模式并清理历史诊断数据", "Debug Mode is disabled after an update and old diagnostics are cleared."),
                L10n.text("保留 1.0.9fix 的悬浮窗创建、高度调节和 120Hz 核心路径", "Preserved the 1.0.9fix PiP creation, sizing, and 120 Hz core paths.")
            ]
        )
    }
}

final class LatestChangelogViewController: UIViewController {
    private let onDismiss: () -> Void
    private let onOpenFullChangelog: () -> Void

    init(onDismiss: @escaping () -> Void, onOpenFullChangelog: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.onOpenFullChangelog = onOpenFullChangelog
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        view.accessibilityViewIsModal = true

        let card = UIView()
        card.layer.cornerRadius = 30
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.16
        card.layer.shadowRadius = 24
        card.layer.shadowOffset = CGSize(width: 0, height: 10)
        view.addSubview(card)

        let glassView: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            glassView = UIVisualEffectView(effect: effect)
        } else {
            glassView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            glassView.contentView.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.42)
        }
        glassView.layer.cornerRadius = 30
        glassView.layer.cornerCurve = .continuous
        glassView.clipsToBounds = true
        card.addSubview(glassView)

        let titleLabel = UILabel()
        titleLabel.text = L10n.text("本次更新", "What's New")
        titleLabel.font = .systemFont(ofSize: 26, weight: .black)
        titleLabel.textColor = .label

        let versionLabel = UILabel()
        versionLabel.text = AppChangelogCatalog.latest.version
        versionLabel.font = .systemFont(ofSize: UIScreen.main.bounds.height < 700 ? 21 : 23, weight: .bold)
        versionLabel.textColor = .systemBlue
        versionLabel.numberOfLines = 1

        let header = UIStackView(arrangedSubviews: [titleLabel, versionLabel])
        header.axis = .vertical
        header.spacing = 5
        card.addSubview(header)

        let items = UIStackView()
        items.axis = .vertical
        items.spacing = 13
        for item in AppChangelogCatalog.latest.items {
            let label = UILabel()
            label.text = "• \(item)"
            label.font = .systemFont(ofSize: 15, weight: .semibold)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            items.addArrangedSubview(label)
        }

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.addSubview(items)
        card.addSubview(scrollView)

        let fullLogButton = UIButton(configuration: .bordered())
        var fullLogConfiguration = fullLogButton.configuration
        fullLogConfiguration?.title = L10n.text("查看完整更新日志", "View Full Changelog")
        fullLogConfiguration?.baseForegroundColor = .systemBlue
        fullLogConfiguration?.cornerStyle = .capsule
        fullLogButton.configuration = fullLogConfiguration
        fullLogButton.addTarget(self, action: #selector(fullLogTapped), for: .touchUpInside)

        let acknowledgeButton = UIButton(configuration: .filled())
        var acknowledgeConfiguration = acknowledgeButton.configuration
        acknowledgeConfiguration?.title = L10n.text("我知道了", "Got It")
        acknowledgeConfiguration?.baseBackgroundColor = .systemBlue
        acknowledgeConfiguration?.baseForegroundColor = .white
        acknowledgeConfiguration?.cornerStyle = .capsule
        acknowledgeButton.configuration = acknowledgeConfiguration
        acknowledgeButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [fullLogButton, acknowledgeButton])
        buttons.axis = .vertical
        buttons.spacing = 10
        card.addSubview(buttons)

        [card, glassView, header, scrollView, items, buttons].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        let safe = view.safeAreaLayoutGuide
        let cardHeight = UIScreen.main.bounds.height < 700 ? 0.72 : 0.64
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 22),
            card.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -22),
            card.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            card.heightAnchor.constraint(equalTo: safe.heightAnchor, multiplier: cardHeight),
            glassView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            glassView.topAnchor.constraint(equalTo: card.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            header.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -16),
            items.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            items.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            items.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            items.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            items.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            buttons.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            buttons.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            buttons.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            fullLogButton.heightAnchor.constraint(equalToConstant: 44),
            acknowledgeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func dismissTapped() {
        onDismiss()
    }

    @objc private func fullLogTapped() {
        onOpenFullChangelog()
    }
}

final class ChangelogViewController: UIViewController {
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
            makeSection(section: AppChangelogCatalog.latest),
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

    private func makeSection(section: AppChangelogSection) -> UIView {
        makeSection(version: section.version, items: section.items)
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

private final class UpdateAvailableViewController: UIViewController {
    private let update: AppUpdateInfo
    private let onSkipUpdate: (AppUpdateInfo) -> Void

    init(update: AppUpdateInfo, onSkipUpdate: @escaping (AppUpdateInfo) -> Void) {
        self.update = update
        self.onSkipUpdate = onSkipUpdate
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        view.accessibilityViewIsModal = true

        let card = UIView()
        let cornerRadius: CGFloat = 28
        card.backgroundColor = .clear
        card.layer.cornerRadius = cornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.16
        card.layer.shadowRadius = 22
        card.layer.shadowOffset = CGSize(width: 0, height: 9)
        view.addSubview(card)

        let glassView = makeGlassView(cornerRadius: cornerRadius)
        card.addSubview(glassView)

        let titleLabel = UILabel()
        titleLabel.text = L10n.text("检测到新版本", "New Version Available")
        titleLabel.font = updateVersionFont(size: 24, weight: .black)
        titleLabel.textColor = .label

        let versionLabel = UILabel()
        versionLabel.text = update.latestVersion
        versionLabel.font = updateVersionFont(
            size: UIScreen.main.bounds.height < 700 ? 21 : 23,
            weight: .bold
        )
        versionLabel.textColor = .systemBlue

        let header = UIStackView(arrangedSubviews: [titleLabel, versionLabel])
        header.axis = .vertical
        header.spacing = 5
        card.addSubview(header)

        let items = UIStackView()
        items.axis = .vertical
        items.spacing = 12
        for note in update.releaseNotes {
            let label = UILabel()
            label.text = "• \(note)"
            label.font = .systemFont(ofSize: 15, weight: .semibold)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            items.addArrangedSubview(label)
        }

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.addSubview(items)
        card.addSubview(scrollView)

        let cloudButton = makeLinkButton(title: L10n.text("123云盘", "123 Cloud"))
        cloudButton.addTarget(self, action: #selector(openCloudDrive), for: .touchUpInside)
        let githubButton = makeLinkButton(title: "GitHub")
        githubButton.addTarget(self, action: #selector(openGitHub), for: .touchUpInside)
        let skipButton = makeLinkButton(title: L10n.text("跳过本次更新", "Skip This Update"))
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        let laterButton = makeLinkButton(title: L10n.text("稍后", "Later"), primary: true)
        laterButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

        let links = UIStackView(arrangedSubviews: [cloudButton, githubButton])
        links.axis = .vertical
        links.spacing = 8
        let buttons = UIStackView(arrangedSubviews: [links, skipButton, laterButton])
        buttons.axis = .vertical
        buttons.spacing = 6
        card.addSubview(buttons)

        [card, glassView, header, scrollView, items, buttons].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        let safe = view.safeAreaLayoutGuide
        let cardHeightMultiplier: CGFloat = UIScreen.main.bounds.height < 700 ? 0.68 : 0.58
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 22),
            card.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -22),
            card.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            card.heightAnchor.constraint(equalTo: safe.heightAnchor, multiplier: cardHeightMultiplier),
            glassView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            glassView.topAnchor.constraint(equalTo: card.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            header.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 15),
            scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -14),
            items.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            items.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            items.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            items.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            items.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            buttons.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            buttons.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            buttons.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            cloudButton.heightAnchor.constraint(equalToConstant: 42),
            githubButton.heightAnchor.constraint(equalToConstant: 42),
            skipButton.heightAnchor.constraint(equalToConstant: 42),
            laterButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func makeGlassView(cornerRadius: CGFloat) -> UIVisualEffectView {
        let glassView: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            glassView = UIVisualEffectView(effect: effect)
        } else {
            glassView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            glassView.contentView.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.42)
        }
        glassView.layer.cornerRadius = cornerRadius
        glassView.layer.cornerCurve = .continuous
        glassView.clipsToBounds = true
        return glassView
    }

    private func makeLinkButton(title: String, primary: Bool = false) -> UIButton {
        let button = UIButton(configuration: primary ? .filled() : .bordered())
        var configuration = button.configuration
        configuration?.title = title
        configuration?.baseForegroundColor = primary ? .white : .systemBlue
        configuration?.baseBackgroundColor = primary ? .systemBlue : nil
        configuration?.cornerStyle = .capsule
        button.configuration = configuration
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        return button
    }

    @objc private func openCloudDrive() {
        UIApplication.shared.open(update.cloudDriveURL)
    }

    @objc private func openGitHub() {
        UIApplication.shared.open(update.githubReleasesURL)
    }

    @objc private func skipTapped() {
        onSkipUpdate(update)
        dismiss(animated: true)
    }

    @objc private func dismissTapped() {
        dismiss(animated: true)
    }
}

private final class UpdateStatusViewController: UIViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        view.accessibilityViewIsModal = true

        let card = UIView()
        let cornerRadius: CGFloat = 28
        card.backgroundColor = .clear
        card.layer.cornerRadius = cornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.14
        card.layer.shadowRadius = 20
        card.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.addSubview(card)

        let glassView: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            glassView = UIVisualEffectView(effect: effect)
        } else {
            glassView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            glassView.contentView.backgroundColor = UIColor.systemGroupedBackground.withAlphaComponent(0.42)
        }
        glassView.layer.cornerRadius = cornerRadius
        glassView.layer.cornerCurve = .continuous
        glassView.clipsToBounds = true
        card.addSubview(glassView)

        let icon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        icon.tintColor = .systemGreen
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 32, weight: .semibold)

        let titleLabel = UILabel()
        titleLabel.text = L10n.text("已是最新版本", "You're Up to Date")
        titleLabel.font = updateVersionFont(size: 23, weight: .black)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        let versionLabel = UILabel()
        versionLabel.text = "\(L10n.text("当前版本", "Current version"))  \(L10n.versionDisplay)"
        versionLabel.font = updateVersionFont(size: 16, weight: .bold)
        versionLabel.textColor = .systemBlue
        versionLabel.textAlignment = .center

        let messageLabel = UILabel()
        messageLabel.text = L10n.text(
            "当前没有检测到可用的新正式版本，敬请期待下一次更新。",
            "No newer stable release is available yet. Stay tuned for the next update."
        )
        messageLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        let dismissButton = UIButton(configuration: .filled())
        var configuration = dismissButton.configuration
        configuration?.title = L10n.text("知道了", "Got It")
        configuration?.baseForegroundColor = .white
        configuration?.baseBackgroundColor = .systemBlue
        configuration?.cornerStyle = .capsule
        dismissButton.configuration = configuration
        dismissButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, versionLabel, messageLabel, dismissButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 11
        card.addSubview(stack)

        [card, glassView, stack, icon, dismissButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 28),
            card.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -28),
            card.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            card.heightAnchor.constraint(equalToConstant: 284),
            glassView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            glassView.topAnchor.constraint(equalTo: card.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -26),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.heightAnchor.constraint(equalToConstant: 36),
            dismissButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    @objc private func dismissTapped() {
        dismiss(animated: true)
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
