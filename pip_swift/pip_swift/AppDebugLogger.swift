//
//  AppDebugLogger.swift
//  pip_swift
//

import UIKit
import AVFoundation
import Darwin
import OSLog

final class RecentRuntimeLogStore {
    private let directory: URL
    private let maximumFileBytes: Int
    private let maximumEntryBytes: Int
    private let queue = DispatchQueue(label: "com.yoroin.globalrefresh.recentRuntimeLog", qos: .utility)
    private var lastWriteError: String?
    private var pending: [Data] = []
    private var pendingBytes = 0
    private var scheduledWrite: DispatchWorkItem?

    init(directory: URL, maximumFileBytes: Int = 4_000_000, maximumEntryBytes: Int = 4096) {
        precondition(maximumFileBytes >= maximumEntryBytes && maximumEntryBytes >= 64)
        self.directory = directory
        self.maximumFileBytes = maximumFileBytes
        self.maximumEntryBytes = maximumEntryBytes
    }

    private var currentURL: URL { directory.appendingPathComponent("recent-runtime.log") }
    private var previousURL: URL { directory.appendingPathComponent("recent-runtime.previous.log") }

    func append(_ entry: String) {
        let escaped = entry.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
        let data = Data((boundedEntry(escaped) + "\n").utf8)
        queue.async { [self] in
            pending.append(data)
            pendingBytes += data.count
            if pendingBytes >= min(32 * 1024, maximumFileBytes) {
                writePending()
            } else if scheduledWrite == nil {
                let task = DispatchWorkItem { [weak self] in self?.writePending() }
                scheduledWrite = task
                queue.asyncAfter(deadline: .now() + .milliseconds(500), execute: task)
            }
        }
    }

    func flush() {
        queue.async { [self] in writePending() }
    }

    private func writePending() {
        scheduledWrite?.cancel()
        scheduledWrite = nil
        guard !pending.isEmpty else { return }
        defer { pending.removeAll(keepingCapacity: true); pendingBytes = 0 }
        let files = FileManager.default
        do {
            try DiagnosticLogFiles.prepare(directory)
            var size = (try? currentURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            var batch = Data()
            for entry in pending {
                if size + batch.count + entry.count > maximumFileBytes {
                    try appendBatch(batch, to: currentURL)
                    if files.fileExists(atPath: previousURL.path) { try files.removeItem(at: previousURL) }
                    try files.moveItem(at: currentURL, to: previousURL)
                    batch.removeAll(keepingCapacity: true)
                    size = 0
                }
                batch.append(entry)
            }
            try appendBatch(batch, to: currentURL)
            lastWriteError = nil
        } catch {
            lastWriteError = error.localizedDescription
        }
    }

    private func appendBatch(_ data: Data, to url: URL) throws {
        guard !data.isEmpty else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            try DiagnosticLogFiles.writeAtomically(data, to: url)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func exportText(newestFirst: Bool) -> String {
        queue.sync {
            writePending()
            var entries: [String] = []
            for url in [previousURL, currentURL] where FileManager.default.fileExists(atPath: url.path) {
                do {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: maximumFileBytes) ?? Data()
                    entries += String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
                } catch {
                    lastWriteError = error.localizedDescription
                }
            }
            if newestFirst { entries.reverse() }
            return """
            轻量关键事件日志（关闭调试模式时仍保存）
            存储：本地滚动文件，最多2份，每份\(maximumFileBytes)字节；不逐帧记录，不启动性能采样或常驻写盘定时器。
            排列顺序：\(newestFirst ? "最新在前" : "按时间顺序")。仅代表成功记录的现场，不等于系统确认的终止原因；进程被杀的瞬间无法保证记录。
            文件状态：\(lastWriteError.map { "读写失败：\($0)" } ?? "正常")
            \(entries.isEmpty ? "暂无关键事件" : entries.joined(separator: "\n"))
            """
        }
    }

    func reset() {
        queue.sync {
            scheduledWrite?.cancel()
            scheduledWrite = nil
            pending.removeAll(keepingCapacity: false)
            pendingBytes = 0
            do {
                for url in [previousURL, currentURL] where FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                lastWriteError = nil
            } catch {
                lastWriteError = error.localizedDescription
            }
        }
    }

    private func boundedEntry(_ entry: String) -> String {
        guard entry.utf8.count + 1 > maximumEntryBytes else { return entry }
        let marker = " [truncated]"
        var prefix = Data(entry.utf8.prefix(maximumEntryBytes - marker.utf8.count - 1))
        while String(data: prefix, encoding: .utf8) == nil { prefix.removeLast() }
        return String(decoding: prefix, as: UTF8.self) + marker
    }
}

private enum DiagnosticLogFiles {
    static func prepare(_ directory: URL) throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    static func writeAtomically(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

// Access is serialized by AppDebugLogger.logQueue.
final class DetailedDebugLogArchive {
    private let url: URL
    private let minimumInterval: TimeInterval
    private var lastWrite: TimeInterval?
    private var hasChanges = false

    init(directory: URL, minimumInterval: TimeInterval = 60) {
        url = directory.appendingPathComponent("detailed-debug.plist")
        self.minimumInterval = minimumInterval
    }

    func load() -> [String]? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size <= 6_100_000, let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode([String].self, from: data)
    }

    func markChanged() { hasChanges = true }

    @discardableResult
    func save(_ entries: [String], at now: TimeInterval, force: Bool = false) throws -> Bool {
        guard hasChanges, force || lastWrite.map({ now - $0 >= minimumInterval }) != false else { return false }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try DiagnosticLogFiles.prepare(url.deletingLastPathComponent())
        try DiagnosticLogFiles.writeAtomically(try encoder.encode(entries), to: url)
        hasChanges = false
        lastWrite = now
        return true
    }

    func reset() {
        try? FileManager.default.removeItem(at: url)
        hasChanges = false
        lastWrite = nil
    }
}

enum AppDebugLogger {
    private static let legacyStorageKey = "pip.debug.recentLogs"
    private static let debugModeKey = "pip.debug.modeEnabled"
    private static let maximumEntries = 1200
    private static let maximumEntryBytes = 16 * 1024
    private static let maximumBufferBytes = 3_000_000
    private static let logger = Logger(subsystem: "com.yoroin.globalrefresh", category: "diagnostics")
    private static let logQueueKey = DispatchSpecificKey<Void>()
    private static let logQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.yoroin.globalrefresh.appDebugLog", qos: .utility)
        queue.setSpecific(key: logQueueKey, value: ())
        return queue
    }()
    private static let registrationLock = NSLock()
    private static var didRegisterBackgroundFlush = false
    private static var didTrimOnLaunch = false
    // 内存环形缓存：日志只写内存，不实时写 UserDefaults
    private static var memoryBuffer: [String] = []
    private static var memoryBufferBytes = 0
    private static let directory =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GlobalRefreshDiagnostics", isDirectory: true)
    private static let recentRuntimeLogs = RecentRuntimeLogStore(directory: directory)
    private static let detailedArchive = DetailedDebugLogArchive(directory: directory)

    static var isDebugModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: debugModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: debugModeKey) }
    }

    // 启动时清理旧积压数据，并加载历史日志到内存
    static func trimOnLaunch() {
        registrationLock.lock()
        guard !didTrimOnLaunch else {
            registrationLock.unlock()
            return
        }
        didTrimOnLaunch = true
        registrationLock.unlock()
        logQueue.async {
            let archived = detailedArchive.load()
            let legacy = UserDefaults.standard.stringArray(forKey: legacyStorageKey)
            let stored = archived ?? legacy ?? []
            memoryBuffer = stored.suffix(maximumEntries).map(limitEntry) + memoryBuffer
            memoryBufferBytes = memoryBuffer.reduce(into: 0) { $0 += $1.utf8.count }
            trimMemoryBuffer()
            if archived == nil, legacy != nil {
                detailedArchive.markChanged()
                do {
                    try detailedArchive.save(memoryBuffer, at: ProcessInfo.processInfo.systemUptime, force: true)
                    UserDefaults.standard.removeObject(forKey: legacyStorageKey)
                } catch {
                    logger.error("Could not migrate detailed debug log archive")
                }
            } else if archived != nil, legacy != nil {
                UserDefaults.standard.removeObject(forKey: legacyStorageKey)
            }
            if !isDebugModeEnabled {
                memoryBuffer.removeAll(keepingCapacity: false)
                memoryBufferBytes = 0
            }
        }
    }

    // 注册后台/终止时落盘，在 viewDidLoad 调用一次即可
    static func registerBackgroundFlush() {
        registrationLock.lock()
        guard !didRegisterBackgroundFlush else {
            registrationLock.unlock()
            return
        }
        didRegisterBackgroundFlush = true
        registrationLock.unlock()
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
            flush()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            flush(force: true)
        }
    }

    // 只写内存，不碰 UserDefaults
    static func log(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        append(message, recordRecent: false, file: file, line: line)
    }

    static func logRuntime(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        append(message, recordRecent: true, file: file, line: line)
    }

    // 生命周期、内存警告和保活切换使用此入口，避免系统直接终止时最后状态只留在内存。
    static func logCritical(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        append(message, recordRecent: true, file: file, line: line)
    }

    private static func append(
        _ message: String,
        recordRecent: Bool,
        file: StaticString,
        line: UInt
    ) {
        let debugEnabled = isDebugModeEnabled
        guard debugEnabled || recordRecent else { return }
        let limitedMessage = limitEntry(message)
        if debugEnabled {
            DiagnosticsRuntimeState.updateLastEvent(limitedMessage)
            logger.info("\(limitedMessage, privacy: .private)")
        }
        let device = UIDevice.current
        let entry = limitEntry([
            beijingFormatter.string(from: Date()),
            "iOS \(device.systemVersion)",
            deviceModelIdentifier,
            "\(file):\(line)",
            limitedMessage
        ].joined(separator: " | "))

        if recordRecent {
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
            let build = info?["CFBundleVersion"] as? String ?? "unknown"
            recentRuntimeLogs.append("\(version)(\(build)) | \(entry)")
        }
        guard debugEnabled else { return }
        logQueue.async {
            guard isDebugModeEnabled else { return }
            memoryBuffer.append(entry)
            memoryBufferBytes += entry.utf8.count
            trimMemoryBuffer()
            detailedArchive.markChanged()
        }
    }

    // Export reads the in-memory buffer directly; only lifecycle events archive it.
    static func flush(force: Bool = false) {
        recentRuntimeLogs.flush()
        logQueue.async {
            guard isDebugModeEnabled, !memoryBuffer.isEmpty else { return }
            do {
                try detailedArchive.save(memoryBuffer, at: ProcessInfo.processInfo.systemUptime, force: force)
            } catch {
                logger.error("Could not checkpoint detailed debug logs")
            }
        }
    }

    static func exportText(newestFirst: Bool = false) -> String {
        var entries: [String] = []
        logQueue.sync { entries = memoryBuffer }
        if newestFirst { entries.reverse() }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let device = UIDevice.current
        let diagnosticsSection = DebugDiagnosticsMonitor.isEnabled
            ? """
        线程与性能日志记录：开启
        当前现场：\(DiagnosticsRuntimeState.snapshotText())
        实时性能：\(PerformanceDiagnosticsLogger.currentSnapshotText())
        """
            : ""

        return """
        全局高刷调试日志
        App版本：\(version) (\(build))
        Bundle ID：\(bundleID)
        系统版本：iOS \(device.systemVersion)
        设备型号：\(deviceModelIdentifier)
        生成时间：\(beijingFormatter.string(from: Date())) 北京时间
        当前保活模式：\(KeepAliveModeText.current)
        调试模式：\(isDebugModeEnabled ? "开启（详细记录）" : "关闭（仅轻量关键事件与低频采样）")

        \(recentRuntimeLogs.exportText(newestFirst: newestFirst))

        详细调试日志（\(newestFirst ? "最新在前" : "按时间顺序")，最多\(maximumEntries)条 / \(maximumBufferBytes / 1_000_000)MB）：
        \(entries.isEmpty ? "暂无日志" : entries.joined(separator: "\n"))

        \(diagnosticsSection)
        \(ProcessTerminationDiagnostics.exportText())
        """
    }

    static func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
    }

    static func resetLogs(includingRecentRuntime: Bool = false) {
        let clearBuffer = {
            memoryBuffer.removeAll(keepingCapacity: false)
            memoryBufferBytes = 0
            detailedArchive.reset()
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        }
        if DispatchQueue.getSpecific(key: logQueueKey) != nil {
            clearBuffer()
        } else {
            logQueue.sync(execute: clearBuffer)
        }
        if includingRecentRuntime { recentRuntimeLogs.reset() }
        DiagnosticsRuntimeState.reset()
        ProcessTerminationDiagnostics.reset()
    }

    static func trimForMemoryPressure() {
        logQueue.async {
            let retained = memoryBuffer.suffix(100)
            memoryBuffer = Array(retained)
            memoryBufferBytes = memoryBuffer.reduce(into: 0) { $0 += $1.utf8.count }
            if isDebugModeEnabled { detailedArchive.markChanged() }
        }
    }

    private static func limitEntry(_ text: String) -> String {
        guard text.utf8.count > maximumEntryBytes else { return text }
        let marker = "\n[日志过长，已截断]"
        let prefixByteCount = max(0, maximumEntryBytes - marker.utf8.count)
        return String(decoding: text.utf8.prefix(prefixByteCount), as: UTF8.self) + marker
    }

    private static func trimMemoryBuffer() {
        while memoryBuffer.count > maximumEntries || memoryBufferBytes > maximumBufferBytes {
            guard !memoryBuffer.isEmpty else {
                memoryBufferBytes = 0
                return
            }
            memoryBufferBytes -= memoryBuffer.removeFirst().utf8.count
        }
    }

    private static let beijingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static let deviceModelIdentifier: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(String(UnicodeScalar(UInt8(value))))
        }
    }()
}

private struct LightweightRuntimeSample: Codable {
    let timestamp: TimeInterval
    let reason: String
    let physicalFootprintMB: Double
    let threadCount: Int
    let appState: String
    let pipActive: Bool?
    let engineRoute: String?
    let keepAlivePolicy: String
    let height: Double?
    let audioPlaying: Bool
    let lowPowerModeEnabled: Bool
    let thermalState: Int
    let appVersion: String
    let buildNumber: String
}

enum LightweightRuntimeDiagnostics {
    private static let storageKey = "pip.lightweightRuntime.samples.beta2"
    private static let lastPeriodicSampleKey = "pip.lightweightRuntime.lastPeriodicSample.beta2"
    private static let minimumPeriodicInterval: TimeInterval = 10 * 60
    private static let maximumSamples = 320
    private static let queue = DispatchQueue(label: "com.yoroin.globalrefresh.lightweight-runtime", qos: .utility)
    private static let observerLock = NSLock()
    private static var observerTokens: [NSObjectProtocol] = []

    static func start() {
        installObserversIfNeeded()
        record(reason: "App启动", force: true)
    }

    static func recordPiPCheckpoint(
        reason: String,
        isActive: Bool,
        engineRoute: String,
        keepAlivePolicy: String,
        height: CGFloat,
        audioPlaying: Bool,
        force: Bool = false
    ) {
        record(
            reason: reason,
            force: force,
            pipActive: isActive,
            engineRoute: engineRoute,
            keepAlivePolicy: keepAlivePolicy,
            height: Double(height),
            audioPlaying: audioPlaying
        )
    }

    static func exportText(newestFirst: Bool = false) -> String {
        var samples = loadSamplesSynchronously()
        if newestFirst { samples.reverse() }
        guard !samples.isEmpty else {
            return "轻量常驻内存记录（调试模式关闭时仍记录）\n暂无记录"
        }

        let lines = samples.map { sample in
            let date = Date(timeIntervalSince1970: sample.timestamp)
            let pipText = sample.pipActive.map { $0 ? "active" : "inactive" } ?? "unknown"
            let routeText = sample.engineRoute ?? "unknown"
            let heightText = sample.height.map { String(format: "%.1fpt", $0) } ?? "unknown"
            return String(
                format: "%@ | %@ | footprint=%.1fMB | threads=%d | App=%@ | PiP=%@ | route=%@ | policy=%@ | height=%@ | audio=%@ | lowPower=%@ | thermal=%d | version=%@(%@)",
                formatter.string(from: date),
                sample.reason,
                sample.physicalFootprintMB,
                sample.threadCount,
                sample.appState,
                pipText,
                routeText,
                sample.keepAlivePolicy,
                heightText,
                sample.audioPlaying ? "on" : "off",
                sample.lowPowerModeEnabled ? "on" : "off",
                sample.thermalState,
                sample.appVersion,
                sample.buildNumber
            )
        }

        return """
        轻量常驻内存记录（调试模式关闭时仍记录）
        采样规则：PiP运行期间每10分钟一次，并记录启动、前后台切换和内存警告；最多保留320条。
        排列顺序：\(newestFirst ? "最新在前" : "按时间顺序")。
        注意：记录物理占用趋势，不等同于系统确认的Jetsam原因。

        \(lines.joined(separator: "\n"))
        """
    }

    static func reset() {
        queue.sync {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: storageKey)
            defaults.removeObject(forKey: lastPeriodicSampleKey)
        }
    }

    private static func record(
        reason: String,
        force: Bool,
        pipActive: Bool? = nil,
        engineRoute: String? = nil,
        keepAlivePolicy: String = KeepAlivePolicy.current.rawValue,
        height: Double? = nil,
        audioPlaying: Bool = false
    ) {
        let now = Date()
        let appState = applicationStateText(UIApplication.shared.applicationState)
        let lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermalState = ProcessInfo.processInfo.thermalState.rawValue
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        queue.async {
            let defaults = UserDefaults.standard
            let previous = defaults.double(forKey: lastPeriodicSampleKey)
            guard force || previous <= 0 || now.timeIntervalSince1970 - previous >= minimumPeriodicInterval else {
                return
            }

            let process = PerformanceDiagnosticsLogger.lightweightProcessSnapshot()
            let sample = LightweightRuntimeSample(
                timestamp: now.timeIntervalSince1970,
                reason: String(reason.prefix(80)),
                physicalFootprintMB: (process.physicalFootprintMB * 10).rounded() / 10,
                threadCount: process.threadCount,
                appState: appState,
                pipActive: pipActive,
                engineRoute: engineRoute,
                keepAlivePolicy: keepAlivePolicy,
                height: height,
                audioPlaying: audioPlaying,
                lowPowerModeEnabled: lowPowerModeEnabled,
                thermalState: thermalState,
                appVersion: version,
                buildNumber: build
            )
            var samples = loadSamples(defaults: defaults)
            samples.append(sample)
            if samples.count > maximumSamples {
                samples.removeFirst(samples.count - maximumSamples)
            }
            if let data = try? JSONEncoder().encode(samples) {
                defaults.set(data, forKey: storageKey)
                defaults.set(now.timeIntervalSince1970, forKey: lastPeriodicSampleKey)
            }
        }
    }

    private static func installObserversIfNeeded() {
        observerLock.lock()
        let alreadyInstalled = !observerTokens.isEmpty
        observerLock.unlock()
        guard !alreadyInstalled else { return }

        let center = NotificationCenter.default
        let tokens = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                record(reason: "App进入后台", force: true)
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                record(reason: "App即将回前台", force: true)
            },
            center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
                AppDebugLogger.logRuntime("收到内存警告；仅记录回调，不认定系统终止原因")
                record(reason: "收到内存警告", force: true)
                AppDebugLogger.trimForMemoryPressure()
                BackgroundTaskManager.shared.releasePreparedAudioIfInactive()
                URLCache.shared.removeAllCachedResponses()
            }
        ]

        observerLock.lock()
        if observerTokens.isEmpty {
            observerTokens = tokens
        } else {
            tokens.forEach(center.removeObserver)
        }
        observerLock.unlock()
    }

    private static func loadSamplesSynchronously() -> [LightweightRuntimeSample] {
        queue.sync { loadSamples(defaults: .standard) }
    }

    private static func loadSamples(defaults: UserDefaults) -> [LightweightRuntimeSample] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([LightweightRuntimeSample].self, from: data)) ?? []
    }

    private static func applicationStateText(_ state: UIApplication.State) -> String {
        switch state {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

enum DiagnosticsRuntimeState {
    private static let lock = NSLock()
    private static var observerTokens: [NSObjectProtocol] = []
    private static var appState = "未记录"
    private static var currentPage = "未记录"
    private static var pipState = "未记录"
    private static var displaySleepState = "未记录"
    private static var pipSurfaceState = "未记录"
    private static var lastUserAction = "无"
    private static var lastEvent = "无"

    static func startAppStateTracking() {
        lock.lock()
        let hasStarted = !observerTokens.isEmpty
        lock.unlock()
        guard !hasStarted else { return }

        updateAppState("启动")
        let center = NotificationCenter.default
        let tokens = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
                updateAppState("前台活跃")
            },
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { _ in
                updateAppState("即将非活跃")
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
                updateAppState("后台")
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { _ in
                updateAppState("即将回前台")
            },
            center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { _ in
                updateAppState("即将终止")
            }
        ]

        lock.lock()
        if observerTokens.isEmpty {
            observerTokens = tokens
        } else {
            tokens.forEach { center.removeObserver($0) }
        }
        lock.unlock()
    }

    static func stopAppStateTracking() {
        lock.lock()
        let tokens = observerTokens
        observerTokens.removeAll()
        lock.unlock()

        let center = NotificationCenter.default
        tokens.forEach { center.removeObserver($0) }
    }

    static func reset() {
        lock.lock()
        appState = "未记录"
        currentPage = "未记录"
        pipState = "未记录"
        displaySleepState = "未记录"
        pipSurfaceState = "未记录"
        lastUserAction = "无"
        lastEvent = "无"
        lock.unlock()
    }

    static func refreshAppState() {
        switch UIApplication.shared.applicationState {
        case .active:
            updateAppState("前台活跃")
        case .inactive:
            updateAppState("非活跃")
        case .background:
            updateAppState("后台")
        @unknown default:
            updateAppState("未知")
        }
    }

    static func updateAppState(_ state: String) {
        update { appState = state }
    }

    static func updateCurrentPage(_ page: String) {
        update { currentPage = page }
    }

    static func updatePiPState(_ state: String) {
        update { pipState = state }
    }

    static func updateDisplaySleepState(_ state: String) {
        update { displaySleepState = state }
    }

    static func updatePiPSurfaceState(_ state: String) {
        update { pipSurfaceState = state }
    }

    static func recordUserAction(_ action: String) {
        update { lastUserAction = action }
        AppDebugLogger.logRuntime("用户操作：\(action)")
    }

    static func updateLastEvent(_ event: String) {
        update { lastEvent = event }
    }

    static func snapshotText(includeAudio: Bool = true) -> String {
        let base: String = lockedValue {
            "App=\(appState), 页面=\(currentPage), 悬浮窗=\(pipState), 悬浮窗显示层=\(pipSurfaceState), 熄屏=\(displaySleepState), 最后操作=\(lastUserAction), 最后事件=\(lastEvent)"
        }
        guard includeAudio else { return base }
        return "\(base), 音频=\(audioSessionSnapshotText)"
    }

    static var isForegroundActive: Bool {
        lock.lock()
        let value = appState == "前台活跃"
        lock.unlock()
        return value
    }

    private static func update(_ block: () -> Void) {
        lock.lock()
        block()
        lock.unlock()
    }

    private static func lockedValue(_ block: () -> String) -> String {
        lock.lock()
        let value = block()
        lock.unlock()
        return value
    }

    private static var audioSessionSnapshotText: String {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
            .map { output in
                "\(output.portType.rawValue):\(output.portName)"
            }
            .joined(separator: ",")
        let routeText = outputs.isEmpty ? "无输出" : outputs
        return String(
            format: "category=%@, mode=%@, route=%@, volume=%.2f, otherAudio=%@",
            session.category.rawValue,
            session.mode.rawValue,
            routeText,
            session.outputVolume,
            session.isOtherAudioPlaying ? "是" : "否"
        )
    }
}

enum MainThreadWatchdog {
    private static let enabledKey = "pip.debug.mainThreadWatchdogEnabled"
    private static let queue = DispatchQueue(label: "pip.debug.main-thread-watchdog")
    private static let pingInterval: TimeInterval = 0.5
    private static let threshold: TimeInterval = 1.2
    private static let reportInterval: TimeInterval = 3

    private static var timer: DispatchSourceTimer?
    private static var lastBeat = Date()
    private static var lastReport = Date.distantPast
    private static var isHanging = false
    private static var currentHangIsForeground = true
    private static var hasPendingPing = false

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        isEnabled ? startIfNeeded() : stop()
        AppDebugLogger.log("Main thread watchdog \(isEnabled ? "enabled" : "disabled")")
    }

    static func startIfNeeded() {
        guard isEnabled else { return }
        DiagnosticsRuntimeState.startAppStateTracking()
        DiagnosticsRuntimeState.refreshAppState()
        queue.async {
            guard timer == nil else { return }
            lastBeat = Date()
            lastReport = .distantPast
            isHanging = false
            hasPendingPing = false

            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
            source.setEventHandler {
                let now = Date()
                let gap = now.timeIntervalSince(lastBeat)
                if gap > threshold {
                    let isForegroundActive = DiagnosticsRuntimeState.isForegroundActive
                    if !isHanging {
                        isHanging = true
                        currentHangIsForeground = isForegroundActive
                        lastReport = now
                        AppDebugLogger.log(
                            String(
                                format: "%@：%.2f秒未响应 | %@ | %@",
                                isForegroundActive ? "主线程卡顿开始" : "后台主线程挂起记录",
                                gap,
                                PerformanceDiagnosticsLogger.currentSnapshotText(),
                                DiagnosticsRuntimeState.snapshotText()
                            )
                        )
                    } else if now.timeIntervalSince(lastReport) > reportInterval {
                        lastReport = now
                        AppDebugLogger.log(
                            String(
                                format: "%@：%.2f秒未响应 | %@",
                                currentHangIsForeground ? "主线程卡顿持续" : "后台主线程仍处于挂起状态",
                                gap,
                                DiagnosticsRuntimeState.snapshotText()
                            )
                        )
                    }
                }

                guard !hasPendingPing else { return }
                hasPendingPing = true
                DispatchQueue.main.async {
                    let acknowledgedAt = Date()
                    queue.async {
                        let blockedDuration = acknowledgedAt.timeIntervalSince(lastBeat)
                        let shouldLogRecovery = isHanging
                        lastBeat = acknowledgedAt
                        hasPendingPing = false
                        if shouldLogRecovery {
                            isHanging = false
                            AppDebugLogger.log(
                                String(
                                    format: "%@：持续约%.2f秒 | %@",
                                    currentHangIsForeground ? "主线程卡顿恢复" : "后台主线程挂起恢复",
                                    blockedDuration,
                                    DiagnosticsRuntimeState.snapshotText()
                                )
                            )
                        }
                    }
                }
            }
            timer = source
            source.resume()
            AppDebugLogger.log("Main thread watchdog started")
        }
    }

    static func stop() {
        queue.async {
            timer?.cancel()
            timer = nil
            isHanging = false
            currentHangIsForeground = true
            hasPendingPing = false
        }
    }
}

enum FrameStutterMonitor {
    private static let enabledKey = "pip.debug.frameStutterEnabled"
    private static let threshold: CFTimeInterval = 0.18
    private static let reportInterval: TimeInterval = 3
    private static var displayLink: CADisplayLink?
    private static var lastTimestamp: CFTimeInterval = 0
    private static var lastReport = Date.distantPast

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        isEnabled ? startIfNeeded() : stop()
        AppDebugLogger.log("Frame stutter monitor \(isEnabled ? "enabled" : "disabled")")
    }

    static func startIfNeeded() {
        guard isEnabled else { return }
        DiagnosticsRuntimeState.startAppStateTracking()
        DiagnosticsRuntimeState.refreshAppState()
        DispatchQueue.main.async {
            guard displayLink == nil else { return }
            lastTimestamp = 0
            lastReport = .distantPast

            let link = CADisplayLink(target: FrameStutterTarget.shared, selector: #selector(FrameStutterTarget.step(_:)))
            // BETA2 ANCHOR: 调试帧监控避开 tracking mode，避免监控本身影响滑动手感。
            link.add(to: .main, forMode: .default)
            displayLink = link
            AppDebugLogger.log("Frame stutter monitor started")
        }
    }

    static func stop() {
        DispatchQueue.main.async {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = 0
        }
    }

    fileprivate static func handleStep(_ displayLink: CADisplayLink) {
        guard lastTimestamp > 0 else {
            lastTimestamp = displayLink.timestamp
            return
        }

        let interval = displayLink.timestamp - lastTimestamp
        lastTimestamp = displayLink.timestamp

        guard interval > threshold else { return }
        let now = Date()
        guard now.timeIntervalSince(lastReport) > reportInterval else { return }
        lastReport = now

        let expectedFrame = displayLink.targetTimestamp - displayLink.timestamp
        let label = DiagnosticsRuntimeState.isForegroundActive ? "UI帧间隔异常" : "后台UI帧间隔记录"
        AppDebugLogger.log(
            String(
                format: "%@：%.0fms，预期帧间隔约%.1fms | %@ | %@",
                label,
                interval * 1000,
                max(expectedFrame, 0) * 1000,
                PerformanceDiagnosticsLogger.currentSnapshotText(),
                DiagnosticsRuntimeState.snapshotText()
            )
        )
    }
}

private final class FrameStutterTarget: NSObject {
    static let shared = FrameStutterTarget()

    @objc func step(_ displayLink: CADisplayLink) {
        FrameStutterMonitor.handleStep(displayLink)
    }
}

struct LightweightProcessSnapshot {
    let physicalFootprintMB: Double
    let threadCount: Int
}

enum PerformanceDiagnosticsLogger {
    private static let enabledKey = "pip.debug.performanceDiagnosticsEnabled"
    private static let queue = DispatchQueue(label: "pip.debug.performance-diagnostics")
    private static var timer: DispatchSourceTimer?
    private static var isRuntimeSamplingSuppressed = false

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        isEnabled ? startIfNeeded() : stop()
        AppDebugLogger.log("Performance diagnostics \(isEnabled ? "enabled" : "disabled")")
    }

    static func startIfNeeded() {
        guard isEnabled else { return }
        DiagnosticsRuntimeState.startAppStateTracking()
        DiagnosticsRuntimeState.refreshAppState()
        queue.async {
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 2, repeating: 60, leeway: .seconds(3))
            source.setEventHandler {
                guard !isRuntimeSamplingSuppressed else { return }
                let snapshot = makeSnapshot()
                AppDebugLogger.log(snapshot)
                DispatchQueue.main.async {
                    let runtime = DiagnosticsRuntimeState.snapshotText(includeAudio: false)
                    ProcessTerminationDiagnostics.recordCheckpoint(
                        reason: "60秒性能心跳",
                        pipSnapshot: "\(runtime), 性能{\(snapshot)}"
                    )
                }
            }
            timer = source
            source.resume()
            AppDebugLogger.log("Performance diagnostics started")
        }
    }

    static func stop() {
        queue.async {
            timer?.cancel()
            timer = nil
            isRuntimeSamplingSuppressed = false
        }
    }

    static func setRuntimeSamplingSuppressed(_ isSuppressed: Bool, reason: String) {
        queue.async {
            guard isRuntimeSamplingSuppressed != isSuppressed else { return }
            isRuntimeSamplingSuppressed = isSuppressed
            AppDebugLogger.log(
                "Performance diagnostics runtime sampling \(isSuppressed ? "suppressed" : "resumed"): \(reason)"
            )
        }
    }

    static func currentSnapshotText() -> String {
        makeSnapshot()
    }

    static func lightweightProcessSnapshot() -> LightweightProcessSnapshot {
        let threadSnapshot = threadUsageSnapshot(countOnly: true)
        return LightweightProcessSnapshot(
            physicalFootprintMB: physicalFootprintMB(),
            threadCount: threadSnapshot.threadCount
        )
    }

    private static func makeSnapshot() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel >= 0
            ? "\(Int(UIDevice.current.batteryLevel * 100))%"
            : "未知"
        let processSnapshot = makeProcessSnapshot()
        return String(
            format: "性能采样：CPU=%.1f%%, 最高线程=%.1f%%, 内存=%.1fMB, 物理占用=%.1fMB, 线程=%d(运行=%d,等待=%d,停止=%d,不可中断=%d,挂起=%d), 热状态=%@, 电量=%@, 充电=%@",
            processSnapshot.cpuUsage,
            processSnapshot.maxThreadCPUUsage,
            processSnapshot.residentMemoryMB,
            processSnapshot.physicalFootprintMB,
            processSnapshot.threadCount,
            processSnapshot.runningThreadCount,
            processSnapshot.waitingThreadCount,
            processSnapshot.stoppedThreadCount,
            processSnapshot.uninterruptibleThreadCount,
            processSnapshot.haltedThreadCount,
            thermalStateText,
            batteryLevel,
            batteryStateText
        )
    }

    private static var thermalStateText: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return "正常"
        case .fair:
            return "轻微升温"
        case .serious:
            return "明显升温"
        case .critical:
            return "严重"
        @unknown default:
            return "未知"
        }
    }

    private static var batteryStateText: String {
        switch UIDevice.current.batteryState {
        case .unknown:
            return "未知"
        case .unplugged:
            return "未充电"
        case .charging:
            return "充电中"
        case .full:
            return "已充满"
        @unknown default:
            return "未知"
        }
    }

    private struct ProcessSnapshot {
        let cpuUsage: Double
        let maxThreadCPUUsage: Double
        let residentMemoryMB: Double
        let physicalFootprintMB: Double
        let threadCount: Int
        let runningThreadCount: Int
        let waitingThreadCount: Int
        let stoppedThreadCount: Int
        let uninterruptibleThreadCount: Int
        let haltedThreadCount: Int
    }

    private static func makeProcessSnapshot() -> ProcessSnapshot {
        let threadSnapshot = threadUsageSnapshot()
        return ProcessSnapshot(
            cpuUsage: threadSnapshot.totalCPUUsage,
            maxThreadCPUUsage: threadSnapshot.maxThreadCPUUsage,
            residentMemoryMB: residentMemoryMB(),
            physicalFootprintMB: physicalFootprintMB(),
            threadCount: threadSnapshot.threadCount,
            runningThreadCount: threadSnapshot.runningThreadCount,
            waitingThreadCount: threadSnapshot.waitingThreadCount,
            stoppedThreadCount: threadSnapshot.stoppedThreadCount,
            uninterruptibleThreadCount: threadSnapshot.uninterruptibleThreadCount,
            haltedThreadCount: threadSnapshot.haltedThreadCount
        )
    }

    private static func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1024.0 / 1024.0
    }

    private static func physicalFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1024.0 / 1024.0
    }

    private struct ThreadUsageSnapshot {
        let totalCPUUsage: Double
        let maxThreadCPUUsage: Double
        let threadCount: Int
        let runningThreadCount: Int
        let waitingThreadCount: Int
        let stoppedThreadCount: Int
        let uninterruptibleThreadCount: Int
        let haltedThreadCount: Int
    }

    private static func threadUsageSnapshot(countOnly: Bool = false) -> ThreadUsageSnapshot {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threadList else {
            return ThreadUsageSnapshot(
                totalCPUUsage: 0,
                maxThreadCPUUsage: 0,
                threadCount: 0,
                runningThreadCount: 0,
                waitingThreadCount: 0,
                stoppedThreadCount: 0,
                uninterruptibleThreadCount: 0,
                haltedThreadCount: 0
            )
        }

        defer {
            // task_threads returns owned port rights as well as the array storage.
            for index in 0..<Int(threadCount) {
                mach_port_deallocate(mach_task_self_, threadList[index])
            }
            let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), size)
        }

        var totalUsage: Double = 0
        var maxUsage: Double = 0
        var runningCount = 0
        var waitingCount = 0
        var stoppedCount = 0
        var uninterruptibleCount = 0
        var haltedCount = 0

        for index in 0..<(countOnly ? 0 : Int(threadCount)) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let infoResult = withUnsafeMutablePointer(to: &threadInfo) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                    thread_info(threadList[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }

            if infoResult == KERN_SUCCESS, (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                let usage = Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                totalUsage += usage
                maxUsage = max(maxUsage, usage)

                switch Int32(threadInfo.run_state) {
                case TH_STATE_RUNNING:
                    runningCount += 1
                case TH_STATE_WAITING:
                    waitingCount += 1
                case TH_STATE_STOPPED:
                    stoppedCount += 1
                case TH_STATE_UNINTERRUPTIBLE:
                    uninterruptibleCount += 1
                case TH_STATE_HALTED:
                    haltedCount += 1
                default:
                    break
                }
            }
        }

        return ThreadUsageSnapshot(
            totalCPUUsage: totalUsage,
            maxThreadCPUUsage: maxUsage,
            threadCount: Int(threadCount),
            runningThreadCount: runningCount,
            waitingThreadCount: waitingCount,
            stoppedThreadCount: stoppedCount,
            uninterruptibleThreadCount: uninterruptibleCount,
            haltedThreadCount: haltedCount
        )
    }
}

enum DebugDiagnosticsMonitor {
    static var isEnabled: Bool {
        MainThreadWatchdog.isEnabled || PerformanceDiagnosticsLogger.isEnabled || FrameStutterMonitor.isEnabled
    }

    static func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            DiagnosticsRuntimeState.startAppStateTracking()
            DiagnosticsRuntimeState.refreshAppState()
        }
        MainThreadWatchdog.setEnabled(isEnabled)
        FrameStutterMonitor.setEnabled(isEnabled)
        PerformanceDiagnosticsLogger.setEnabled(isEnabled)
        if !isEnabled {
            DiagnosticsRuntimeState.stopAppStateTracking()
        }
    }

    static func startIfNeeded() {
        MainThreadWatchdog.startIfNeeded()
        FrameStutterMonitor.startIfNeeded()
        PerformanceDiagnosticsLogger.startIfNeeded()
    }

    static func stop() {
        MainThreadWatchdog.stop()
        FrameStutterMonitor.stop()
        PerformanceDiagnosticsLogger.stop()
    }
}
struct ProcessTerminationEvidenceSnapshot: Codable, Equatable {
    let capturedAt: Date
    let lastCheckpointAt: Date?
    let memoryWarningCount: Int
    let lastMemoryWarningAt: Date?
    let checkpointText: String
    let inferenceText: String
    let systemRestartDetected: Bool
    let metricKitStatus: String?
}

enum ProcessTerminationDiagnostics {
    private static let prefix = "pip.debug.processExit."
    private static let runActiveKey = prefix + "runActive"
    private static let launchKey = prefix + "launch"
    private static let legacyBootKey = prefix + "boot"
    private static let lastUptimeKey = prefix + "lastUptime"
    private static let lastCheckpointKey = prefix + "lastCheckpoint"
    private static let lastCheckpointDateKey = prefix + "lastCheckpointDate"
    private static let memoryWarningCountKey = prefix + "memoryWarningCount"
    private static let lastMemoryWarningKey = prefix + "lastMemoryWarning"
    private static let previousRunSummaryKey = prefix + "previousRunSummary"
    private static let previousRunEvidenceKey = prefix + "previousRunEvidence.v1"
    private static let observerLock = NSLock()
    private static var observerTokens: [NSObjectProtocol] = []

    static func prepareForLaunch() {
        guard AppDebugLogger.isDebugModeEnabled else { return }

        let defaults = UserDefaults.standard
        let previousRunWasActive = defaults.bool(forKey: runActiveKey)
        let previousLaunch = defaults.double(forKey: launchKey)
        let previousUptime = defaults.double(forKey: lastUptimeKey)
        let previousCheckpoint = defaults.string(forKey: lastCheckpointKey) ?? "无"
        let previousCheckpointDate = defaults.double(forKey: lastCheckpointDateKey)
        let previousMemoryWarnings = defaults.integer(forKey: memoryWarningCountKey)
        let previousLastMemoryWarning = defaults.double(forKey: lastMemoryWarningKey)
        let currentUptime = ProcessInfo.processInfo.systemUptime

        var launchEvidenceSummary: String?
        if previousRunWasActive {
            // A reboot resets monotonic uptime. Deriving a boot date from wall-clock time
            // drifts during deep sleep on some iOS versions and causes false reboot reports.
            let bootChanged = previousUptime > 0 && currentUptime + 90 < previousUptime
            let warningWasRecent = previousLastMemoryWarning > 0
                && previousCheckpointDate > 0
                && previousCheckpointDate - previousLastMemoryWarning < 30 * 60
            let inference: String
            if bootChanged {
                inference = "设备在两次运行之间重启或更新系统，无法判定为单纯杀后台"
            } else if warningWasRecent || previousMemoryWarnings > 0 {
                inference = "终止前出现过内存警告，可能与内存压力/Jetsam有关；需结合MetricKit确认"
            } else if previousCheckpoint.contains("低电量=是") && previousCheckpoint.contains("PiP") {
                inference = "低电量模式下的后台媒体资格不足、系统夜间整理或Jetsam均有可能；普通App无法获得精确终止回调"
            } else {
                inference = "可能为系统后台策略、Jetsam、用户强退或其他未回调终止；需结合MetricKit确认"
            }
            let previousLaunchText = dateText(previousLaunch)
            let checkpointText = dateText(previousCheckpointDate)
            let summary = "上次进程未记录正常终止 | 启动=\(previousLaunchText) | 最后现场=\(checkpointText) | 内存警告=\(previousMemoryWarnings)次 | 推断=\(inference) | 现场{\(previousCheckpoint)}"
            defaults.set(summary, forKey: previousRunSummaryKey)
            launchEvidenceSummary = summary
            let evidence = ProcessTerminationEvidenceSnapshot(
                capturedAt: Date(),
                lastCheckpointAt: previousCheckpointDate > 0 ? Date(timeIntervalSince1970: previousCheckpointDate) : nil,
                memoryWarningCount: previousMemoryWarnings,
                lastMemoryWarningAt: previousLastMemoryWarning > 0 ? Date(timeIntervalSince1970: previousLastMemoryWarning) : nil,
                checkpointText: previousCheckpoint,
                inferenceText: inference,
                systemRestartDetected: bootChanged,
                metricKitStatus: defaults.string(forKey: "pip.metricKit.beta5HistoryStatus")
            )
            if let data = try? JSONEncoder().encode(evidence) {
                defaults.set(data, forKey: previousRunEvidenceKey)
            }
        }

        defaults.set(true, forKey: runActiveKey)
        defaults.set(Date().timeIntervalSince1970, forKey: launchKey)
        defaults.set(0, forKey: memoryWarningCountKey)
        defaults.removeObject(forKey: lastMemoryWarningKey)
        installObserversIfNeeded()
        recordCheckpoint(reason: "进程启动")
        AppDebugLogger.logCritical("进程终止诊断已启动；\(launchEvidenceSummary ?? "本次启动没有新的异常终止证据，已有历史记录保留")")
    }

    static func markBuildTransition(from previousBuild: String, to currentBuild: String) {
        let defaults = UserDefaults.standard
        let lastCheckpoint = dateText(defaults.double(forKey: lastCheckpointDateKey))
        let lastRunMarkedActive = defaults.bool(forKey: runActiveKey)
        defaults.set(false, forKey: runActiveKey)
        AppDebugLogger.logRuntime("构建变更 \(previousBuild) → \(currentBuild)；旧进程活跃标记=\(lastRunMarkedActive)，旧现场时间=\(lastCheckpoint)。覆盖安装不计为新的后台异常，已记录的诊断保留。")
    }

    static func recordCheckpoint(reason: String, pipSnapshot: String? = nil) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        storeCheckpoint(runtimeSnapshot(reason: reason, pipSnapshot: pipSnapshot))
    }

    private static func storeCheckpoint(_ snapshot: String) {
        let defaults = UserDefaults.standard
        defaults.set(snapshot, forKey: lastCheckpointKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastCheckpointDateKey)
        defaults.set(ProcessInfo.processInfo.systemUptime, forKey: lastUptimeKey)
    }

    static func recordMemoryWarning() {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: memoryWarningCountKey) + 1
        defaults.set(count, forKey: memoryWarningCountKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastMemoryWarningKey)
        recordCheckpoint(reason: "收到内存警告#\(count)")
        AppDebugLogger.logCritical("收到系统内存警告#\(count) | \(PerformanceDiagnosticsLogger.currentSnapshotText())")
    }

    static func markGracefulTermination(reason: String) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        recordCheckpoint(reason: reason)
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: runActiveKey)
        AppDebugLogger.logCritical("进程记录正常结束：\(reason)")
    }

    static func exportText() -> String {
        let defaults = UserDefaults.standard
        return """
        进程终止推断：
        最近一次异常终止推断（可能来自旧构建）：\(defaults.string(forKey: previousRunSummaryKey) ?? "无异常终止记录")
        本次启动：\(dateText(defaults.double(forKey: launchKey)))
        本次内存警告：\(defaults.integer(forKey: memoryWarningCountKey)) 次
        最后诊断现场：\(defaults.string(forKey: lastCheckpointKey) ?? "无")
        说明：iOS 不向普通App提供Jetsam瞬间回调；这里是根据最后持久化现场、设备重启、内存警告及MetricKit作出的推断，不等同于系统精确杀进程原因。
        """
    }

    static func previousRunEvidenceSnapshot() -> ProcessTerminationEvidenceSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: previousRunEvidenceKey) else { return nil }
        return try? JSONDecoder().decode(ProcessTerminationEvidenceSnapshot.self, from: data)
    }

    static func reset() {
        observerLock.lock()
        let tokens = observerTokens
        observerTokens.removeAll(keepingCapacity: false)
        observerLock.unlock()
        tokens.forEach(NotificationCenter.default.removeObserver)

        let defaults = UserDefaults.standard
        [
            runActiveKey,
            launchKey,
            legacyBootKey,
            lastUptimeKey,
            lastCheckpointKey,
            lastCheckpointDateKey,
            memoryWarningCountKey,
            lastMemoryWarningKey,
            previousRunSummaryKey,
            previousRunEvidenceKey
        ].forEach(defaults.removeObject(forKey:))
    }

    private static func installObserversIfNeeded() {
        observerLock.lock()
        let hasObservers = !observerTokens.isEmpty
        observerLock.unlock()
        guard !hasObservers else { return }

        let center = NotificationCenter.default
        let tokens = [
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("App即将非活跃")
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("App进入后台")
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("App即将回前台")
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("App前台活跃")
            },
            center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
                recordMemoryWarning()
            },
            center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("设备即将锁定")
            },
            center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("设备已解锁")
            },
            center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
                recordAndLogCritical("系统低电量模式变化")
            },
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("系统热状态变化")
            },
            center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                markGracefulTermination(reason: "收到willTerminate")
            }
        ]

        observerLock.lock()
        if observerTokens.isEmpty {
            observerTokens = tokens
        } else {
            tokens.forEach(center.removeObserver)
        }
        observerLock.unlock()
    }

    private static func recordAndLogCritical(_ reason: String) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        let snapshot = runtimeSnapshot(reason: reason, pipSnapshot: nil)
        storeCheckpoint(snapshot)
        AppDebugLogger.logCritical("生命周期诊断：\(snapshot)")
    }

    private static func runtimeSnapshot(reason: String, pipSnapshot: String?) -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let app = UIApplication.shared
        let state: String
        switch app.applicationState {
        case .active: state = "active"
        case .inactive: state = "inactive"
        case .background: state = "background"
        @unknown default: state = "unknown"
        }
        let remainingBackgroundTime = app.backgroundTimeRemaining
        let backgroundTime: String
        if app.applicationState != .background {
            backgroundTime = "不适用"
        } else if !remainingBackgroundTime.isFinite || remainingBackgroundTime > 24 * 60 * 60 {
            backgroundTime = "系统未限制"
        } else {
            backgroundTime = String(format: "%.1fs", remainingBackgroundTime)
        }
        let battery = UIDevice.current.batteryLevel >= 0
            ? "\(Int(UIDevice.current.batteryLevel * 100))%"
            : "未知"
        let pipText = pipSnapshot ?? DiagnosticsRuntimeState.snapshotText(includeAudio: false)
        return [
            "原因=\(reason)",
            "App=\(state)",
            "后台剩余=\(backgroundTime)",
            "受保护数据=\(app.isProtectedDataAvailable ? "可用" : "不可用/锁定")",
            "低电量=\(ProcessInfo.processInfo.isLowPowerModeEnabled ? "是" : "否")",
            "热状态=\(thermalStateText)",
            "电量=\(battery)",
            "物理内存=\(String(format: "%.1fGB", Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824))",
            "运行时长=\(String(format: "%.0fs", ProcessInfo.processInfo.systemUptime))",
            "保活策略=\(KeepAlivePolicy.current.diagnosticsName)",
            "音频{\(BackgroundTaskManager.shared.diagnosticsText)}",
            "现场{\(pipText)}"
        ].joined(separator: ", ")
    }

    private static var thermalStateText: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "正常"
        case .fair: return "轻微升温"
        case .serious: return "明显升温"
        case .critical: return "严重"
        @unknown default: return "未知"
        }
    }

    private static func dateText(_ timestamp: TimeInterval) -> String {
        guard timestamp > 0 else { return "无" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
