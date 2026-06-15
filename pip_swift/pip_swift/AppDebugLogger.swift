//
//  AppDebugLogger.swift
//  pip_swift
//

import UIKit
import AVFoundation
import Darwin

enum AppDebugLogger {
    private static let storageKey = "pip.debug.recentLogs"
    private static let debugModeKey = "pip.debug.modeEnabled"
    private static let maximumEntries = 200

    static var isDebugModeEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: debugModeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: debugModeKey)
        }
    }

    static func log(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        guard isDebugModeEnabled else { return }
        DiagnosticsRuntimeState.updateLastEvent(message)
        let device = UIDevice.current
        let entry = [
            beijingFormatter.string(from: Date()),
            "iOS \(device.systemVersion)",
            deviceModelIdentifier,
            "\(file):\(line)",
            message
        ].joined(separator: " | ")

        var entries = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        entries.append(entry)
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        UserDefaults.standard.set(entries, forKey: storageKey)
    }

    static func exportText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let device = UIDevice.current
        let entries = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
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
        \(diagnosticsSection)

        最近日志：
        \(entries.isEmpty ? "暂无日志" : entries.joined(separator: "\n"))
        """
    }

    static func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
    }

    static func resetLogs() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        DiagnosticsRuntimeState.reset()
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
            source.schedule(deadline: .now() + 2, repeating: 15)
            source.setEventHandler {
                AppDebugLogger.log(makeSnapshot())
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
