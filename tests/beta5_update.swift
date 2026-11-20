import Foundation

@main
struct UpdateTests {
    static func main() {
        let version = "1.1.1"
        let names = ["GlobalRefresh_1.1.1_2026100902_unsigned.ipa", "GlobalRefresh_1.1.1_2026100901_unsigned.ipa",
                     "GlobalRefresh_1.1.1beta3_2026111801_unsigned.ipa", "old_2026111901_unsigned.ipa",
                     "GlobalRefresh_1.1.1_2026-10099_unsigned.ipa", "GlobalRefresh_1.1.1_2026111801_signed.ipa"]
        let build = AppUpdateChecker.publishedBuild(for: version, assetNames: names)
        precondition(build == 2026100902 && AppUpdateChecker.publishedBuild(for: version, assetNames: []) == nil)
        for (v, b, local, installed, expected): (String, Int?, String, String?, Bool) in [
            (version, build, version, "2026100901", true), (version, build, version, "2026100902", false),
            (version, build, version, "2026100903", false), (version, nil, version, "2026100901", false),
            ("1.1.1", nil, "1.1.0fix", nil, true), ("1.1.2beta5", nil, "1.1.2beta4", nil, true),
            ("1.1.2beta5", 2026111801, "1.1.2", "1", false)
        ] {
            precondition(AppUpdateChecker.offersUpdate(version: v, build: b, localVersion: local, localBuild: installed) == expected)
        }
        let view = ChannelHarness()
        defer {
            UserDefaults.standard.removeObject(forKey: ChannelHarness.betaUpdateChannelKey)
            UserDefaults.standard.removeObject(forKey: ChannelHarness.skippedUpdateVersionKey)
        }
        view.checkForUpdates(presentResult: true)
        let first = ChannelHarness.AppUpdateChecker.pending[0]
        view.setBetaUpdateChannelEnabled(true)
        let second = ChannelHarness.AppUpdateChecker.pending[1]
        precondition(first.task.cancelled && !first.beta && second.beta)
        first.finish(.failure(CocoaError(.userCancelled)))
        precondition(view.isCheckingForUpdate && view.presented == 0 && !view.hasUpdateCheckFailed)
        let url = URL(fileURLWithPath: "/")
        let info = AppUpdateInfo(version: version, build: build, notes: "", releaseURL: url,
                                 releaseNotes: [], cloudDriveURL: url, githubReleasesURL: url)
        second.finish(.success(info))
        first.finish(.success(nil))
        precondition(!view.isCheckingForUpdate && view.hasCompletedUpdateCheck && view.presented == 0)
        precondition(view.availableUpdate?.latestVersion == "1.1.1 (2026100902)")
        print("PASS: canonical same-version builds, version rank and out-of-order channel responses")
    }
}

enum UIView { static func performWithoutAnimation(_ work: () -> Void) { work() } }
enum AppDebugLogger { static func log(_ text: String) {} }
enum DiagnosticsRuntimeState { static func recordUserAction(_ text: String) {} }
final class ChannelHarness {
    static let betaUpdateChannelKey = UUID().uuidString
    static let skippedUpdateVersionKey = UUID().uuidString
    final class Task {
        var cancelled = false
        func cancel() { cancelled = true }
    }
    enum AppUpdateChecker {
        typealias Callback = (Result<AppUpdateInfo?, Error>) -> Void
        static var pending: [(beta: Bool, task: Task, finish: Callback)] = []
        static func check(includePrereleases: Bool, completion: @escaping Callback) -> Task {
            let task = Task()
            pending.append((includePrereleases, task, completion))
            return task
        }
    }
    var isBetaUpdateChannelEnabled = false
    var isCheckingForUpdate = false
    var hasCompletedUpdateCheck = false
    var hasUpdateCheckFailed = false
    var availableUpdate: AppUpdateInfo?
    var updateRequestID: UUID?
    var updateTask: Task?
    var presented = 0
    func updateSwiftUI() {}
    func presentUpdateCheckResult(_ result: Result<AppUpdateInfo?, Error>) { presented += 1 }
