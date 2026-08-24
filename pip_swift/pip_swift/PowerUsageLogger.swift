//
//  PowerUsageLogger.swift
//  pip_swift
//

import UIKit
import Darwin

enum PowerUsageLogger {
    private static let maximumStatisticsAge: TimeInterval = 24 * 60 * 60
    private static let launchDateKey = "pip.power.launchDate"
    private static let foregroundStartKey = "pip.power.foregroundStart"
    private static let foregroundTotalKey = "pip.power.foregroundTotal"
    private static let backgroundStartKey = "pip.power.backgroundStart"
    private static let backgroundTotalKey = "pip.power.backgroundTotal"
    private static let pipStartKey = "pip.power.pipStart"
    private static let pipTotalKey = "pip.power.pipTotal"
    private static let keepAliveStartKey = "pip.power.keepAliveStart"
    private static let keepAliveTotalKey = "pip.power.keepAliveTotal"
    private static let pipStartCountKey = "pip.power.pipStartCount"
    private static let pipStopCountKey = "pip.power.pipStopCount"
    private static let keepAliveStartCountKey = "pip.power.keepAliveStartCount"
    private static let keepAliveStopCountKey = "pip.power.keepAliveStopCount"
    private static let backgroundEntryCountKey = "pip.power.backgroundEntryCount"
    private static let foregroundEntryCountKey = "pip.power.foregroundEntryCount"

    static func markLaunch() {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let defaults = UserDefaults.standard
        if defaults.object(forKey: launchDateKey) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: launchDateKey)
        }
        rotateStatisticsIfNeeded()
        markForegroundStart()
    }

    static func markForegroundStart() {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        stopTimer(startKey: backgroundStartKey, totalKey: backgroundTotalKey)
        startTimerIfNeeded(foregroundStartKey)
        increment(foregroundEntryCountKey)
    }

    static func markBackgroundStart() {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        stopTimer(startKey: foregroundStartKey, totalKey: foregroundTotalKey)
        startTimerIfNeeded(backgroundStartKey)
        increment(backgroundEntryCountKey)
    }

    static func markPiPStart() {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        if startTimerIfNeeded(pipStartKey) {
            increment(pipStartCountKey)
        }
    }

    static func markPiPStop() {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        if stopTimer(startKey: pipStartKey, totalKey: pipTotalKey) {
            increment(pipStopCountKey)
        }
    }

    static func markKeepAliveStart() {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        if startTimerIfNeeded(keepAliveStartKey) {
            increment(keepAliveStartCountKey)
        }
    }

    static func markKeepAliveStop() {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        if stopTimer(startKey: keepAliveStartKey, totalKey: keepAliveTotalKey) {
            increment(keepAliveStopCountKey)
        }
    }

    static func exportText() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        if !AppDebugLogger.isDebugModeEnabled {
            resetStatistics()
        }
        rotateStatisticsIfNeeded()
        let defaults = UserDefaults.standard
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let device = UIDevice.current
        let launchTimestamp = defaults.double(forKey: launchDateKey)
        let launchText = launchTimestamp > 0 ? beijingFormatter.string(from: Date(timeIntervalSince1970: launchTimestamp)) : "unknown"

        return """
        全局高刷耗电辅助日志
        App版本：\(version) (\(build))
        Bundle ID：\(bundleID)
        系统版本：iOS \(device.systemVersion)
        设备型号：\(deviceModelIdentifier)
        生成时间：\(beijingFormatter.string(from: Date())) 北京时间
        当前保活模式：\(KeepAliveModeText.current)
        本轮统计开始时间：\(launchText) 北京时间

        当前电量：\(batteryLevelText)
        充电状态：\(batteryStateText)

        前台累计：\(durationText(total(for: foregroundTotalKey, startKey: foregroundStartKey)))
        后台累计：\(durationText(total(for: backgroundTotalKey, startKey: backgroundStartKey)))
        悬浮窗开启累计：\(durationText(total(for: pipTotalKey, startKey: pipStartKey)))
        后台保活音频累计：\(durationText(total(for: keepAliveTotalKey, startKey: keepAliveStartKey)))

        前台进入次数：\(defaults.integer(forKey: foregroundEntryCountKey))
        后台进入次数：\(defaults.integer(forKey: backgroundEntryCountKey))
        悬浮窗开启次数：\(defaults.integer(forKey: pipStartCountKey))
        悬浮窗关闭次数：\(defaults.integer(forKey: pipStopCountKey))
        保活音频启动次数：\(defaults.integer(forKey: keepAliveStartCountKey))
        保活音频停止次数：\(defaults.integer(forKey: keepAliveStopCountKey))

        模式说明：PiP保活-低功耗不启动静音音频；音频强保活会累计后台保活音频时长。
        说明：iOS 不允许普通 App 读取系统电池用量百分比，本日志用于辅助判断悬浮窗、后台保活和音频会话的运行时长；统计周期最多保留24小时，超过后自动重新统计。
        """
    }

    static func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
    }

    static func resetStatistics() {
        let defaults = UserDefaults.standard
        for key in [launchDateKey] + totalKeys + countKeys + startKeys {
            defaults.removeObject(forKey: key)
        }
    }

    static func startFreshStatistics() {
        resetStatistics()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: launchDateKey)
    }

    @discardableResult
    private static func startTimerIfNeeded(_ key: String) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.double(forKey: key) <= 0 else { return false }
        defaults.set(Date().timeIntervalSince1970, forKey: key)
        return true
    }

    @discardableResult
    private static func stopTimer(startKey: String, totalKey: String) -> Bool {
        let defaults = UserDefaults.standard
        let start = defaults.double(forKey: startKey)
        guard start > 0 else { return false }
        let elapsed = max(0, Date().timeIntervalSince1970 - start)
        defaults.set(defaults.double(forKey: totalKey) + elapsed, forKey: totalKey)
        defaults.removeObject(forKey: startKey)
        return true
    }

    private static func total(for totalKey: String, startKey: String) -> TimeInterval {
        let defaults = UserDefaults.standard
        let total = defaults.double(forKey: totalKey)
        let start = defaults.double(forKey: startKey)
        guard start > 0 else { return total }
        return total + max(0, Date().timeIntervalSince1970 - start)
    }

    private static func increment(_ key: String) {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    private static func rotateStatisticsIfNeeded() {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let launchTimestamp = defaults.double(forKey: launchDateKey)
        guard launchTimestamp > 0 else {
            defaults.set(now, forKey: launchDateKey)
            return
        }
        guard now - launchTimestamp > maximumStatisticsAge else { return }

        let isForegroundActive = defaults.double(forKey: foregroundStartKey) > 0
        let isBackgroundActive = defaults.double(forKey: backgroundStartKey) > 0
        let isPiPActive = defaults.double(forKey: pipStartKey) > 0
        let isKeepAliveAudioActive = defaults.double(forKey: keepAliveStartKey) > 0

        for key in totalKeys + countKeys + startKeys {
            defaults.removeObject(forKey: key)
        }

        defaults.set(now, forKey: launchDateKey)
        if isForegroundActive {
            defaults.set(now, forKey: foregroundStartKey)
            defaults.set(1, forKey: foregroundEntryCountKey)
        }
        if isBackgroundActive {
            defaults.set(now, forKey: backgroundStartKey)
            defaults.set(1, forKey: backgroundEntryCountKey)
        }
        if isPiPActive {
            defaults.set(now, forKey: pipStartKey)
            defaults.set(1, forKey: pipStartCountKey)
        }
        if isKeepAliveAudioActive {
            defaults.set(now, forKey: keepAliveStartKey)
            defaults.set(1, forKey: keepAliveStartCountKey)
        }
    }

    private static var totalKeys: [String] {
        [foregroundTotalKey, backgroundTotalKey, pipTotalKey, keepAliveTotalKey]
    }

    private static var countKeys: [String] {
        [
            pipStartCountKey,
            pipStopCountKey,
            keepAliveStartCountKey,
            keepAliveStopCountKey,
            backgroundEntryCountKey,
            foregroundEntryCountKey
        ]
    }

    private static var startKeys: [String] {
        [foregroundStartKey, backgroundStartKey, pipStartKey, keepAliveStartKey]
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        return "\(hours)小时\(minutes)分\(remainingSeconds)秒"
    }

    private static var batteryLevelText: String {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return "未知" }
        return "\(Int((level * 100).rounded()))%"
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

    private static var beijingFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }

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
