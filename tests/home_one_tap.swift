import Foundation

enum L10n {
    static var english = false
    static func text(_ chinese: String, _ englishText: String) -> String {
        english ? englishText : chinese
    }
}

struct EngineRoute {
    var usesPlayerLayer = false
}

final class Controller {
    var isPictureInPictureActive = false
}

final class HomeHarness {
    var pipController: Controller?
    var isHiddenReferenceRequested = false
    var isPiPActive: Bool { pipController?.isPictureInPictureActive == true }
    var pipEngineRoute = EngineRoute()
    var calls: [String] = []
    func applyOneTapMinimumHeight(source: String) { calls.append("adjust") }
    func startHiddenReferencePiP(atMinimumHeight: Bool, source: String) {
        precondition(atMinimumHeight)
        calls.append("direct")
    }
    func startPiPFromShortcut(shouldHideAfterStart: Bool) {
        precondition(shouldHideAfterStart)
        calls.append("compatibility")
    }
    func tap() { startPiPAndHideFromHome() }
}

@main
struct HomeTests {
    static func main() {
        for active in [false, true] {
            for reference in [false, true] {
                let home = HomeHarness()
                home.pipController = Controller()
                home.pipController!.isPictureInPictureActive = active
                home.isHiddenReferenceRequested = reference
                home.tap()
                precondition(home.calls == [active ? "adjust" : reference ? "direct" : "compatibility"])
            }
        }
        let cold = HomeHarness()
        cold.isHiddenReferenceRequested = true
        cold.tap()
        precondition(cold.calls == ["direct"])
        for english in [false, true] {
            L10n.english = english
            for playerLayer in [false, true] {
                let home = HomeHarness()
                home.pipEngineRoute.usesPlayerLayer = playerLayer
                precondition(home.startAndHidePiPButtonTitle == (english ? "Start & Hide PiP" : "一键开启并隐藏"))
                home.pipController = Controller()
                home.pipController!.isPictureInPictureActive = true
                let activeTitle = playerLayer
                    ? (english ? "One-tap 1 pt" : "一键1pt")
                    : (english ? "One-tap 0.1 pt" : "一键0.1pt")
                precondition(home.startAndHidePiPButtonTitle == activeTitle)
                home.pipController!.isPictureInPictureActive = false
                precondition(home.startAndHidePiPButtonTitle == (english ? "Start & Hide PiP" : "一键开启并隐藏"))
            }
        }
        print("PASS: active PiP only adjusts; inactive hidden experiment directly starts; normal routes use the existing compatibility start; nil controller handled")
        print("PASS: Home title follows inactive/active/stopped state in Chinese and English; PlayerLayer retains its 1 pt title")
    }
}
