//
//  KeepAliveLogger.swift
//  pip_swift
//

import UIKit
import Darwin
import UserNotifications

enum KeepAliveNotificationProbeFrequency: String, CaseIterable {
    case low
    case high
    case ultra

    var title: String {
        switch self {
        case .low: return "低频检测"
        case .high: return "高频检测"
        case .ultra: return "超高频检测"
        }
    }

    var detail: String {
        switch self {
        case .low: return "30分钟检测一次，更适合日常使用"
        case .high: return "1分钟检测一次，更及时小幅增加耗电"
        case .ultra: return "20秒检测一次，适合极客用户"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .low: return 30 * 60
        case .high: return 60
        case .ultra: return 20
        }
    }

    var intervalText: String {
        switch self {
        case .low: return "30分钟"
        case .high: return "1分钟"
        case .ultra: return "20秒"
        }
    }

    var refreshInterval: TimeInterval {
        switch self {
        case .low: return 29 * 60
        case .high: return 55
        case .ultra: return 10
        }
    }

}

struct KeepAliveInterruptionNotice {
    let interruptedAtText: String
    let runtimeText: String

    var message: String {
        """
        上次后台在\(interruptedAtText)左右中断
        持续运行了\(runtimeText)
        """
    }
}

struct KeepAliveLocalNotificationNotice {
    let interruptedAtText: String
    let runtimeText: String
    let reason: String

    var message: String {
        """
        上次后台在\(interruptedAtText)左右中断
        持续运行了\(runtimeText)
        原因：\(reason)
        """
    }
}

enum KeepAliveLogger {
    private static let eventsKey = "pip.keepAlive.events"
    private static let sessionActiveKey = "pip.keepAlive.sessionActive"
    private static let sessionStartKey = "pip.keepAlive.sessionStart"
    private static let backgroundStartKey = "pip.keepAlive.backgroundStart"
    private static let lastHeartbeatKey = "pip.keepAlive.lastHeartbeat"
    private static let lastModeKey = "pip.keepAlive.lastMode"
    private static let maximumEvents = 80

    @discardableResult
    static func markAppLaunch() -> KeepAliveInterruptionNotice? {
        guard shouldTrackState else { return nil }
        if UserDefaults.standard.bool(forKey: sessionActiveKey),
           UserDefaults.standard.double(forKey: backgroundStartKey) > 0 {
            let sessionStart = storedTimestamp(sessionStartKey)
            let lastHeartbeat = storedTimestamp(lastHeartbeatKey)
            let heartbeatText = compactDateText(lastHeartbeat)
            let runtimeText = runtimeText(start: sessionStart, end: lastHeartbeat)
            appendIfDebug("App重新启动：上次保活可能异常中断，最后心跳=\(storedDateText(lastHeartbeatKey))，持续运行=\(runtimeText)，本次启动=\(nowText)")
            UserDefaults.standard.set(false, forKey: sessionActiveKey)
            UserDefaults.standard.removeObject(forKey: backgroundStartKey)
            return KeepAliveInterruptionNotice(interruptedAtText: heartbeatText, runtimeText: runtimeText)
        } else {
            appendIfDebug("App启动")
            return nil
        }
    }

    static func markPiPStarted(mode: String) {
        guard shouldTrackState else { return }
        UserDefaults.standard.set(true, forKey: sessionActiveKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: sessionStartKey)
        UserDefaults.standard.set(mode, forKey: lastModeKey)
        heartbeat()
        appendIfDebug("悬浮窗开始保活，模式=\(mode)")
    }

    static func markPiPStopped(reason: String) {
        guard shouldTrackState else { return }
        appendIfDebug("悬浮窗停止保活，原因=\(reason)，开始=\(storedDateText(sessionStartKey))，最后心跳=\(storedDateText(lastHeartbeatKey))")
        UserDefaults.standard.set(false, forKey: sessionActiveKey)
        UserDefaults.standard.removeObject(forKey: backgroundStartKey)
        KeepAliveNotificationTester.cancelBackgroundInterruptionProbe(reason: "悬浮窗停止：\(reason)")
    }

    static func markEnterBackground(mode: String) {
        guard shouldTrackState else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: backgroundStartKey)
        UserDefaults.standard.set(mode, forKey: lastModeKey)
        heartbeat()
        appendIfDebug("进入后台保活，模式=\(mode)")
        KeepAliveNotificationTester.notifyDidEnterBackground(mode: mode)
    }

    static func markEnterForeground() {
        guard shouldTrackState else { return }
        appendIfDebug("回到前台，后台开始=\(storedDateText(backgroundStartKey))，最后心跳=\(storedDateText(lastHeartbeatKey))")
        UserDefaults.standard.removeObject(forKey: backgroundStartKey)
        heartbeat()
        KeepAliveNotificationTester.cancelBackgroundInterruptionProbe(reason: "回到前台")
    }

    static func heartbeat() {
        guard shouldTrackState else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastHeartbeatKey)
    }

    static func backgroundInterruptionProbeDecision(staleAfter: TimeInterval) -> (shouldNotify: Bool, reason: String) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: sessionActiveKey) else {
            return (false, "保活会话未开启")
        }
        guard defaults.double(forKey: backgroundStartKey) > 0 else {
            return (false, "未记录后台保活")
        }
        let lastHeartbeat = defaults.double(forKey: lastHeartbeatKey)
        guard lastHeartbeat > 0 else {
            return (true, "没有心跳记录")
        }
        let age = Date().timeIntervalSince1970 - lastHeartbeat
        if age >= staleAfter {
            return (true, "最后心跳已超过\(durationText(age))")
        }
        return (false, "心跳正常，距上次心跳\(durationText(age))")
    }

    static func markNotificationScheduled(reason: String, fireAt: Date) {
        guard shouldTrackState else { return }
        append("通知已排队，原因=\(reason)，预计弹出=\(compactFormatter.string(from: fireAt))")
    }

    static func markNotificationCancelled(reason: String) {
        guard shouldTrackState else { return }
        append("通知已取消，原因=\(reason)")
    }

    static func markNotificationPaused(reason: String) {
        guard shouldTrackState else { return }
        append("通知已暂停，原因=\(reason)")
    }

    static func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
    }

    static func resetLogs() {
        let defaults = UserDefaults.standard
        for key in [eventsKey, sessionActiveKey, sessionStartKey, backgroundStartKey, lastHeartbeatKey, lastModeKey] {
            defaults.removeObject(forKey: key)
        }
        KeepAliveNotificationTester.cancelAllTestingNotifications(reason: "保活日志清空")
    }

    static func exportText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let device = UIDevice.current
        let events = UserDefaults.standard.stringArray(forKey: eventsKey) ?? []
        let isActive = UserDefaults.standard.bool(forKey: sessionActiveKey)

        return """
        全局高刷保活日志
        App版本：\(version) (\(build))
        Bundle ID：\(bundleID)
        系统版本：iOS \(device.systemVersion)
        设备型号：\(deviceModelIdentifier)
        生成时间：\(nowText) 北京时间
        当前保活模式：\(KeepAliveModeText.current)

        当前保活状态：\(isActive ? "可能正在保活" : "未处于保活")
        当前运行模式记录：\(UserDefaults.standard.string(forKey: lastModeKey) ?? "未知")
        保活开始时间：\(storedDateText(sessionStartKey))
        后台开始时间：\(storedDateText(backgroundStartKey))
        最后心跳时间：\(storedDateText(lastHeartbeatKey))

        说明：iOS 不会在 App 被杀死的瞬间通知普通 App；若下次启动时发现上次保活未正常停止，会用“最后心跳时间”到“本次启动时间”推断可能中断时间段。

        最近保活事件：
        \(events.isEmpty ? "暂无保活事件" : events.joined(separator: "\n"))
        """
    }

    private static func append(_ message: String) {
        var events = UserDefaults.standard.stringArray(forKey: eventsKey) ?? []
        events.append("\(nowText) | \(message)")
        if events.count > maximumEvents {
            events.removeFirst(events.count - maximumEvents)
        }
        UserDefaults.standard.set(events, forKey: eventsKey)
    }

    fileprivate static func appendIfDebug(_ message: String) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        append(message)
    }

    private static var shouldTrackState: Bool {
        AppDebugLogger.isDebugModeEnabled || KeepAliveNotificationTester.isEnabled
    }

    private static func storedDateText(_ key: String) -> String {
        let timestamp = storedTimestamp(key)
        guard timestamp > 0 else { return "无" }
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private static func storedTimestamp(_ key: String) -> TimeInterval {
        UserDefaults.standard.double(forKey: key)
    }

    private static func compactDateText(_ timestamp: TimeInterval) -> String {
        guard timestamp > 0 else { return "未知时间" }
        return compactFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private static func runtimeText(start: TimeInterval, end: TimeInterval) -> String {
        guard start > 0, end > 0, end >= start else { return "00:00:00" }
        let totalSeconds = max(0, Int((end - start).rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d小时%d分%d秒", hours, minutes, seconds)
        }
        if minutes > 0 {
            return String(format: "%d分%d秒", minutes, seconds)
        }
        return "\(seconds)秒"
    }

    fileprivate static var nowText: String {
        formatter.string(from: Date())
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static let compactFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M/d HH:mm:ss"
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

// TEST ANCHOR: 后台中断/悬浮窗停止提醒测试。撤回时删除本 enum，并移除 KeepAliveLogger/ViewController/VersionViewController 中的调用。
enum KeepAliveNotificationTester {
    private static let enabledKey = "pip.keepAlive.notificationTesterEnabled"
    private static let frequencyKey = "pip.keepAlive.notificationProbeFrequency"
    private static let frequencyMigrationKey = "pip.keepAlive.notificationProbeFrequency.v6"
    private static let defaultProbeFrequency = KeepAliveNotificationProbeFrequency.low
    private static let backgroundProbeIdentifier = "pip.keepAlive.backgroundInterruptionProbe"
    private static let pipStoppedIdentifier = "pip.keepAlive.pipStopped"
    private static let pendingLocalNotificationNoticeKey = "pip.keepAlive.pendingLocalNotificationNotice"
    private static let immediateDelay: TimeInterval = 1
    private static let backgroundProbeSafetyWindow: TimeInterval = 60
    private static let heartbeatStaleGrace: TimeInterval = 90
    private static let foregroundTakeoverGrace: TimeInterval = 5 * 60
    private static let systemOverlayProtectionThreshold: TimeInterval = 1.2
    private static let cameraInterruptionWindow: TimeInterval = 2
    private static let backgroundProbeQueue = DispatchQueue(label: "pip.keepAlive.backgroundProbeRefresh")
    private static var backgroundProbeRefreshTimer: DispatchSourceTimer?
    private static let backgroundProbeGenerationLock = NSLock()
    private static var backgroundProbeGeneration = 0
    private static var pendingBackgroundProbeStartWorkItem: DispatchWorkItem?
    private static var pendingUnlockResumeWorkItem: DispatchWorkItem?
    private static var activeBackgroundProbeMode: String?
    private static var didInstallLockStateObserver = false
    private static var lastActiveResignAt: Date?
    private static var foregroundLockStartedAt: Date?
    private static var foregroundSystemOverlayStartedAt: Date?
    private static var foregroundTakeoverSuppressedUntil: Date?
    private static var lastAudioInterruptionBeganAt: Date?
    private static var suppressBackgroundProbeUntilUnlock = false

    static var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue {
                cancelAllTestingNotifications(reason: "关闭后台中断提醒beta")
            }
        }
    }

    static var probeFrequency: KeepAliveNotificationProbeFrequency {
        get {
            if !UserDefaults.standard.bool(forKey: frequencyMigrationKey) {
                UserDefaults.standard.set(true, forKey: frequencyMigrationKey)
                UserDefaults.standard.set(defaultProbeFrequency.rawValue, forKey: frequencyKey)
                return defaultProbeFrequency
            }
            let rawValue = UserDefaults.standard.string(forKey: frequencyKey) ?? defaultProbeFrequency.rawValue
            return KeepAliveNotificationProbeFrequency(rawValue: rawValue) ?? defaultProbeFrequency
        }
        set {
            let oldValue = probeFrequency
            UserDefaults.standard.set(newValue.rawValue, forKey: frequencyKey)
            guard oldValue != newValue else { return }
            AppDebugLogger.log("后台中断提醒频率切换：\(newValue.title)，间隔=\(newValue.intervalText)")
            restartActiveBackgroundProbeIfNeeded(reason: "频率切换")
        }
    }

    static func prepareForHomeToggle(from controller: UIViewController?, completion: @escaping (Bool) -> Void) {
        ensureAuthorizationForHomeToggle(from: controller) { granted in
            guard granted else {
                isEnabled = false
                completion(false)
                return
            }
            isEnabled = true
            sanitizeScheduledNotifications(reason: "首页开启后台中断通知")
            completion(true)
        }
    }

    static func sanitizeOnLaunch() {
        installLockStateObserverIfNeeded()
        sanitizeScheduledNotifications(reason: "启动清理")
    }

    static func presentLaunchInterruptionAlert(_ notice: KeepAliveInterruptionNotice, from controller: UIViewController) {
        guard isEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak controller] in
            guard let controller, controller.presentedViewController == nil else { return }
            let alert = UIAlertController(
                title: "后台保活可能已中断",
                message: notice.message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "知道了", style: .default))
            controller.present(alert, animated: true)
        }
    }

    static func presentPendingLocalNotificationAlertIfNeeded(from controller: UIViewController) {
        guard isEnabled, let notice = pendingLocalNotificationNoticeIfReady() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak controller] in
            guard let controller, controller.presentedViewController == nil else { return }
            let alert = UIAlertController(
                title: "后台保活可能已中断",
                message: notice.message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "知道了", style: .default))
            controller.present(alert, animated: true)
            clearPendingLocalNotificationNotice()
        }
    }

    static func startBackgroundInterruptionProbe(mode: String) {
        guard isEnabled else { return }
        DispatchQueue.main.async {
            installLockStateObserverIfNeeded()
            guard isAppInBackground else {
                clearBackgroundProbeStateOnMain(reason: "未在后台，跳过启动后台中断通知")
                return
            }
            guard !isForegroundLockProbeSuppressed else {
                activeBackgroundProbeMode = mode
                pauseBackgroundProbeForDeviceLockOnMain(reason: "前台锁屏进入后台，解锁前不安排通知")
                return
            }
            guard !isDeviceLocked else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "进入后台时设备锁定")
                return
            }
            guard !isForegroundSystemOverlayTransition else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "前台系统界面覆盖，跳过后台中断通知")
                return
            }
            guard !isForegroundLockTransition else {
                clearBackgroundProbeStateOnMain(reason: "前台锁屏，跳过后台中断通知")
                return
            }
            pendingUnlockResumeWorkItem?.cancel()
            pendingUnlockResumeWorkItem = nil
            activeBackgroundProbeMode = mode
            requestAuthorizationIfNeeded()
            pendingBackgroundProbeStartWorkItem?.cancel()
            pendingBackgroundProbeStartWorkItem = nil
            if isForegroundTakeoverSuppressed {
                startBackgroundProbeSafetyWindow(
                    mode: mode,
                    reason: "系统界面/相机保护",
                    detail: "保护剩余=\(notificationDelayText(foregroundTakeoverRemaining))"
                )
            } else {
                scheduleBackgroundProbeNotification(mode: mode, reason: "进入后台立即预排")
                startBackgroundProbeRefreshTimer(mode: mode)
            }
        }
    }

    static func markAudioInterruptionBegan() {
        DispatchQueue.main.async {
            lastAudioInterruptionBeganAt = Date()
            KeepAliveLogger.appendIfDebug("音频中断开始，已记录用于相机/系统界面保护判断")
        }
    }

    // BETA2 ANCHOR: 后台中断通知状态机。控制中心、通知中心、相机等系统占用先进入保护窗口；普通退后台仍正常预排。
    static func notifyDidEnterBackground(mode: String) {
        DispatchQueue.main.async {
            let overlayElapsed = foregroundSystemOverlayElapsed
            let shouldProtectSystemOverlay = overlayElapsed.map { $0 >= systemOverlayProtectionThreshold } ?? false
            let resignElapsed = lastActiveResignElapsed
            let shouldProtectCameraLikeTakeover = wasRecentlyAudioInterrupted
                && (resignElapsed.map { $0 < cameraInterruptionWindow } ?? false)
            foregroundSystemOverlayStartedAt = nil
            if isForegroundLockProbeSuppressed {
                foregroundTakeoverSuppressedUntil = nil
                activeBackgroundProbeMode = mode
                pauseBackgroundProbeForDeviceLockOnMain(reason: "前台锁屏后进入后台，解锁前不安排通知")
                return
            }
            foregroundLockStartedAt = nil
            if shouldProtectCameraLikeTakeover, !isDeviceLocked {
                enableForegroundTakeoverProtection(
                    reason: "疑似相机或系统界面保护",
                    detail: resignElapsed.map { String(format: "音频中断后前台非活跃%.1f秒进入后台", $0) }
                )
            } else if shouldProtectSystemOverlay, !isDeviceLocked {
                enableForegroundTakeoverProtection(
                    reason: "系统界面/相机保护",
                    detail: overlayElapsed.map { String(format: "前台非活跃%.1f秒后进入后台", $0) }
                )
            } else {
                foregroundTakeoverSuppressedUntil = nil
                if let overlayElapsed {
                    KeepAliveLogger.appendIfDebug(String(format: "普通退后台，未启用系统界面/相机保护，前台非活跃%.1f秒", overlayElapsed))
                }
            }
            startBackgroundInterruptionProbe(mode: mode)
        }
    }

    static func cancelBackgroundInterruptionProbe(reason: String) {
        DispatchQueue.main.async {
            clearBackgroundProbeStateOnMain(reason: reason)
        }
    }

    static func cancelAllTestingNotifications(reason: String) {
        DispatchQueue.main.async {
            stopBackgroundProbeRefreshTimer()
            activeBackgroundProbeMode = nil
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [backgroundProbeIdentifier, pipStoppedIdentifier]
            )
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [backgroundProbeIdentifier, pipStoppedIdentifier]
            )
            clearPendingLocalNotificationNotice()
            AppDebugLogger.log("保活提醒测试通知已全部取消，原因=\(reason)")
        }
    }

    private static func restartActiveBackgroundProbeIfNeeded(reason: String) {
        DispatchQueue.main.async {
            guard isEnabled, let mode = activeBackgroundProbeMode else { return }
            guard isAppInBackground else {
                clearBackgroundProbeStateOnMain(reason: "\(reason)：当前不在后台")
                return
            }
            guard !isForegroundLockProbeSuppressed else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason)：前台锁屏保护")
                return
            }
            guard !isDeviceLocked else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason)：设备锁定")
                return
            }
            guard !isForegroundSystemOverlayTransition else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason)：前台系统界面覆盖")
                return
            }
            guard !isForegroundLockTransition else {
                clearBackgroundProbeStateOnMain(reason: "\(reason)：前台锁屏")
                return
            }
            if isForegroundTakeoverSuppressed {
                KeepAliveLogger.markNotificationPaused(reason: "\(reason)：系统界面/相机保护中，暂不预排后台定时通知")
                AppDebugLogger.log("后台中断本地通知暂不安排，原因=\(reason)：系统界面/相机保护，剩余=\(notificationDelayText(foregroundTakeoverRemaining))")
            } else {
                scheduleBackgroundProbeNotification(mode: mode, reason: "\(reason)：预排")
            }
            startBackgroundProbeRefreshTimer(mode: mode)
        }
    }

    private static func scheduleBackgroundProbeNotification(mode: String, reason: String, delay: TimeInterval? = nil) {
        guard isEnabled, isAppInBackground, !isDeviceLocked, !isForegroundLockProbeSuppressed, !isForegroundSystemOverlayTransition, !isForegroundLockTransition else {
            clearBackgroundProbeNotifications()
            AppDebugLogger.log("跳过后台中断本地通知安排，原因=\(reason)，当前不在后台、设备锁定、前台锁屏保护、前台系统界面覆盖或前台锁屏")
            return
        }
        let frequency = probeFrequency
        let notificationDelay = max(1, delay ?? frequency.interval)
        let expectedAt = Date().addingTimeInterval(notificationDelay)
        let expectedText = notificationDateText(expectedAt)
        let notificationBody = """
        可能中断时间：\(expectedText)
        模式：\(mode)，频率：\(frequency.title)
        """
        let content = UNMutableNotificationContent()
        content.title = "后台定时探测中断通知"
        content.body = notificationBody
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: notificationDelay, repeats: false)
        let request = UNNotificationRequest(identifier: backgroundProbeIdentifier, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [backgroundProbeIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [backgroundProbeIdentifier])
        center.add(request) { error in
            if let error {
                AppDebugLogger.log("后台中断本地通知安排失败：\(error.localizedDescription)")
            } else {
                KeepAliveLogger.markNotificationScheduled(reason: reason, fireAt: expectedAt)
                AppDebugLogger.log("后台中断本地通知已安排，原因=\(reason)，频率=\(frequency.title)，延迟=\(notificationDelayText(notificationDelay))，预计=\(notificationDateText(expectedAt))，模式=\(mode)")
            }
        }
    }

    private static func startBackgroundProbeSafetyWindow(mode: String, reason: String, detail: String? = nil) {
        stopBackgroundProbeRefreshTimer()
        let fallbackDelay = backgroundProbeSafetyWindow + probeFrequency.interval
        scheduleBackgroundProbeNotification(
            mode: mode,
            reason: "\(reason)：安全窗口兜底预排",
            delay: fallbackDelay
        )
        KeepAliveLogger.markNotificationPaused(reason: "\(reason)：进入\(Int(backgroundProbeSafetyWindow))秒安全窗口，暂不启动正式刷新")
        let detailText = detail.map { "，\($0)" } ?? ""
        AppDebugLogger.log("后台中断通知进入安全窗口，原因=\(reason)\(detailText)，安全窗口=\(Int(backgroundProbeSafetyWindow))秒，兜底延迟=\(notificationDelayText(fallbackDelay))，模式=\(mode)")

        let workItem = DispatchWorkItem {
            pendingBackgroundProbeStartWorkItem = nil
            guard isEnabled else { return }
            guard isAppInBackground else {
                clearBackgroundProbeStateOnMain(reason: "\(reason)：安全窗口结束时已回前台")
                return
            }
            guard !isForegroundLockProbeSuppressed else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason)：安全窗口结束时仍处于前台锁屏保护")
                return
            }
            guard !isDeviceLocked else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason)：安全窗口结束时设备锁定")
                return
            }
            guard !isForegroundSystemOverlayTransition else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason)：安全窗口结束时仍有前台系统界面覆盖")
                return
            }
            guard !isForegroundLockTransition else {
                clearBackgroundProbeStateOnMain(reason: "\(reason)：安全窗口结束时仍处于前台锁屏")
                return
            }

            if isForegroundTakeoverSuppressed {
                foregroundTakeoverSuppressedUntil = nil
                KeepAliveLogger.appendIfDebug("\(reason)：安全窗口结束，已清理系统界面/相机保护并恢复正式检测")
            }

            activeBackgroundProbeMode = mode
            let decision = KeepAliveLogger.backgroundInterruptionProbeDecision(staleAfter: heartbeatStaleGrace)
            guard !decision.shouldNotify else {
                AppDebugLogger.log("后台中断通知安全窗口后暂不刷新，预检测=\(decision.reason)")
                return
            }
            scheduleBackgroundProbeNotification(mode: mode, reason: "\(reason)：安全窗口后正式预排，\(decision.reason)")
            startBackgroundProbeRefreshTimer(mode: mode)
        }
        pendingBackgroundProbeStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + backgroundProbeSafetyWindow, execute: workItem)
    }

    private static func startBackgroundProbeRefreshTimer(mode: String) {
        stopBackgroundProbeRefreshTimer()
        let frequency = probeFrequency
        let generation = activateBackgroundProbeGeneration()
        let timer = DispatchSource.makeTimerSource(queue: backgroundProbeQueue)
        timer.schedule(
            deadline: .now() + frequency.refreshInterval,
            repeating: frequency.refreshInterval,
            leeway: .seconds(1)
        )
        timer.setEventHandler {
            refreshBackgroundProbeFromTimer(mode: mode, generation: generation)
        }
        backgroundProbeRefreshTimer = timer
        timer.resume()
        AppDebugLogger.log("后台中断通知刷新计时器已启动，频率=\(frequency.title)，刷新间隔=\(frequency.refreshIntervalText)，方式=后台队列")
    }

    private static func refreshBackgroundProbeFromTimer(mode: String, generation: Int) {
        guard isBackgroundProbeGenerationActive(generation) else { return }
        guard isEnabled else {
            DispatchQueue.main.async {
                clearBackgroundProbeStateOnMain(reason: "刷新时通知已关闭")
            }
            return
        }
        KeepAliveLogger.heartbeat()
        guard !isForegroundTakeoverSuppressed else {
            AppDebugLogger.log("后台中断本地通知暂不刷新，原因=前台切到外部App保护，剩余=\(notificationDelayText(foregroundTakeoverRemaining))")
            return
        }
        let decision = KeepAliveLogger.backgroundInterruptionProbeDecision(staleAfter: heartbeatStaleGrace)
        guard isBackgroundProbeGenerationActive(generation) else { return }
        guard !decision.shouldNotify else {
            AppDebugLogger.log("后台中断本地通知不刷新，预检测=\(decision.reason)")
            return
        }
        scheduleBackgroundProbeNotificationFromTimer(
            mode: mode,
            reason: "后台保活心跳正常刷新，\(decision.reason)",
            generation: generation
        )
    }

    private static func scheduleBackgroundProbeNotificationFromTimer(mode: String, reason: String, generation: Int) {
        guard isEnabled, isBackgroundProbeGenerationActive(generation) else {
            return
        }
        let frequency = probeFrequency
        let expectedAt = Date().addingTimeInterval(frequency.interval)
        let expectedText = notificationDateText(expectedAt)
        let notificationBody = """
        可能中断时间：\(expectedText)
        模式：\(mode)，频率：\(frequency.title)
        """
        let content = UNMutableNotificationContent()
        content.title = "后台定时探测中断通知"
        content.body = notificationBody
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: frequency.interval, repeats: false)
        let request = UNNotificationRequest(identifier: backgroundProbeIdentifier, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [backgroundProbeIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [backgroundProbeIdentifier])
        center.add(request) { error in
            guard isBackgroundProbeGenerationActive(generation) else { return }
            if let error {
                AppDebugLogger.log("后台中断本地通知刷新失败：\(error.localizedDescription)")
            } else {
                KeepAliveLogger.markNotificationScheduled(reason: reason, fireAt: expectedAt)
                AppDebugLogger.log("后台中断本地通知已刷新，原因=\(reason)，频率=\(frequency.title)，延迟=\(frequency.intervalText)，预计=\(notificationDateText(expectedAt))，模式=\(mode)")
            }
        }
    }

    private static func sanitizeScheduledNotifications(reason: String) {
        DispatchQueue.main.async {
            guard isEnabled else {
                cancelAllTestingNotifications(reason: "\(reason)：通知关闭")
                return
            }
            guard isAppInBackground else {
                clearBackgroundProbeStateOnMain(reason: "\(reason)：前台清理残留")
                requestAuthorizationIfNeeded()
                return
            }
            guard !isForegroundLockProbeSuppressed else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason)：前台锁屏保护")
                requestAuthorizationIfNeeded()
                return
            }
            guard !isDeviceLocked else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason)：设备锁定")
                requestAuthorizationIfNeeded()
                return
            }
            guard !isForegroundSystemOverlayTransition else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason)：前台系统界面覆盖")
                requestAuthorizationIfNeeded()
                return
            }
            guard !isForegroundLockTransition else {
                clearBackgroundProbeStateOnMain(reason: "\(reason)：前台锁屏")
                requestAuthorizationIfNeeded()
                return
            }
            if isForegroundTakeoverSuppressed {
                requestAuthorizationIfNeeded()
                if let mode = activeBackgroundProbeMode {
                    KeepAliveLogger.markNotificationPaused(reason: "\(reason)：系统界面/相机保护中，暂不预排后台定时通知")
                    AppDebugLogger.log("后台中断本地通知暂不安排，原因=\(reason)：系统界面/相机保护，剩余=\(notificationDelayText(foregroundTakeoverRemaining))")
                    startBackgroundProbeRefreshTimer(mode: mode)
                }
                return
            }
            requestAuthorizationIfNeeded()
            if let mode = activeBackgroundProbeMode {
                scheduleBackgroundProbeNotification(mode: mode, reason: "\(reason)：预排")
                startBackgroundProbeRefreshTimer(mode: mode)
            }
        }
    }

    private static var isAppInBackground: Bool {
        UIApplication.shared.applicationState == .background
    }

    private static var isDeviceLocked: Bool {
        !UIApplication.shared.isProtectedDataAvailable
    }

    private static var isForegroundLockTransition: Bool {
        guard let foregroundLockStartedAt else { return false }
        return Date().timeIntervalSince(foregroundLockStartedAt) < 30
    }

    private static var isForegroundLockProbeSuppressed: Bool {
        suppressBackgroundProbeUntilUnlock
    }

    private static var isForegroundSystemOverlayTransition: Bool {
        guard let foregroundSystemOverlayStartedAt else { return false }
        return Date().timeIntervalSince(foregroundSystemOverlayStartedAt) < 120
    }

    private static var foregroundSystemOverlayElapsed: TimeInterval? {
        guard let foregroundSystemOverlayStartedAt else { return nil }
        return Date().timeIntervalSince(foregroundSystemOverlayStartedAt)
    }

    private static var lastActiveResignElapsed: TimeInterval? {
        guard let lastActiveResignAt else { return nil }
        return Date().timeIntervalSince(lastActiveResignAt)
    }

    private static var wasRecentlyAudioInterrupted: Bool {
        guard let lastAudioInterruptionBeganAt else { return false }
        return Date().timeIntervalSince(lastAudioInterruptionBeganAt) < cameraInterruptionWindow
    }

    private static var isForegroundTakeoverSuppressed: Bool {
        guard let foregroundTakeoverSuppressedUntil else { return false }
        if Date() < foregroundTakeoverSuppressedUntil {
            return true
        }
        self.foregroundTakeoverSuppressedUntil = nil
        return false
    }

    private static var foregroundTakeoverRemaining: TimeInterval {
        guard let foregroundTakeoverSuppressedUntil else { return 0 }
        return max(0, foregroundTakeoverSuppressedUntil.timeIntervalSinceNow)
    }

    private static func enableForegroundTakeoverProtection(reason: String, detail: String? = nil) {
        let until = Date().addingTimeInterval(foregroundTakeoverGrace)
        if let currentUntil = foregroundTakeoverSuppressedUntil, currentUntil > until {
            return
        }
        foregroundTakeoverSuppressedUntil = until
        let detailText = detail.map { "，\($0)" } ?? ""
        KeepAliveLogger.appendIfDebug("\(reason)已开启\(detailText)，\(Int(foregroundTakeoverGrace))秒内延后后台定时通知")
    }

    private static func installLockStateObserverIfNeeded() {
        guard !didInstallLockStateObserver else { return }
        didInstallLockStateObserver = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            lastActiveResignAt = Date()
            if UIApplication.shared.applicationState == .active {
                foregroundSystemOverlayStartedAt = Date()
                KeepAliveLogger.appendIfDebug("App临时非活跃，foregroundSystemOverlayStartedAt=\(KeepAliveLogger.nowText)")
                pauseBackgroundProbeForDeviceLockOnMain(reason: "前台临时非活跃，可能为控制中心或通知中心")
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            foregroundSystemOverlayStartedAt = nil
            foregroundTakeoverSuppressedUntil = nil
            if suppressBackgroundProbeUntilUnlock {
                KeepAliveLogger.appendIfDebug("App回到前台活跃，但仍处于前台锁屏保护，等待设备解锁")
                clearBackgroundProbeStateOnMain(reason: "回到前台活跃：前台锁屏保护")
                return
            }
            foregroundLockStartedAt = nil
            KeepAliveLogger.appendIfDebug("App回到前台活跃，已清理系统覆盖层标记")
            sanitizeScheduledNotifications(reason: "回到前台活跃")
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil,
            queue: .main
        ) { _ in
            KeepAliveLogger.appendIfDebug("设备即将锁定，foregroundLockStartedAt=\(KeepAliveLogger.nowText)，App状态=\(UIApplication.shared.applicationState.rawValue)")
            if didRecentlyLeaveForeground || UIApplication.shared.applicationState != .background {
                foregroundLockStartedAt = Date()
                foregroundTakeoverSuppressedUntil = nil
                suppressBackgroundProbeUntilUnlock = true
                clearBackgroundProbeStateOnMain(reason: "前台锁屏")
            } else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "设备锁定")
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { _ in
            foregroundLockStartedAt = nil
            foregroundTakeoverSuppressedUntil = nil
            suppressBackgroundProbeUntilUnlock = false
            clearBackgroundProbeNotifications()
            KeepAliveLogger.markNotificationCancelled(reason: "设备解锁：等待前后台状态稳定")
            KeepAliveLogger.appendIfDebug("设备解锁，已清理前台锁屏标记，延迟确认后台状态后再恢复通知")
            pendingUnlockResumeWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                guard isEnabled else { return }
                guard let mode = activeBackgroundProbeMode else {
                    KeepAliveLogger.appendIfDebug("设备解锁后无活动后台探测，跳过通知恢复")
                    return
                }
                guard isAppInBackground else {
                    clearBackgroundProbeStateOnMain(reason: "设备解锁后已回前台，跳过通知恢复")
                    return
                }
                guard !isDeviceLocked else {
                    pauseBackgroundProbeForDeviceLockOnMain(reason: "设备解锁后仍处于锁定")
                    return
                }
                guard !isForegroundSystemOverlayTransition else {
                    pauseBackgroundProbeForDeviceLockOnMain(reason: "设备解锁后仍有系统界面覆盖")
                    return
                }
                requestAuthorizationIfNeeded()
                scheduleBackgroundProbeNotification(mode: mode, reason: "设备解锁后仍在后台：预排")
                startBackgroundProbeRefreshTimer(mode: mode)
            }
            pendingUnlockResumeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
        }
    }

    private static func clearBackgroundProbeStateOnMain(reason: String) {
        pendingBackgroundProbeStartWorkItem?.cancel()
        pendingBackgroundProbeStartWorkItem = nil
        pendingUnlockResumeWorkItem?.cancel()
        pendingUnlockResumeWorkItem = nil
        stopBackgroundProbeRefreshTimer()
        activeBackgroundProbeMode = nil
        foregroundTakeoverSuppressedUntil = nil
        clearBackgroundProbeNotifications()
        KeepAliveLogger.markNotificationCancelled(reason: reason)
        AppDebugLogger.log("后台中断本地通知测试已取消，原因=\(reason)")
    }

    private static func pauseBackgroundProbeForDeviceLockOnMain(reason: String) {
        pendingBackgroundProbeStartWorkItem?.cancel()
        pendingBackgroundProbeStartWorkItem = nil
        pendingUnlockResumeWorkItem?.cancel()
        pendingUnlockResumeWorkItem = nil
        stopBackgroundProbeRefreshTimer()
        foregroundTakeoverSuppressedUntil = nil
        clearBackgroundProbeNotifications()
        KeepAliveLogger.markNotificationPaused(reason: reason)
        AppDebugLogger.log("后台中断本地通知已暂停，原因=\(reason)，解锁后若仍在后台会继续检测")
    }

    private static var didRecentlyLeaveForeground: Bool {
        guard let lastActiveResignAt else { return false }
        return Date().timeIntervalSince(lastActiveResignAt) < 5
    }

    private static func stopBackgroundProbeRefreshTimer() {
        deactivateBackgroundProbeGeneration()
        backgroundProbeRefreshTimer?.cancel()
        backgroundProbeRefreshTimer = nil
    }

    private static func activateBackgroundProbeGeneration() -> Int {
        backgroundProbeGenerationLock.lock()
        backgroundProbeGeneration += 1
        let generation = backgroundProbeGeneration
        backgroundProbeGenerationLock.unlock()
        return generation
    }

    private static func deactivateBackgroundProbeGeneration() {
        backgroundProbeGenerationLock.lock()
        backgroundProbeGeneration += 1
        backgroundProbeGenerationLock.unlock()
    }

    private static func isBackgroundProbeGenerationActive(_ generation: Int) -> Bool {
        backgroundProbeGenerationLock.lock()
        let isActive = backgroundProbeGeneration == generation
        backgroundProbeGenerationLock.unlock()
        return isActive
    }

    private static func clearBackgroundProbeNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [backgroundProbeIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [backgroundProbeIdentifier])
    }

    static func schedulePiPStoppedNotification(mode: String, reason: String) {
        guard isEnabled else { return }
        DispatchQueue.main.async {
            requestAuthorizationIfNeeded()
            let stoppedAt = Date()
            let stoppedText = notificationDateText(stoppedAt)
            let notificationBody = """
            中断时间：\(stoppedText)
            原因：可能被其他画中画应用挤掉或被系统停止
            模式：\(mode)
            """
            let content = UNMutableNotificationContent()
            content.title = "全局高刷悬浮窗已停止"
            content.body = notificationBody
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: immediateDelay, repeats: false)
            let request = UNNotificationRequest(identifier: pipStoppedIdentifier, content: content, trigger: trigger)
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [pipStoppedIdentifier])
            center.add(request) { error in
                if let error {
                    AppDebugLogger.log("悬浮窗停止本地通知安排失败：\(error.localizedDescription)")
                } else {
                    storePendingLocalNotificationNotice(
                        identifier: pipStoppedIdentifier,
                        interruptedAt: stoppedAt,
                        reason: "可能被其他画中画应用挤掉或被系统停止",
                        fireAt: stoppedAt.addingTimeInterval(immediateDelay)
                    )
                    KeepAliveLogger.markNotificationScheduled(reason: "悬浮窗停止：\(reason)，可能中断=\(stoppedText)", fireAt: stoppedAt.addingTimeInterval(immediateDelay))
                    AppDebugLogger.log("悬浮窗停止本地通知已安排，原因=\(reason)，可能中断=\(stoppedText)")
                }
            }
        }
    }

    static func shouldSuppressPiPStoppedNotification(reason: String) -> Bool {
        guard isEnabled else { return false }
        let protectedByLock = isDeviceLocked || isForegroundLockProbeSuppressed || isForegroundLockTransition
        guard protectedByLock else { return false }
        let protectionReason = "锁屏保护"
        KeepAliveLogger.markNotificationPaused(reason: "悬浮窗停止通知被\(protectionReason)拦截：\(reason)")
        AppDebugLogger.log("悬浮窗停止通知已拦截，保护=\(protectionReason)，原因=\(reason)")
        return true
    }

    private static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        AppDebugLogger.log("本地通知权限请求失败：\(error.localizedDescription)")
                    } else {
                        AppDebugLogger.log("本地通知权限请求结果：\(granted ? "允许" : "拒绝")")
                    }
                }
            case .denied:
                AppDebugLogger.log("本地通知权限已被拒绝，后台中断提醒无法弹出")
            default:
                break
            }
        }
    }

    private static func ensureAuthorizationForHomeToggle(from controller: UIViewController?, completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        AppDebugLogger.log("本地通知权限请求失败：\(error.localizedDescription)")
                    } else {
                        AppDebugLogger.log("本地通知权限请求结果：\(granted ? "允许" : "拒绝")")
                    }
                    DispatchQueue.main.async {
                        if !granted {
                            openSystemSettings(from: controller, reason: "首次授权未允许")
                        }
                        completion(granted)
                    }
                }
            case .denied:
                AppDebugLogger.log("本地通知权限未开启，跳转系统设置")
                DispatchQueue.main.async {
                    openSystemSettings(from: controller, reason: "权限关闭")
                    completion(false)
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    completion(true)
                }
            @unknown default:
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }

    private static func openSystemSettings(from controller: UIViewController?, reason: String) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        let message = "后台中断通知需要开启系统通知权限，请在设置里允许通知后再打开。"
        if let controller, controller.presentedViewController == nil {
            let alert = UIAlertController(title: "通知权限未开启", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
                UIApplication.shared.open(url)
            })
            controller.present(alert, animated: true)
        } else {
            UIApplication.shared.open(url)
        }
        AppDebugLogger.log("打开系统设置请求通知权限，原因=\(reason)")
    }

    private static let notificationFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M/d HH:mm:ss"
        return formatter
    }()

    private static func notificationDateText(_ date: Date) -> String {
        notificationFormatter.string(from: date)
    }

    private static func notificationDelayText(_ delay: TimeInterval) -> String {
        let totalSeconds = max(1, Int(delay.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0, seconds > 0 {
            return "\(minutes)分\(seconds)秒"
        }
        if minutes > 0 {
            return "\(minutes)分钟"
        }
        return "\(seconds)秒"
    }

    private static func storePendingLocalNotificationNotice(identifier: String, interruptedAt: Date, reason: String, fireAt: Date) {
        let sessionStart = UserDefaults.standard.double(forKey: "pip.keepAlive.sessionStart")
        let interruptedAtTimestamp = interruptedAt.timeIntervalSince1970
        let payload: [String: Any] = [
            "identifier": identifier,
            "interruptedAt": interruptedAtTimestamp,
            "interruptedAtText": notificationDateText(interruptedAt),
            "runtimeText": runtimeText(start: sessionStart, end: interruptedAtTimestamp),
            "reason": reason,
            "fireAt": fireAt.timeIntervalSince1970
        ]
        UserDefaults.standard.set(payload, forKey: pendingLocalNotificationNoticeKey)
    }

    private static func runtimeText(start: TimeInterval, end: TimeInterval) -> String {
        guard start > 0, end > 0, end >= start else { return "00:00:00" }
        let totalSeconds = max(0, Int((end - start).rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func clearPendingLocalNotificationNotice() {
        UserDefaults.standard.removeObject(forKey: pendingLocalNotificationNoticeKey)
    }

    private static func pendingLocalNotificationNoticeIfReady() -> KeepAliveLocalNotificationNotice? {
        guard let payload = UserDefaults.standard.dictionary(forKey: pendingLocalNotificationNoticeKey),
              let interruptedAtText = payload["interruptedAtText"] as? String,
              let runtimeText = payload["runtimeText"] as? String,
              let reason = payload["reason"] as? String,
              let fireAt = payload["fireAt"] as? TimeInterval else {
            return nil
        }
        if reason == "定时探测中断" {
            clearPendingLocalNotificationNotice()
            return nil
        }
        guard Date().timeIntervalSince1970 >= fireAt else { return nil }
        return KeepAliveLocalNotificationNotice(interruptedAtText: interruptedAtText, runtimeText: runtimeText, reason: reason)
    }

}

private extension KeepAliveNotificationProbeFrequency {
    var refreshIntervalText: String {
        switch self {
        case .low: return "29分钟"
        case .high: return "55秒"
        case .ultra: return "10秒"
        }
    }
}
