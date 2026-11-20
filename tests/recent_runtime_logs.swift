import Foundation
import Darwin
import OSLog

let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
enum UIDevice {
    static let current = UIDeviceStub()
    struct UIDeviceStub { let systemVersion = "test" }
}
enum UIApplication {
    static let didEnterBackgroundNotification = Notification.Name("test.background")
    static let willTerminateNotification = Notification.Name("test.terminate")
}
final class UIPasteboard {
    static let general = UIPasteboard()
    var string: String?
}
enum DiagnosticsRuntimeState {
    static func updateLastEvent(_ value: String) {}
    static func snapshotText() -> String { "state" }
    static func reset() {}
}
enum DebugDiagnosticsMonitor { static let isEnabled = false }
enum PerformanceDiagnosticsLogger { static func currentSnapshotText() -> String { "snapshot" } }
enum ProcessTerminationDiagnostics {
    static func exportText() -> String { "termination" }
    static func reset() {}
}
enum KeepAliveModeText { static let current = "test" }

func runTests() throws {
    defer { try? FileManager.default.removeItem(at: testDirectory) }
    AppDebugLogger.isDebugModeEnabled = false
    AppDebugLogger.resetLogs(includingRecentRuntime: true)
    AppDebugLogger.log("VERBOSE-MUST-NOT-APPEAR")
    AppDebugLogger.logRuntime("PASSIVE-EVENT")
    AppDebugLogger.logCritical("CRITICAL-EVENT")
    var report = AppDebugLogger.exportText(newestFirst: true)
    precondition(report.contains("PASSIVE-EVENT") && report.contains("CRITICAL-EVENT"))
    precondition(report.contains("最多2份，每份4000000字节"))
    precondition(!report.contains("VERBOSE-MUST-NOT-APPEAR"))
    precondition(report.range(of: "CRITICAL-EVENT")!.lowerBound < report.range(of: "PASSIVE-EVENT")!.lowerBound)
    AppDebugLogger.resetLogs()
    AppDebugLogger.flush()
    UserDefaults.standard.set(["LEGACY-DETAILED-LOG"], forKey: "pip.debug.recentLogs")
    AppDebugLogger.isDebugModeEnabled = true
    AppDebugLogger.trimOnLaunch()
    report = AppDebugLogger.exportText()
    precondition(report.contains("PASSIVE-EVENT") && report.contains("LEGACY-DETAILED-LOG"))
    let archive = DetailedDebugLogArchive(directory: testDirectory.appendingPathComponent("GlobalRefreshDiagnostics"))
    precondition(archive.load() == ["LEGACY-DETAILED-LOG"])
    precondition(UserDefaults.standard.object(forKey: "pip.debug.recentLogs") == nil)

    AppDebugLogger.isDebugModeEnabled = true
    AppDebugLogger.log("FULL-DEBUG-EVENT")
    precondition(AppDebugLogger.exportText().contains("FULL-DEBUG-EVENT"))
    for i in 0..<100 { AppDebugLogger.logCritical("BURST-\(i)-END") }
    precondition(AppDebugLogger.exportText().contains("BURST-99-END"))
    precondition(archive.load() == ["LEGACY-DETAILED-LOG"], "Critical events must not rewrite the detailed archive")
    AppDebugLogger.flush(force: true)
    _ = AppDebugLogger.exportText()
    precondition(archive.load()?.contains(where: { $0.contains("BURST-99-END") }) == true)
    AppDebugLogger.isDebugModeEnabled = false
    AppDebugLogger.resetLogs()
    report = AppDebugLogger.exportText()
    precondition(report.contains("PASSIVE-EVENT") && !report.contains("FULL-DEBUG-EVENT"))
    AppDebugLogger.trimForMemoryPressure()
    precondition(AppDebugLogger.exportText().contains("CRITICAL-EVENT"))
    AppDebugLogger.resetLogs(includingRecentRuntime: true)
    precondition(!AppDebugLogger.exportText().contains("PASSIVE-EVENT"))

    let archiveTest = DetailedDebugLogArchive(directory: testDirectory.appendingPathComponent("archive"))
    archiveTest.markChanged()
    let first = try archiveTest.save(["first"], at: 10)
    archiveTest.markChanged()
    let tooSoon = try archiveTest.save(["second"], at: 69)
    precondition(first && !tooSoon && archiveTest.load() == ["first"])
    let second = try archiveTest.save(["second"], at: 70)
    let unchanged = try archiveTest.save(["unexpected"], at: 130)
    precondition(second && !unchanged && archiveTest.load() == ["second"])
    archiveTest.reset()
    precondition(archiveTest.load() == nil)

    let rotationDirectory = testDirectory.appendingPathComponent("rotation")
    let store = RecentRuntimeLogStore(directory: rotationDirectory, maximumFileBytes: 256, maximumEntryBytes: 128)
    for index in 0..<30 { store.append("event-\(index):" + String(repeating: "x", count: 85)) }
    report = store.exportText(newestFirst: true)
    precondition(report.contains("event-29:") && !report.contains("event-0:"))
    let files = try FileManager.default.contentsOfDirectory(at: rotationDirectory, includingPropertiesForKeys: [.fileSizeKey])
    precondition(files.count == 2)
    let filesWithinLimit = try files.allSatisfy { try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize! <= 256 }
    precondition(filesWithinLimit)
    let reopened = RecentRuntimeLogStore(directory: rotationDirectory, maximumFileBytes: 256, maximumEntryBytes: 128)
    precondition(reopened.exportText(newestFirst: false).contains("event-29:"))
    store.append(String(repeating: "中文🙂\n", count: 1000))
    report = store.exportText(newestFirst: false)
    precondition(report.contains("[truncated]") && !report.contains("\u{FFFD}"))
    for file in try FileManager.default.contentsOfDirectory(at: rotationDirectory, includingPropertiesForKeys: nil) {
        let data = try Data(contentsOf: file)
        precondition(data.count <= 256 && String(data: data, encoding: .utf8) != nil)
    }
    store.reset()
    let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: rotationDirectory.path)
    precondition(remainingFiles.isEmpty)

    let concurrent = RecentRuntimeLogStore(directory: testDirectory.appendingPathComponent("concurrent"))
    DispatchQueue.concurrentPerform(iterations: 100) { concurrent.append("concurrent-\($0):end") }
    report = concurrent.exportText(newestFirst: false)
    for index in 0..<100 { precondition(report.contains("concurrent-\(index):end")) }
    concurrent.reset()
    precondition(!concurrent.exportText(newestFirst: false).contains("concurrent-"))
    concurrent.append("RESET-BEFORE-FLUSH")
    concurrent.reset()
    precondition(!concurrent.exportText(newestFirst: false).contains("RESET-BEFORE-FLUSH"))
    let blockedDirectory = testDirectory.appendingPathComponent("blocked")
    try Data("not-a-directory".utf8).write(to: blockedDirectory)
    let failed = RecentRuntimeLogStore(directory: blockedDirectory)
    failed.append("must-not-crash")
    precondition(failed.exportText(newestFirst: false).contains("读写失败"))
    print("PASS: legacy migration, no full rewrites on critical bursts, rate-limited archive, pending export, debug-off routing, rotation and reset")
}
