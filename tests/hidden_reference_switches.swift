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
        precondition(PiPHiddenReferenceOptions.contentFramesPerSecond == 30)
        for major in 14...29 {
            precondition(!PiPHiddenReferenceMode.supportsSystemMajorVersion(major))
            for playerLayer in [false, true] {
                for pipOnly in [false, true] {
                    precondition(PiPHiddenReferenceMode.supports(systemMajorVersion: major, isPlayerLayer: playerLayer, isPiPOnly: pipOnly)
                        == false)
                    precondition(PiPNativeContentRefreshPolicy.supports(systemMajorVersion: major, isPlayerLayer: playerLayer, isPiPOnly: pipOnly)
                        == ((15...27).contains(major) && !playerLayer && pipOnly))
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
        print("PASS: native optimized startup on iOS15-27; retired hidden route disabled; future systems, PlayerLayer and audio stay isolated; all legacy switch combinations ignored and owner cleanup scoped")
    }
}
