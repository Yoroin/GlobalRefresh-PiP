import Foundation
import CoreGraphics
struct BackingVideoSpec: Equatable {
    let text: String
    var filename: String { text + ".mov" }
    let size = CGSize(width: 32, height: 32)
    let longVideo = false
}
enum PlaceholderVideoFactory {
    static func prepare(at url: URL, size: CGSize, text: String, longVideo: Bool, cancelled: () -> Bool) throws {
        precondition(!Thread.isMainThread, "Preparing video on the UI thread")
        if cancelled() { throw CocoaError(.userCancelled) }
    }
}
final class UIApplication {
    static let shared = UIApplication()
    enum State { case active, background }
    var applicationState = State.active
}
enum AppDebugLogger { static func logRuntime(_ msg: String) {} }
enum L10n { static func text(_ a: String, _ b: String) -> String { a } }
func run() {
    func pump(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        precondition(condition(), "Async preparation did not finish")
    }
    let vc = Harness()
    var calls: [Int] = []
    func start(_ n: Int) -> Bool {
        vc.deferBackingVideoStartIfNeeded {
            precondition(Thread.isMainThread)
            calls.append(n)
        }
    }
    precondition(!start(0) && vc.backingVideoJob == nil, "VideoCall must skip video preparation")
    vc.shouldPrepareBackingPlayerForPlayback = true
    GeneratedPiPVideoCache.queue.suspend()
    precondition(start(1))
    let first = vc.backingVideoJob!
    precondition(start(2) && vc.backingVideoJob === first)
    vc.backingVideoSpec = BackingVideoSpec(text: "new-size")
    GeneratedPiPVideoCache.queue.resume()
    pump { !calls.isEmpty }
    precondition(calls == [2] && vc.preparedBackingVideo?.spec == vc.backingVideoSpec && !start(3))
    let url = vc.preparedBackingVideo!.lease.url
    precondition(GeneratedPiPVideoCache.isInUse(url))
    var playerLease: GeneratedPiPVideoCache.Lease? = .init(url)
    vc.preparedBackingVideo = nil
    precondition(playerLease != nil && GeneratedPiPVideoCache.isInUse(url))
    playerLease = nil
    precondition(!GeneratedPiPVideoCache.isInUse(url))
    GeneratedPiPVideoCache.queue.suspend()
    precondition(start(4))
    let stale = vc.backingVideoJob!
    vc.cancelBackingVideoJob()
    vc.backingVideoSpec = BackingVideoSpec(text: "replacement")
    precondition(start(5))
    GeneratedPiPVideoCache.queue.resume()
    pump { calls.count > 1 }
    precondition(stale.isCancelled && calls == [2, 5])
    print("PASS: VideoCall isolation, off-main work, coalescing, latest size, lease lifetime and stale-job cancellation")
}
final class Harness {
    struct Content { var window: Int? }
    var viewIfLoaded: Content? = nil
    var presentedViewController: Int? = nil
    var backingVideoJob: BlockOperation?
    var pendingVideoSpec: BackingVideoSpec?
    var onBackingVideoReady: (() -> Void)?
    var preparedBackingVideo: (spec: BackingVideoSpec, lease: GeneratedPiPVideoCache.Lease)?
    var backingVideoSpec = BackingVideoSpec(text: "old")
    var pipController: NSObject? = nil
    var isPiPTransitioning = false
    var shouldPrepareBackingPlayerForPlayback = false
    func showMessage(_ text: String) { preconditionFailure(text) }
