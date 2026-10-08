import Foundation

enum AppDebugLogger {
    static func logCritical(_ message: String) {}
}

@main
struct HiddenReferenceSwitchTests {
    static func main() {
        let keys = [PiPHiddenReferenceMode.preferenceKey, "pip.experiment.coexistenceProvider6", "pip.experiment.hidden.request120",
                    "pip.experiment.hidden.animateContent",
                    "pip.experiment.hidden.minimumSurface"]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        defer { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        precondition(!PiPHiddenReferenceOptions.requests120)
        precondition(PiPHiddenReferenceOptions.animatesContent)
        precondition(!PiPHiddenReferenceOptions.preservesMinimumSurface)
        precondition(PiPHiddenReferenceOptions.contentFramesPerSecond == 60)
        for major in 14...29 {
            precondition(PiPHiddenReferenceMode.supportsSystemMajorVersion(major) == (major >= 15 && major <= 27))
            for playerLayer in [false, true] {
                for pipOnly in [false, true] {
                    precondition(PiPHiddenReferenceMode.supports(systemMajorVersion: major, isPlayerLayer: playerLayer, isPiPOnly: pipOnly)
                        == ((major >= 15 && major <= 27) && !playerLayer && pipOnly))
                }
            }
        }

        for mask in 0..<(1 << keys.count) {
            for (index, key) in keys.enumerated() {
                UserDefaults.standard.set(mask & (1 << index) != 0, forKey: key)
            }
            precondition(!PiPHiddenReferenceMode.suppressesRefreshDriver)
            precondition(PiPHiddenReferenceMode.isEnabled, "Old opt-in values cannot disable the default beta policy")
            precondition(!PiPHiddenReferenceMode.suppressesStrictRefreshRequest,
                         "Normal routes must ignore all experimental switch combinations")
            let owner = UUID()
            PiPHiddenReferenceMode.begin(owner: owner)
            precondition(PiPHiddenReferenceMode.suppressesRefreshDriver)
            precondition(PiPHiddenReferenceMode.suppressesStrictRefreshRequest)
            precondition(!PiPHiddenReferenceOptions.requests120)
            precondition(PiPHiddenReferenceOptions.animatesContent)
            precondition(!PiPHiddenReferenceOptions.preservesMinimumSurface)
            PiPHiddenReferenceMode.end(owner: UUID())
            precondition(PiPHiddenReferenceMode.owner == owner)
            PiPHiddenReferenceMode.end(owner: owner)
            precondition(!PiPHiddenReferenceMode.suppressesStrictRefreshRequest)
        }
        print("PASS: iOS15-27 default content-only policy; unsupported/future systems, PlayerLayer and audio policies stay isolated; legacy switch combinations and owner-scoped cleanup")
    }
}
