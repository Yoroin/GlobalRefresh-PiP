//
//  AppDebugLogger.swift
//  pip_swift
//

import UIKit
import AVFoundation
import Darwin
import OSLog

enum AppDebugLogger {
    private static let storageKey = "pip.debug.recentLogs"
    private static let debugModeKey = "pip.debug.modeEnabled"
    private static let maximumEntries = 600
    private static let maximumEntryBytes = 8 * 1024
    private static let maximumBufferBytes = 1_500_000
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
            guard isDebugModeEnabled else {
                memoryBuffer.removeAll(keepingCapacity: false)
                memoryBufferBytes = 0
                UserDefaults.standard.removeObject(forKey: storageKey)
                return
            }
            let stored = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
            memoryBuffer = stored.suffix(maximumEntries).map(limitEntry)
            memoryBufferBytes = memoryBuffer.reduce(into: 0) { $0 += $1.utf8.count }
            trimMemoryBuffer()
            if stored != memoryBuffer {
                UserDefaults.standard.set(memoryBuffer, forKey: storageKey)
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
            flush()
        }
    }

    // 只写内存，不碰 UserDefaults
    static func log(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        append(message, persistImmediately: false, file: file, line: line)
    }

    // 生命周期、内存警告和保活切换使用此入口，避免系统直接终止时最后状态只留在内存。
    static func logCritical(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        append(message, persistImmediately: true, file: file, line: line)
    }

    private static func append(
        _ message: String,
        persistImmediately: Bool,
        file: StaticString,
        line: UInt
    ) {
        guard isDebugModeEnabled else { return }
        let limitedMessage = limitEntry(message)
        DiagnosticsRuntimeState.updateLastEvent(limitedMessage)
        logger.info("\(limitedMessage, privacy: .public)")
        let device = UIDevice.current
        let entry = limitEntry([
            beijingFormatter.string(from: Date()),
            "iOS \(device.systemVersion)",
            deviceModelIdentifier,
            "\(file):\(line)",
            limitedMessage
        ].joined(separator: " | "))

        logQueue.async {
            memoryBuffer.append(entry)
            memoryBufferBytes += entry.utf8.count
            trimMemoryBuffer()
            if persistImmediately {
                UserDefaults.standard.set(memoryBuffer, forKey: storageKey)
                UserDefaults.standard.synchronize()
            }
        }
    }

    // 只在复制日志/进后台/终止时落盘
    static func flush() {
        logQueue.async {
            guard isDebugModeEnabled else {
                memoryBuffer.removeAll(keepingCapacity: false)
                memoryBufferBytes = 0
                UserDefaults.standard.removeObject(forKey: storageKey)
                return
            }
            guard !memoryBuffer.isEmpty else { return }
            UserDefaults.standard.set(memoryBuffer, forKey: storageKey)
        }
    }

    static func exportText() -> String {
        var entries: [String] = []
        logQueue.sync { entries = memoryBuffer }
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
        \(ProcessTerminationDiagnostics.exportText())
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
        \(diagnosticsSection)

        最近日志：
        \(entries.isEmpty ? "暂无日志" : entries.joined(separator: "\n"))
        """
    }

    static func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
    }

    static func resetLogs() {
        let clearBuffer = {
            memoryBuffer.removeAll(keepingCapacity: false)
            memoryBufferBytes = 0
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        if DispatchQueue.getSpecific(key: logQueueKey) != nil {
            clearBuffer()
        } else {
            logQueue.sync(execute: clearBuffer)
        }
        DiagnosticsRuntimeState.reset()
        ProcessTerminationDiagnostics.reset()
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

    private static var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(String(UnicodeScalar(UInt8(value))))
        }
    }
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
        AppDebugLogger.log("用户操作：\(action)")
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

    private static func threadUsageSnapshot() -> ThreadUsageSnapshot {
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

        for index in 0..<Int(threadCount) {
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
        }

        defaults.set(true, forKey: runActiveKey)
        defaults.set(Date().timeIntervalSince1970, forKey: launchKey)
        defaults.set(0, forKey: memoryWarningCountKey)
        defaults.removeObject(forKey: lastMemoryWarningKey)
        installObserversIfNeeded()
        recordCheckpoint(reason: "进程启动")
        AppDebugLogger.logCritical("进程终止诊断已启动；\(defaults.string(forKey: previousRunSummaryKey) ?? "无上次异常终止记录")")
    }

    static func recordCheckpoint(
        reason: String,
        pipSnapshot: String? = nil,
        persistImmediately: Bool = true
    ) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        let defaults = UserDefaults.standard
        let snapshot = runtimeSnapshot(reason: reason, pipSnapshot: pipSnapshot)
        defaults.set(snapshot, forKey: lastCheckpointKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastCheckpointDateKey)
        defaults.set(ProcessInfo.processInfo.systemUptime, forKey: lastUptimeKey)
        if persistImmediately {
            defaults.synchronize()
        }
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
        defaults.synchronize()
        AppDebugLogger.logCritical("进程记录正常结束：\(reason)")
    }

    static func exportText() -> String {
        let defaults = UserDefaults.standard
        return """
        进程终止推断：
        上次运行：\(defaults.string(forKey: previousRunSummaryKey) ?? "无异常终止记录")
        本次启动：\(dateText(defaults.double(forKey: launchKey)))
        本次内存警告：\(defaults.integer(forKey: memoryWarningCountKey)) 次
        最后诊断现场：\(defaults.string(forKey: lastCheckpointKey) ?? "无")
        说明：iOS 不向普通App提供Jetsam瞬间回调；这里是根据最后持久化现场、设备重启、内存警告及MetricKit作出的推断，不等同于系统精确杀进程原因。
        """
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
            previousRunSummaryKey
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
        recordCheckpoint(reason: reason)
        AppDebugLogger.logCritical("生命周期诊断：\(runtimeSnapshot(reason: reason, pipSnapshot: nil))")
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
