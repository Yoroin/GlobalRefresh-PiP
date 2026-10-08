import Foundation
import ObjectiveC

enum AppDebugLogger {
    static var isDebugModeEnabled = true
    static var entries: [String] = []
    static func log(_ message: String) {}
    static func logCritical(_ message: String) { entries.append(message) }
}

@main
struct CoexistenceRuntimeTests {
    static func main() {
        UserDefaults.standard.removeObject(forKey: PiPHiddenReferenceMode.preferenceKey)
        let sibling = PCEMakeAdapter()!
        let adapter = PCEMakeAdapter()!
        let proxy = PCEMakeProxy(4)!
        let siblingProxy = PCEMakeProxy(1)!
        PCESetDelegate(proxy, adapter)
        let originalClass: AnyClass = object_getClass(adapter)!
        precondition(PCEControlsStyle(adapter) == 2)
        let constructed = PiPHiddenReferenceControls.withPolicy(adapterClass: originalClass, make: { () -> NSObject in
            precondition(PCEControlsStyle(adapter) == 5)
            precondition(PCEControlsStyle(sibling) == 2)
            return adapter
        }, adapter: { $0 })
        precondition(constructed === adapter && PCEControlsStyle(adapter) == 2,
                     "Style 5 is released after construction")
        let mismatched = PiPHiddenReferenceControls.withPolicy(adapterClass: originalClass, make: { () -> NSObject in
            precondition(PCEControlsStyle(adapter) == 5)
            return sibling
        }, adapter: { $0 })
        precondition(mismatched == nil && PCEControlsStyle(adapter) == 2)
        let controlsSelector = NSSelectorFromString("_proxyControlsStyle")
        let originalControlsImplementation = method_getImplementation(class_getInstanceMethod(originalClass, controlsSelector)!)
        let provider = NSSelectorFromString("pictureInPictureProxyContentType:")
        let experiment = PiPCoexistenceExperiment()
        precondition(!UserDefaults.standard.bool(forKey: PiPCoexistenceExperiment.preferenceKey))
        precondition(experiment.install(adapter: adapter, proxy: proxy))
        precondition(PCEType(proxy) == 6 && PCELastSentType(proxy) == 6)
        precondition(PCEProviderType(adapter, proxy) == 6)
        precondition(class_getInstanceMethod(originalClass, provider) != nil)
        precondition(object_getClass(adapter) === originalClass)
        precondition(object_getClass(sibling) === originalClass && !sibling.responds(to: provider))
        precondition(PCEProviderType(sibling, siblingProxy) == 1)
        precondition(PCEProviderType(adapter, siblingProxy) == 1, "Unrelated proxies retain their type")
        precondition(adapter.responds(to: NSSelectorFromString("description")))
        precondition(!adapter.responds(to: NSSelectorFromString("unsupportedTestSelector")))
        precondition(experiment.diagnosticDescription.contains("proxyDelegateMatches=true"))
        PCERunAdapterUpdate(adapter)
        precondition(PCEType(proxy) == 4, "Tracing must not override the original write-back")
        precondition(AppDebugLogger.entries.contains { $0.contains("newValue=4") && $0.contains("WRITE-TRACE") })
        PCERunProxyRecalculate(proxy)
        precondition(PCEType(proxy) == 6, "The native recalculation still calls the provider")
        precondition(AppDebugLogger.entries.contains { $0.contains("[_updatePlaybackStateContentTypeIfNeeded #") })
        precondition(Thread.current.threadDictionary["com.yoroin.pip.contentTypeTrace.context"] == nil)
        let setterTraceCount = AppDebugLogger.entries.filter { $0.contains("[setContentType #") }.count
        for _ in 0..<80 { PCESetType(proxy, 4) }
        precondition(AppDebugLogger.entries.filter { $0.contains("[setContentType #") }.count <= setterTraceCount + 24)
        PCERunProxyRecalculate(proxy)
        PCESetType(proxy, 4)
        PCERecalculate(proxy, adapter)
        precondition(PCEType(proxy) == 6, "AVKit recalculation reads the provider")
        let sends = PCESendCount(proxy)
        precondition(experiment.install(adapter: adapter, proxy: proxy))
        precondition(PCESendCount(proxy) == sends, "Idempotent installation sends no duplicate state")
        precondition(!experiment.install(adapter: sibling, proxy: proxy))
        experiment.restore()
        precondition(object_getClass(adapter) === originalClass && PCEType(proxy) == 4)
        precondition(PCESendCount(proxy) == sends, "Restore sends no remote update")
        PCERecalculate(proxy, adapter)
        precondition(PCEType(proxy) == 4 && PCEProviderType(adapter, proxy) == 4)
        precondition(!adapter.responds(to: provider), "After restore, PG takes the native fallback")
        let afterRestore = AppDebugLogger.entries.count
        PCERunAdapterUpdate(adapter)
        PCERunProxyRecalculate(proxy)
        precondition(AppDebugLogger.entries.count == afterRestore, "Tracing is dormant after restore")
        PCERecalculate(siblingProxy, sibling)
        precondition(PCEType(siblingProxy) == 1)
        experiment.restore()
        precondition(!experiment.install(adapter: adapter, proxy: PCEMakeUnsupportedProxy()!))
        precondition(!experiment.install(adapter: adapter, proxy: PCEMakeProxy(7)!))
        precondition(!experiment.install(adapter: PCEMakeExistingProviderAdapter()!, proxy: proxy))

        PCESetDeferred(proxy, true)
        precondition(experiment.install(adapter: adapter, proxy: proxy))
        experiment.restore()
        PCECompleteDeferred(proxy)
        precondition(PCEType(proxy) == 4, "A canceled startup cannot mutate restored state")
        precondition(experiment.install(adapter: adapter, proxy: proxy))
        experiment.restore()
        precondition(experiment.install(adapter: adapter, proxy: proxy))
        // Only the new installation's mutation may run.
        PCECompleteDeferred(proxy)
        precondition(PCEType(proxy) == 6)
        experiment.restore()
        PCESetDeferred(proxy, false)

        for _ in 0..<100 {
            autoreleasepool {
                let target = PCEMakeAdapter()!
                let targetProxy = PCEMakeProxy(4)!
                var session: PiPCoexistenceExperiment? = PiPCoexistenceExperiment()
                precondition(session!.install(adapter: target, proxy: targetProxy))
                session = nil
                precondition(object_getClass(target) === originalClass && PCEType(targetProxy) == 4)
            }
        }
        weak var weakAdapter: NSObject?
        weak var weakProxy: NSObject?
        autoreleasepool {
            let target = PCEMakeAdapter()!
            let targetProxy = PCEMakeProxy(4)!
            weakAdapter = target
            weakProxy = targetProxy
            precondition(experiment.install(adapter: target, proxy: targetProxy))
        }
        precondition(weakAdapter == nil && weakProxy == nil)
        experiment.restore()
        precondition(experiment.diagnosticDescription == "coexistenceProvider=false")
        if let nativeProxy = PCEMakeNativeStateProxy() {
            precondition(experiment.install(adapter: adapter, proxy: nativeProxy))
            precondition(PCENativeStateRoundTrips(nativeProxy))
            experiment.restore()
            precondition(PCEType(nativeProxy) == 4)
            print("PASS: native Pegasus dictionary-diff round-trip")
        } else {
            print("SKIP: native Pegasus framework/state unavailable on this test host")
        }

        let postOwner = UUID()
        PiPHiddenReferenceMode.begin(owner: postOwner)
        defer { UserDefaults.standard.removeObject(forKey: PiPCoexistenceExperiment.preferenceKey) }
        let postAdapter = PCEMakeAdapter()!
        let postProxy = PCEMakeProxy(4)!
        PCESetDelegate(postProxy, postAdapter)
        let postExperiment = PiPCoexistenceExperiment()
        func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
        precondition(PiPCoexistenceExperiment.postStartTransitionDelay == 1)
        precondition(postExperiment.install(adapter: postAdapter, proxy: postProxy))
        PCERunAdapterUpdate(postAdapter)
        let timedSends = PCESendCount(postProxy)
        postExperiment.schedulePostStartTransition { true }
        postExperiment.schedulePostStartTransition(delay: 0) { true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        precondition(PCEType(postProxy) == 4 && PCESendCount(postProxy) == timedSends,
                     "Duplicate entry must not shorten the 1-second startup window")
        RunLoop.main.run(until: Date().addingTimeInterval(1.05))
        precondition(PCEType(postProxy) == 6 && PCESendCount(postProxy) == timedSends + 1)
        postExperiment.restore()
        print("PASS: shared 1-second post-start delay and exactly one transition")
        precondition(postExperiment.install(adapter: postAdapter, proxy: postProxy))
        PCERunAdapterUpdate(postAdapter)
        let beforePostSend = PCESendCount(postProxy)
        precondition(PCEType(postProxy) == 4)
        postExperiment.schedulePostStartTransition(delay: 0) { true }
        postExperiment.schedulePostStartTransition(delay: 0) { true }
        precondition(PCEType(postProxy) == 4, "No synchronous post-start mutation")
        pump()
        precondition(PCEType(postProxy) == 6 && PCELastSentType(postProxy) == 6)
        precondition(PCESendCount(postProxy) == beforePostSend + 1, "Exactly one post-start submission")
        PCERunAdapterUpdate(postAdapter)
        pump()
        precondition(PCEType(postProxy) == 4, "The experiment must not continuously force type 6")
        postExperiment.restore()

        precondition(postExperiment.install(adapter: postAdapter, proxy: postProxy))
        PCERunAdapterUpdate(postAdapter)
        var active = true
        postExperiment.schedulePostStartTransition(delay: 0) { active }
        active = false
        pump()
        precondition(PCEType(postProxy) == 4, "Inactive or suspended PiP cannot be updated")
        postExperiment.restore()

        precondition(postExperiment.install(adapter: postAdapter, proxy: postProxy))
        PCERunAdapterUpdate(postAdapter)
        postExperiment.schedulePostStartTransition(delay: 0) { true }
        PiPHiddenReferenceMode.end(owner: postOwner)
        pump()
        precondition(PCEType(postProxy) == 4, "Ending the default session cancels delayed mutation")
        postExperiment.restore()
        PiPHiddenReferenceMode.begin(owner: postOwner)

        precondition(postExperiment.install(adapter: postAdapter, proxy: postProxy))
        PCERunAdapterUpdate(postAdapter)
        postExperiment.schedulePostStartTransition(delay: 0) { true }
        postExperiment.restore()
        precondition(postExperiment.install(adapter: postAdapter, proxy: postProxy))
        PCERunAdapterUpdate(postAdapter)
        let afterReinstall = PCESendCount(postProxy)
        pump()
        precondition(PCEType(postProxy) == 4 && PCESendCount(postProxy) == afterReinstall,
                     "Old scheduled work cannot mutate a replacement session")
        postExperiment.restore()

        precondition(postExperiment.install(adapter: postAdapter, proxy: postProxy))
        PCERunAdapterUpdate(postAdapter)
        PCESetDeferred(postProxy, true)
        active = true
        postExperiment.schedulePostStartTransition(delay: 0) { active }
        pump()
        active = false
        PCECompleteDeferred(postProxy)
        precondition(PCEType(postProxy) == 4, "Deferred submission rechecks active state")
        postExperiment.restore()
        PCESetDeferred(postProxy, false)
        PiPHiddenReferenceMode.end(owner: postOwner)
        precondition(!PiPHiddenReferenceMode.suppressesRefreshDriver)
        let oldOwner = UUID()
        let newOwner = UUID()
        PiPHiddenReferenceMode.begin(owner: oldOwner)
        precondition(PiPHiddenReferenceMode.suppressesRefreshDriver)
        PiPHiddenReferenceMode.begin(owner: newOwner)
        PiPHiddenReferenceMode.end(owner: oldOwner)
        precondition(PiPHiddenReferenceMode.suppressesRefreshDriver,
                     "Old teardown cannot release the new session's refresh suppression")
        PiPHiddenReferenceMode.end(owner: newOwner)
        precondition(!PiPHiddenReferenceMode.suppressesRefreshDriver)

        let earlyAdapter = PCEMakeAdapter()!
        let earlyProxy = PCEMakeProxy(4)!
        PCESetDelegate(earlyProxy, earlyAdapter)
        let earlyExperiment = PiPCoexistenceExperiment()
        precondition(earlyExperiment.prepareHiddenReference(adapter: earlyAdapter) {
            precondition(PCEControlsStyle(earlyAdapter) == 2,
                         "Early type submission must not change the internal control style")
            precondition(earlyAdapter.responds(to: provider), "Provider must exist before obtaining the proxy")
            precondition(PCEProviderType(earlyAdapter, earlyProxy) == 4)
            PCERecalculate(earlyProxy, earlyAdapter)
            precondition(PCELastSentType(earlyProxy) == 4, "The first fixture submission must use ordinary VideoCall type 4")
            return earlyProxy
        })
        precondition(PCEType(earlyProxy) == 4 && PCELastSentType(earlyProxy) == 4,
                     "Preparation must not overwrite the initial type with standby type 6")
        precondition(earlyExperiment.diagnosticDescription.contains("providerCalls=2"))
        precondition(PCEProviderType(earlyAdapter, siblingProxy) == 1)
        UserDefaults.standard.set(true, forKey: PiPHiddenReferenceMode.preferenceKey)
        PiPHiddenReferenceMode.begin(owner: newOwner)
        earlyExperiment.beginReferenceStartupProtection { true }
        precondition(PCEProviderType(earlyAdapter, earlyProxy) == 4, "Provider follows the startup phase")
        earlyExperiment.schedulePostStartTransition(delay: 0) { true }
        pump()
        precondition(PCEProviderType(earlyAdapter, earlyProxy) == 6, "Provider follows standby phase")
        earlyExperiment.restore()
        PiPHiddenReferenceMode.end(owner: newOwner)
        UserDefaults.standard.removeObject(forKey: PiPHiddenReferenceMode.preferenceKey)
        precondition(!earlyAdapter.responds(to: provider) && PCEType(earlyProxy) == 4)
        precondition(!earlyExperiment.prepareHiddenReference(adapter: earlyAdapter) { nil })
        precondition(!earlyAdapter.responds(to: provider), "Failed lazy proxy lookup must remove the association")
        precondition(!earlyExperiment.prepareHiddenReference(adapter: earlyAdapter) { PCEMakeUnsupportedProxy() })
        precondition(!earlyAdapter.responds(to: provider))
        print("PASS: early provider before proxy lookup, first type-4 fixture submission, 4->6 phase values, sibling isolation and failure cleanup")

        UserDefaults.standard.set(false, forKey: PiPCoexistenceExperiment.preferenceKey)
        UserDefaults.standard.set(true, forKey: PiPHiddenReferenceMode.preferenceKey)
        precondition(postExperiment.install(adapter: postAdapter, proxy: postProxy))
        PiPHiddenReferenceMode.begin(owner: newOwner)
        postExperiment.beginReferenceStartupProtection { true }
        precondition(PCEType(postProxy) == 4 && PCELastSentType(postProxy) == 4,
                     "Reference startup explicitly submits type 4")
        let protectionSends = PCESendCount(postProxy)
        postExperiment.beginReferenceStartupProtection { true }
        precondition(PCESendCount(postProxy) == protectionSends, "Only one startup protection submission")
        postExperiment.schedulePostStartTransition(delay: 0) { true }
        pump()
        precondition(PCEType(postProxy) == 6, "Reference-only mode retains the coexistence transition")
        postExperiment.restore()
        precondition(PCEControlsStyle(adapter) == 2 && PCEControlsStyle(sibling) == 2 && PCEControlsStyle(earlyAdapter) == 2)
        precondition(method_getImplementation(class_getInstanceMethod(originalClass, controlsSelector)!) == originalControlsImplementation,
                     "Content-type experiments must leave the proxy control getter untouched")
        print("PASS: proxy control getter unchanged throughout construction/provider/transition/restore tests")
        PiPHiddenReferenceMode.end(owner: newOwner)
        UserDefaults.standard.removeObject(forKey: PiPHiddenReferenceMode.preferenceKey)
        UserDefaults.standard.set(true, forKey: PiPCoexistenceExperiment.preferenceKey)
        precondition(postExperiment.install(adapter: postAdapter, proxy: postProxy))
        PCERunAdapterUpdate(postAdapter)
        postExperiment.schedulePostStartTransition(delay: 0) { true }
        pump()
        precondition(PCEType(postProxy) == 4, "Legacy coexistence=true cannot affect a compatibility session")
        postExperiment.restore()
        print("PASS: default session refresh suppression, owner isolation, release, transition and compatibility-route isolation")
        print("PASS: post-start one-shot submission, duplicate suppression, no force loop, inactive/disabled cancellation, replaced-session cancellation, deferred active-state check")
        print("PASS: unchanged adapter class, scoped respondsToSelector, delegate identity, instance/proxy isolation, idempotency, recalculation, restore, rejection, deferred cancellation, 100 cycles, weak ownership")
    }
}
