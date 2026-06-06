//
//  KeepAliveLogger.swift
//  pip_swift
//

import UIKit
import Darwin

enum KeepAliveLogger {
    private static let eventsKey = "pip.keepAlive.events"
    private static let sessionActiveKey = "pip.keepAlive.sessionActive"
    private static let sessionStartKey = "pip.keepAlive.sessionStart"
    private static let backgroundStartKey = "pip.keepAlive.backgroundStart"
    private static let lastHeartbeatKey = "pip.keepAlive.lastHeartbeat"
    private static let lastModeKey = "pip.keepAlive.lastMode"
    private static let maximumEvents = 80

    static func markAppLaunch() {
        if UserDefaults.standard.bool(forKey: sessionActiveKey),
           UserDefaults.standard.double(forKey: backgroundStartKey) > 0 {
            append("App重新启动：上次保活可能异常中断，最后心跳=\(storedDateText(lastHeartbeatKey))，本次启动=\(nowText)")
            UserDefaults.standard.set(false, forKey: sessionActiveKey)
            UserDefaults.standard.removeObject(forKey: backgroundStartKey)
        } else {
            append("App启动")
        }
    }

    static func markPiPStarted(mode: String) {
        UserDefaults.standard.set(true, forKey: sessionActiveKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: sessionStartKey)
        UserDefaults.standard.set(mode, forKey: lastModeKey)
        heartbeat()
        append("悬浮窗开始保活，模式=\(mode)")
    }

    static func markPiPStopped(reason: String) {
        append("悬浮窗停止保活，原因=\(reason)，开始=\(storedDateText(sessionStartKey))，最后心跳=\(storedDateText(lastHeartbeatKey))")
        UserDefaults.standard.set(false, forKey: sessionActiveKey)
        UserDefaults.standard.removeObject(forKey: backgroundStartKey)
    }

    static func markEnterBackground(mode: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: backgroundStartKey)
        UserDefaults.standard.set(mode, forKey: lastModeKey)
        heartbeat()
        append("进入后台保活，模式=\(mode)")
    }

    static func markEnterForeground() {
        append("回到前台，后台开始=\(storedDateText(backgroundStartKey))，最后心跳=\(storedDateText(lastHeartbeatKey))")
        UserDefaults.standard.removeObject(forKey: backgroundStartKey)
        heartbeat()
    }

    static func heartbeat() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastHeartbeatKey)
    }

    static func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
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

    private static func storedDateText(_ key: String) -> String {
        let timestamp = UserDefaults.standard.double(forKey: key)
        guard timestamp > 0 else { return "无" }
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private static var nowText: String {
        formatter.string(from: Date())
    }

    private static var formatter: DateFormatter {
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
