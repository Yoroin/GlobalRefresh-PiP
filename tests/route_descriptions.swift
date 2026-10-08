import Foundation
import AppKit

typealias UIFont = NSFont
enum AppDebugLogger {
    static func logCritical(_ message: String) {}
}
enum UIColor {
    static var secondaryLabel: NSColor { .secondaryLabelColor }
}
enum KeepAlivePolicy {
    case pipOnly, audioAlways
    static var current: Self = .pipOnly
}
enum L10n {
    static var usesChinese = true
    static func text(_ chinese: String, _ english: String) -> String { usesChinese ? chinese : english }
}
enum ProcessInfo {
    struct Version { var majorVersion = 27 }
    struct Info { var operatingSystemVersion = Version() }
    static var processInfo = Info()
}

@main
struct RouteDescriptionTests {
    static func main() {
        for chinese in [true, false] {
            L10n.usesChinese = chinese
            for major in [14, 15, 16, 17, 18, 26, 27, 28] {
                ProcessInfo.processInfo.operatingSystemVersion.majorVersion = major
                for policy in [KeepAlivePolicy.pipOnly, .audioAlways] {
                    KeepAlivePolicy.current = policy
                    let supported = (major >= 15 && major <= 27) && policy == .pipOnly
                    precondition(PiPRouteDescriptions.updatedDefaultAvailable == supported)
                    let text = PiPRouteDescriptions.videoCallText
                    let rendered = PiPRouteDescriptions.attributedCompatibilityText(text, font: .systemFont(ofSize: 16))
                    precondition(rendered.string == text, "Strikethrough must not add explanatory text")
                    precondition(!text.contains("\n"), "Default description keeps its original single-paragraph wording")
                    let range = (text as NSString).range(of: PiPRouteDescriptions.legacyLimitation)
                    precondition(range.location != NSNotFound)
                    let strike = rendered.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int
                    precondition((strike == NSUnderlineStyle.single.rawValue) == supported)
                    precondition(!PiPRouteDescriptions.playerLayerText.isEmpty)
                }
            }
        }
        print("PASS: Chinese/English obsolete limitations are struck only for the supported system and policy")
    }
}
