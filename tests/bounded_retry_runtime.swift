import Foundation
import ObjectiveC

enum AppDebugLogger {
    static let isDebugModeEnabled = true
    static var entries: [String] = []
    static func log(_ text: String) {}
    static func logCritical(_ text: String) { entries.append(text) }
}

@main
struct BoundedRetryTests {
    static func pump(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    static func session(type: Int = 4) -> (PiPCoexistenceExperiment, AVPictureInPictureController, NSObject, NSObject) {
        let adapter = PCEMakeAdapter()!, proxy = PCEMakeProxy(type)!
        PCESetDelegate(proxy, adapter)
        let controller = AVPictureInPictureController(contentSource: .init())
        controller.platformAdapter = adapter
        controller.isPictureInPictureActive = true
        let trial = PiPCoexistenceExperiment()
        trial.schedulePostStartUpdateIfRequested(controller: controller, useNativePostStart: true)
        return (trial, controller, adapter, proxy)
    }
    static func main() {
        do {
            let (trial, controller, _, proxy) = session()
            controller.isPictureInPictureSuspended = true
            pump(1.2)
            precondition(PCEType(proxy) == 4 && PCESendCount(proxy) == 0)
            controller.isPictureInPictureSuspended = false
            pump(1.9)
            precondition(PCEType(proxy) == 6 && PCESendCount(proxy) == 1, "A temporary first-check suspension can recover")
            precondition(trial.diagnosticDescription.contains("mutationApplied=true") && trial.diagnosticDescription.contains("localReadback=6"), trial.diagnosticDescription)
            precondition(trial.diagnosticDescription.contains("systemCoexistence=unverified"))
            trial.restore()
        }
        do {
            let (trial, controller, adapter, proxy) = session()
            withExtendedLifetime((controller, adapter)) {
                pump(1.35)
                precondition(PCEType(proxy) == 6 && PCESendCount(proxy) == 1)
                PCESetType(proxy, 4)
                pump(1.5)
                precondition(PCEType(proxy) == 6 && PCESendCount(proxy) == 2)
                PCESetType(proxy, 4)
                pump(2.5)
                precondition(PCEType(proxy) == 6 && PCESendCount(proxy) == 3)
                PCESetType(proxy, 4)
                pump(4.2)
                precondition(PCEType(proxy) == 4 && PCESendCount(proxy) == 3, "Retries must end without permanent forcing")
                precondition(trial.diagnosticDescription.contains("window-ended-unconfirmed"))
            }
            trial.restore()
        }
        do {
            let (trial, controller, adapter, proxy) = session()
            withExtendedLifetime((controller, adapter)) {
                PCESetDeferred(proxy, true)
                pump(1.4)
                precondition(trial.diagnosticDescription.contains("mutationApplied=false"), "API invocation is not an actual write")
                precondition(trial.diagnosticDescription.contains("actualWrites=0"))
                PCECompleteDeferred(proxy)
                precondition(PCEType(proxy) == 4, "Expired deferred attempt cannot mutate state")
                PCESetDeferred(proxy, false)
                pump(1.4)
                precondition(PCEType(proxy) == 6 && trial.diagnosticDescription.contains("actualWrites=1"))
            }
            trial.restore()
        }
        do {
            let trial = PiPCoexistenceExperiment()
            let controller = AVPictureInPictureController(contentSource: .init())
            controller.isPictureInPictureActive = true
            trial.schedulePostStartUpdateIfRequested(controller: controller, useNativePostStart: true)
            pump(0.2)
            let adapter = PCEMakeAdapter()!, proxy = PCEMakeProxy(4)!
            PCESetDelegate(proxy, adapter)
            controller.platformAdapter = adapter
            pump(1.6)
            precondition(PCEType(proxy) == 6 && PCESendCount(proxy) == 1)
            precondition(trial.diagnosticDescription.contains("preparationAttempts=2/3"))
            trial.restore()
        }
        do {
            let (trial, controller, adapter, proxy) = session(type: 6)
            withExtendedLifetime((controller, adapter)) {
                pump(1.4)
                precondition(PCESendCount(proxy) == 0 && trial.diagnosticDescription.contains("mutationApplied=false"))
                precondition(trial.diagnosticDescription.contains("localReadback=6"), "A preexisting local6 must not imply an app write or system validation")
            }
            trial.restore()
        }
        do {
            let (trial, oldController, oldAdapter, oldProxy) = session()
            PCESetDeferred(oldProxy, true)
            pump(1.1)
            trial.cancelPendingTransition()
            let newAdapter = PCEMakeAdapter()!, newProxy = PCEMakeProxy(4)!
            PCESetDelegate(newProxy, newAdapter)
            let newController = AVPictureInPictureController(contentSource: .init())
            newController.isPictureInPictureActive = true
            newController.platformAdapter = newAdapter
            trial.schedulePostStartUpdateIfRequested(controller: newController, useNativePostStart: true)
            PCECompleteDeferred(oldProxy)
            pump(1.4)
            withExtendedLifetime((oldController, oldAdapter)) {
                precondition(PCEType(oldProxy) == 4 && PCEType(newProxy) == 6)
            }
            trial.restore()
        }
        do {
            let trial = PiPCoexistenceExperiment()
            let adapter = PCEMakeAdapter()!, proxy = PCEMakeProxy(4)!
            PCESetDelegate(proxy, adapter)
            let controller = AVPictureInPictureController(contentSource: .init())
            controller.platformAdapter = adapter
            controller.isPictureInPictureActive = true
            var eligible = true
            trial.schedulePostStartUpdateIfRequested(controller: controller, useNativePostStart: true) { eligible }
            eligible = false
            pump(2.8)
            precondition(PCEType(proxy) == 4 && PCESendCount(proxy) == 0, "A route/mode change must prevent every pending retry")
            trial.restore()
        }
        print("PASS: temporary suspension and preparation recovery; no premature submitted flag; drift recovery; three-updater limit and deadline; local/system evidence separation; stale deferred/session isolation")
    }
}
