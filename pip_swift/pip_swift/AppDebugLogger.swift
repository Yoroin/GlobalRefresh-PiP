//
//  AppDebugLogger.swift
//  pip_swift
//

import UIKit
import Darwin

enum AppDebugLogger {
    private static let storageKey = "pip.debug.recentLogs"
    private static let debugModeKey = "pip.debug.modeEnabled"
    private static let maximumEntries = 100

    static var isDebugModeEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: debugModeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: debugModeKey)
        }
    }

    static func log(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
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

        return """
        全局高刷调试日志
        App版本：\(version) (\(build))
        Bundle ID：\(bundleID)
        系统版本：iOS \(device.systemVersion)
        设备型号：\(deviceModelIdentifier)
        生成时间：\(beijingFormatter.string(from: Date())) 北京时间
        当前保活模式：\(KeepAliveModeText.current)

        最近日志：
        \(entries.isEmpty ? "暂无日志" : entries.joined(separator: "\n"))
        """
    }

    static func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
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
