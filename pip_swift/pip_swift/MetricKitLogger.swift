//
//  MetricKitLogger.swift
//  pip_swift
//

import UIKit
import Darwin
import MetricKit

final class MetricKitLogger: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitLogger()

    private let storageKey = "pip.metricKit.payloads"
    private let maximumPayloads = 5
    private let maximumPayloadBytes = 256 * 1024
    private var isStarted = false

    private override init() {
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        guard AppDebugLogger.isDebugModeEnabled else { return }
        isStarted = true
        MXMetricManager.shared.add(self)
        AppDebugLogger.log("MetricKit subscriber started")
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        appendPayloads(payloads.map { $0.jsonRepresentation() })
        AppDebugLogger.log("MetricKit received metric payloads: \(payloads.count)")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        appendPayloads(payloads.map { $0.jsonRepresentation() })
        AppDebugLogger.log("MetricKit received diagnostic payloads: \(payloads.count)")
    }

    func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
    }

    func resetLogs() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func exportText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let device = UIDevice.current
        let payloads = UserDefaults.standard.stringArray(forKey: storageKey) ?? []

        return """
        全局高刷系统指标日志（MetricKit）
        App版本：\(version) (\(build))
        Bundle ID：\(bundleID)
        系统版本：iOS \(device.systemVersion)
        设备型号：\(deviceModelIdentifier)
        生成时间：\(beijingFormatter.string(from: Date())) 北京时间
        当前保活模式：\(KeepAliveModeText.current)

        指标来源：Apple MetricKit，本机系统后台汇总生成，不联网。
        数据说明：MetricKit 通常需要约24小时才会回调每日系统指标；刚安装或使用时间太短时可能为空。

        最近系统指标：
        \(payloads.isEmpty ? "暂无系统指标，请使用一段时间后第二天再复制。" : payloads.joined(separator: "\n\n----- MetricKit Payload -----\n\n"))
        """
    }

    private func appendPayloads(_ payloadData: [Data]) {
        guard !payloadData.isEmpty else { return }
        var payloads = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        let newPayloads = payloadData.map { data -> String in
            let limitedData = data.count > maximumPayloadBytes
                ? data.prefix(maximumPayloadBytes)
                : data[...]
            let text = String(decoding: limitedData, as: UTF8.self)
            return data.count > maximumPayloadBytes
                ? text + "\n[MetricKit 数据过长，已截断]"
                : text
        }
        payloads.append(contentsOf: newPayloads)
        if payloads.count > maximumPayloads {
            payloads.removeFirst(payloads.count - maximumPayloads)
        }
        UserDefaults.standard.set(payloads, forKey: storageKey)
    }

    private var beijingFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }

    private var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(String(UnicodeScalar(UInt8(value))))
        }
    }
}
