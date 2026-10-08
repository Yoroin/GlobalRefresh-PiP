import Foundation
import Combine

enum UIAccessibility {
    static var isReduceMotionEnabled = false
}

enum UIApplication {
    enum State { case active, background }
    final class Application { var applicationState = State.active }
    static let shared = Application()
}

@main
struct UpgradePlaybackTests {
    static func main() {
        let playback = PiPUpgradePreviewPlayback()
        precondition(!playback.isRunning && playback.restingElapsed == 0,
                     "Presentation must start at the first frame before viewDidAppear")
        var updates: [(Bool, TimeInterval)] = []
        let subscription = playback.$state.dropFirst().sink {
            updates.append(($0.isRunning, $0.restingElapsed))
        }
        for _ in 0..<3 {
            updates.removeAll()
            playback.play()
            precondition(updates.count == 1 && updates[0].0 && updates[0].1 == 0,
                         "Start/replay must not publish a transient finished frame")
            playback.stop()
            precondition(!playback.isRunning && playback.restingElapsed == 10.8)
        }
        UIAccessibility.isReduceMotionEnabled = true
        playback.play()
        precondition(!playback.isRunning && playback.restingElapsed == 10.8)
        UIAccessibility.isReduceMotionEnabled = false
        UIApplication.shared.applicationState = .background
        playback.play()
        precondition(!playback.isRunning)
        withExtendedLifetime(subscription) {}
        print("PASS: first-frame initialization, atomic replay, pause and reduced-motion behavior")
    }
}
