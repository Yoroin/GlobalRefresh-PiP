import Foundation

final class AVPictureInPictureController: NSObject {
    var isPictureInPictureActive = false
    var localStyle = 2
    var writes = 0
    override func setValue(_ value: Any?, forKey key: String) {
        precondition(key == "controlsStyle")
        localStyle = value as! Int
        writes += 1
    }
}
final class PiPCoexistenceExperiment {
    static func setControlsStyleIfSupported(_ style: Int, on controller: AVPictureInPictureController) -> Bool {
        controller.setValue(style, forKey: "controlsStyle")
        return true
    }
    var calls = 0
    static func controlsStyle(of controller: AVPictureInPictureController) -> Int? { controller.localStyle }
    var lastResubmit = false
    func maintainControlsHidden(controller: AVPictureInPictureController, systemMajorVersion: Int, resubmitAfterTransition: Bool = false) -> Bool {
        calls += 1
        lastResubmit = resubmitAfterTransition
        return true
    }
}
enum AppDebugLogger {
    static var logs: [String] = []
    static func logCritical(_ value: String) { logs.append(value) }
}
func runTests() {
    let view = ViewController()
    let controller = AVPictureInPictureController()
    view.pipController = controller
    view.maintainPiPControlsHidden(reason: "pre-start", resubmitAfterTransition: true)
    precondition(controller.writes == 0)
    controller.isPictureInPictureActive = true
    view.maintainPiPControlsHidden(reason: "didStart")
    precondition(controller.writes == 1)
    view.maintainPiPControlsHidden(reason: "ordinary height check")
    precondition(controller.writes == 1)
    view.maintainPiPControlsHidden(reason: "post-start state applied", resubmitAfterTransition: true)
    precondition(controller.writes == 2, "Matching local style must not skip post-transition submission")
    precondition(view.pipCoexistenceExperiment.lastResubmit, "The transition flag must reach the actual proxy maintainer")
    precondition(AppDebugLogger.logs.last!.contains("resubmittedAfterTransition=true"))
    precondition(AppDebugLogger.logs.last!.contains("local state only"))
    let unrelated = AVPictureInPictureController()
    unrelated.isPictureInPictureActive = true
    view.maintainPiPControlsHidden(reason: "stale", controller: unrelated, resubmitAfterTransition: true)
    precondition(unrelated.writes == 0)
    view.isStoppingMaintainedControls = true
    view.maintainPiPControlsHidden(reason: "closing", resubmitAfterTransition: true)
    precondition(controller.writes == 2)
    view.isStoppingMaintainedControls = false
    view.usesIOS15NativeContentRefresh = false
    view.maintainPiPControlsHidden(reason: "compatibility route", resubmitAfterTransition: true)
    precondition(controller.writes == 2)
    print("PASS: actual controls-maintenance method resubmits after transition despite matching cache, avoids repeated ordinary writes, and guards inactive/stale/closing/other routes")
}
final class ViewController {
    var usesIOS15NativeContentRefresh = true
    var isStoppingMaintainedControls = false
    var pipController: AVPictureInPictureController?
    let pipCoexistenceExperiment = PiPCoexistenceExperiment()
    var preferredPiPControlsStyle = 2
    weak var lastMaintainedControlsController: AVPictureInPictureController?
