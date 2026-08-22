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
    private let storageFingerprintsKey = "pip.metricKit.payloadFingerprints"
    private let historyStatusKey = "pip.metricKit.beta5HistoryStatus"
    private let maximumPayloads = 5
    private let maximumPayloadBytes = 256 * 1024
    private var isStarted = false
    private var hasImportedPastPayloads = false

    private override init() {
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        guard AppDebugLogger.isDebugModeEnabled else { return }
        isStarted = true
        MXMetricManager.shared.add(self)
        importPastPayloads()
        AppDebugLogger.log("BETA5 MetricKit订阅已启动")
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        appendPayloads(payloads.map { $0.jsonRepresentation() }, source: "系统新回调指标")
        let summary = historicalExitSummary(from: payloads)
        UserDefaults.standard.set(
            "系统新回调：指标=\(payloads.count)，\(summary)",
            forKey: historyStatusKey
        )
        AppDebugLogger.logCritical("BETA5 MetricKit收到指标：\(payloads.count)条；\(summary)")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        appendPayloads(payloads.map { $0.jsonRepresentation() }, source: "系统新回调诊断")
        AppDebugLogger.logCritical("BETA5 MetricKit收到诊断载荷：\(payloads.count)条")
    }

    func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
    }

    func resetLogs() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: storageFingerprintsKey)
        defaults.removeObject(forKey: historyStatusKey)
        hasImportedPastPayloads = false
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

        BETA5历史退出指标读取：
        \(UserDefaults.standard.string(forKey: historyStatusKey) ?? "尚未读取；请确认调试模式已开启并重新进入App。")

        最近系统指标：
        \(payloads.isEmpty ? "暂无系统指标，请使用一段时间后第二天再复制。" : payloads.joined(separator: "\n\n----- MetricKit Payload -----\n\n"))
        """
    }

    private func importPastPayloads() {
        guard !hasImportedPastPayloads else { return }
        hasImportedPastPayloads = true

        let metricPayloads = MXMetricManager.shared.pastPayloads
        let diagnosticPayloads = MXMetricManager.shared.pastDiagnosticPayloads
        appendPayloads(
            metricPayloads.map { $0.jsonRepresentation() },
            source: "启动读取的历史指标"
        )
        appendPayloads(
            diagnosticPayloads.map { $0.jsonRepresentation() },
            source: "启动读取的历史诊断"
        )

        let exitSummary = historicalExitSummary(from: metricPayloads)
        let status = "历史指标=\(metricPayloads.count)条，历史诊断=\(diagnosticPayloads.count)条；\(exitSummary)"
        UserDefaults.standard.set(status, forKey: historyStatusKey)
        AppDebugLogger.logCritical("BETA5 MetricKit历史读取完成：\(status)")
    }

    private func appendPayloads(_ payloadData: [Data], source: String) {
        guard !payloadData.isEmpty else { return }
        let defaults = UserDefaults.standard
        var payloads = defaults.stringArray(forKey: storageKey) ?? []
        var fingerprints = defaults.stringArray(forKey: storageFingerprintsKey) ?? []
        let knownFingerprints = Set(fingerprints)
        let newEntries = payloadData.compactMap { data -> (fingerprint: String, text: String)? in
            let fingerprint = payloadFingerprint(for: data)
            guard !knownFingerprints.contains(fingerprint) else { return nil }
            let limitedData = data.count > maximumPayloadBytes
                ? data.prefix(maximumPayloadBytes)
                : data[...]
            let text = String(decoding: limitedData, as: UTF8.self)
            let summary = exitMetricSummary(from: data)
            let rawText = data.count > maximumPayloadBytes
                ? text + "\n[MetricKit 数据过长，已截断]"
                : text
            let formattedText = summary.isEmpty
                ? "来源：\(source)\n\(rawText)"
                : "来源：\(source)\nApp退出相关指标摘要：\n\(summary)\n\n原始MetricKit数据：\n\(rawText)"
            return (fingerprint, formattedText)
        }
        payloads.append(contentsOf: newEntries.map { $0.text })
        fingerprints.append(contentsOf: newEntries.map { $0.fingerprint })
        if payloads.count > maximumPayloads {
            payloads.removeFirst(payloads.count - maximumPayloads)
        }
        if fingerprints.count > maximumPayloads {
            fingerprints.removeFirst(fingerprints.count - maximumPayloads)
        }
        defaults.set(payloads, forKey: storageKey)
        defaults.set(fingerprints, forKey: storageFingerprintsKey)
    }

    private func historicalExitSummary(from payloads: [MXMetricPayload]) -> String {
        var backgroundNormal = 0
        var backgroundMemoryLimit = 0
        var backgroundCPULimit = 0
        var backgroundMemoryPressure = 0
        var backgroundBadAccess = 0
        var backgroundAbnormal = 0
        var backgroundIllegalInstruction = 0
        var backgroundWatchdog = 0
        var backgroundLockedFile = 0
        var backgroundTaskTimeout = 0
        var foregroundMemoryLimit = 0
        var foregroundBadAccess = 0
        var foregroundAbnormal = 0
        var foregroundIllegalInstruction = 0
        var foregroundWatchdog = 0
        var exitMetricCount = 0

        for payload in payloads {
            guard let metric = payload.applicationExitMetrics else { continue }
            exitMetricCount += 1
            let background = metric.backgroundExitData
            backgroundNormal += Int(background.cumulativeNormalAppExitCount)
            backgroundMemoryLimit += Int(background.cumulativeMemoryResourceLimitExitCount)
            backgroundCPULimit += Int(background.cumulativeCPUResourceLimitExitCount)
            backgroundMemoryPressure += Int(background.cumulativeMemoryPressureExitCount)
            backgroundBadAccess += Int(background.cumulativeBadAccessExitCount)
            backgroundAbnormal += Int(background.cumulativeAbnormalExitCount)
            backgroundIllegalInstruction += Int(background.cumulativeIllegalInstructionExitCount)
            backgroundWatchdog += Int(background.cumulativeAppWatchdogExitCount)
            backgroundLockedFile += Int(background.cumulativeSuspendedWithLockedFileExitCount)
            backgroundTaskTimeout += Int(background.cumulativeBackgroundTaskAssertionTimeoutExitCount)

            let foreground = metric.foregroundExitData
            foregroundMemoryLimit += Int(foreground.cumulativeMemoryResourceLimitExitCount)
            foregroundBadAccess += Int(foreground.cumulativeBadAccessExitCount)
            foregroundAbnormal += Int(foreground.cumulativeAbnormalExitCount)
            foregroundIllegalInstruction += Int(foreground.cumulativeIllegalInstructionExitCount)
            foregroundWatchdog += Int(foreground.cumulativeAppWatchdogExitCount)
        }

        guard exitMetricCount > 0 else {
            return "未发现App退出指标"
        }

        let values: [(String, Int)] = [
            ("后台正常退出", backgroundNormal),
            ("后台内存上限", backgroundMemoryLimit),
            ("后台CPU上限", backgroundCPULimit),
            ("后台系统内存压力", backgroundMemoryPressure),
            ("后台非法内存访问", backgroundBadAccess),
            ("后台异常退出", backgroundAbnormal),
            ("后台非法指令", backgroundIllegalInstruction),
            ("后台Watchdog", backgroundWatchdog),
            ("后台挂起时持有锁文件", backgroundLockedFile),
            ("后台任务超时", backgroundTaskTimeout),
            ("前台内存上限", foregroundMemoryLimit),
            ("前台非法内存访问", foregroundBadAccess),
            ("前台异常退出", foregroundAbnormal),
            ("前台非法指令", foregroundIllegalInstruction),
            ("前台Watchdog", foregroundWatchdog)
        ]
        let nonZeroValues = values.filter { $0.1 > 0 }
        guard !nonZeroValues.isEmpty else {
            return "退出指标载荷=\(exitMetricCount)条，未记录上述退出计数"
        }
        let details = nonZeroValues.map { "\($0.0)=\($0.1)" }.joined(separator: "，")
        return "退出指标载荷=\(exitMetricCount)条；\(details)"
    }

    private func payloadFingerprint(for data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func exitMetricSummary(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return "" }
        var lines: [String] = []

        func collect(_ value: Any, path: [String]) {
            if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted() {
                    if let child = dictionary[key] {
                        collect(child, path: path + [key])
                    }
                }
                return
            }
            if let array = value as? [Any] {
                for (index, child) in array.enumerated() {
                    collect(child, path: path + ["[\(index)]"])
                }
                return
            }

            let normalizedPath = path.joined(separator: ".").lowercased()
            guard normalizedPath.contains("exit")
                    || normalizedPath.contains("termination")
                    || normalizedPath.contains("jetsam")
                    || normalizedPath.contains("watchdog")
            else {
                return
            }
            guard let number = value as? NSNumber else { return }
            lines.append("\(path.joined(separator: ".")) = \(number)")
        }

        collect(object, path: [])
        return lines.prefix(120).joined(separator: "\n")
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
