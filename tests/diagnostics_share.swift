import Foundation

enum AppDebugLogger {
    static let maximumEntries = 1200
    static let maximumEntryBytes = 16 * 1024
    static let maximumBufferBytes = 3_000_000
    static var memoryBuffer: [String] = []
    static var memoryBufferBytes = 0
    static func exportText(newestFirst: Bool = false) -> String {
        precondition(newestFirst)
        return "NEWEST-EVENT\nolder-event"
    }
    static func exerciseLimits() {
        memoryBuffer = Array(repeating: "event", count: 1201)
        memoryBufferBytes = memoryBuffer.reduce(0) { $0 + $1.utf8.count }
        trimMemoryBuffer()
        precondition(memoryBuffer.count == 1200)
        memoryBuffer = Array(repeating: String(repeating: "x", count: 16 * 1024), count: 300)
        memoryBufferBytes = memoryBuffer.reduce(0) { $0 + $1.utf8.count }
        trimMemoryBuffer()
        precondition(memoryBufferBytes <= 3_000_000)
        precondition(limitEntry(String(repeating: "x", count: 30_000)).utf8.count == 16 * 1024)
    }
}
enum LightweightRuntimeDiagnostics {
    static func exportText(newestFirst: Bool = false) -> String {
        precondition(newestFirst)
        return "LIGHTWEIGHT"
    }
}
enum KeepAliveLogger {
    static func exportText(newestFirst: Bool = false) -> String {
        precondition(newestFirst)
        return "KEEPALIVE"
    }
}
enum PowerUsageLogger {
    static func exportText() -> String { "POWER" }
}
final class MetricKitLogger {
    static let shared = MetricKitLogger()
    func exportText() -> String { "METRICKIT" }
}

func runTests() throws {
    let report = DiagnosticsLogExporter.exportText()
    precondition(report.hasPrefix("NEWEST-EVENT"))
    for section in ["LIGHTWEIGHT", "KEEPALIVE", "POWER", "METRICKIT"] {
        precondition(report.contains(section))
    }
    let text = report + String(repeating: "\n完整中文诊断记录", count: 40_000) + "\nEND-OF-REPORT"
    let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let first = try DiagnosticsLogExporter.writeTextFile(text, in: temporaryDirectory)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let second = try DiagnosticsLogExporter.writeTextFile(text, in: temporaryDirectory)
    precondition(first != second && first.pathExtension == "txt")
    let firstText = try String(contentsOf: first, encoding: .utf8)
    let secondText = try String(contentsOf: second, encoding: .utf8)
    precondition(firstText == text && secondText == text)
    let prefix = "globalrefresh-diagnostics-"
    let priorSession = temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString + "-" + UUID().uuidString)
    let legacyExport = temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString)
    let unrelated = temporaryDirectory.appendingPathComponent(prefix + "unrelated")
    let symlink = temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString)
    let regularFile = temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString)
    let fileManager = FileManager.default
    for directory in [priorSession, legacyExport, unrelated] {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
    }
    try fileManager.createSymbolicLink(at: symlink, withDestinationURL: unrelated)
    try Data().write(to: regularFile)
    let entries = try fileManager.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil)
    let abandoned = DiagnosticsLogExporter.abandonedTemporaryDirectories(in: entries)
    precondition(Set(abandoned.map(\.lastPathComponent)) == Set([priorSession, legacyExport].map(\.lastPathComponent)))
    for url in abandoned { try fileManager.removeItem(at: url) }
    precondition(fileManager.fileExists(atPath: first.path) && fileManager.fileExists(atPath: second.path))
    AppDebugLogger.exerciseLimits()
    print("PASS: diagnostics sections, full Unicode TXT, bounded storage, legacy/session cleanup and active-export protection")
}
