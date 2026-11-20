import Foundation
import ObjectiveC

final class VisibilityFixture: NSObject {
    @objc dynamic var stashedOrUnderLock = false
    var originalCalls = 0
    @objc(_setStashedOrUnderLock:reason:)
    dynamic func change(_ value: Bool, reason: Int) {
        originalCalls += 1
        stashedOrUnderLock = value
    }
}
final class ObjectReasonVisibilityFixture: NSObject {
    var originalCalls = 0
    @objc(_setStashedOrUnderLock:reason:)
    dynamic func change(_ value: Bool, reason: NSObject?) { originalCalls += 1 }
}
final class UnsupportedVisibilityFixture: NSObject {
    @objc(_setStashedOrUnderLock:reason:)
    dynamic func change(_ value: Double, reason: Double) {}
}

@main
struct VisibilityRefreshTests {
    static func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    static func main() {
        precondition(!PiPVisibilityRefreshPolicy.pauseContentUpdates && PiPVisibilityRefreshPolicy.pauseExtraBackgroundDriver,
                     "Group B retains content updates and only pauses the extra background driver")
        let defaults = UserDefaults.standard
        let oldValue = defaults.object(forKey: PiPVisibilityRefreshPolicy.preferenceKey)
        defer { defaults.set(oldValue, forKey: PiPVisibilityRefreshPolicy.preferenceKey) }
        defaults.removeObject(forKey: PiPVisibilityRefreshPolicy.preferenceKey)
        precondition(PiPVisibilityRefreshPolicy.isEnabled)
        defaults.set("NO", forKey: PiPVisibilityRefreshPolicy.preferenceKey)
        precondition(!PiPVisibilityRefreshPolicy.isEnabled, "The baseline launch argument must disable the trial")
        defaults.set("YES", forKey: PiPVisibilityRefreshPolicy.preferenceKey)
        precondition(PiPVisibilityRefreshPolicy.isEnabled)
        for enabled in [false, true] {
            for eligible in [false, true] {
                for active in [false, true] {
                    for bits in 0..<8 {
                        for privateState: Bool? in [nil, false, true] {
                            let hidden = bits & 1 != 0
                            let suspended = bits & 2 != 0
                            let protected = bits & 4 != 0
                            let result = PiPVisibilityRefreshPolicy.shouldPause(
                                enabled: enabled, eligible: eligible, active: active,
                                hidden: hidden, suspended: suspended, stashedOrUnderLock: privateState,
                                protectedDataUnavailable: protected)
                            precondition(result == (enabled && eligible && active && (hidden || suspended || protected || privateState == true)))
                        }
                    }
                }
            }
        }
        let first = VisibilityFixture()
        let sibling = VisibilityFixture()
        let observer = PiPVisibilityObserver()
        var events: [Bool] = []
        precondition(observer.install(proxy: first) { events.append($0) })
        precondition(events == [false], "Read the initial private state when a compatible getter exists")
        sibling.change(true, reason: 3)
        drain()
        precondition(events == [false] && sibling.originalCalls == 1, "Unobserved instances retain system behavior")
        first.change(true, reason: 4)
        drain()
        precondition(events == [false, true] && first.originalCalls == 1 && first.stashedOrUnderLock)
        first.change(false, reason: 5)
        observer.reset()
        drain()
        precondition(events == [false, true], "Discard a queued callback after stop")
        var replacementEvents: [Bool] = []
        precondition(observer.install(proxy: first) { replacementEvents.append($0) })
        first.change(true, reason: 6)
        precondition(observer.install(proxy: first) { events.append($0) })
        drain()
        precondition(replacementEvents == [false], "Discard callbacks belonging to an earlier observation")
        let objectReason = ObjectReasonVisibilityFixture()
        var objectEvents: [Bool] = []
        precondition(observer.install(proxy: objectReason) { objectEvents.append($0) })
        objectReason.change(true, reason: NSString(string: "lock"))
        drain()
        precondition(objectEvents == [true] && objectReason.originalCalls == 1)
        precondition(!observer.install(proxy: UnsupportedVisibilityFixture()) { _ in fatalError("Unsupported ABI") })
        for _ in 0..<100 {
            weak var released: PiPVisibilityObserver?
            do {
                let temporary = PiPVisibilityObserver()
                released = temporary
                precondition(temporary.install(proxy: first) { _ in })
            }
            precondition(released == nil, "Observation must not retain its owner")
        }
        print("PASS: visibility policy matrix; initial state; original dispatch; instance isolation; stale callbacks; supported/unsupported ABI; observation lifetime")
    }
}
