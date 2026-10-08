import Foundation
import CoreGraphics

final class UIColor {
    static let clear = UIColor()
    static let black = UIColor()
    static let white = UIColor()
    var cgColor: String { "color" }
}

final class CALayer {
    var backgroundColor: String?
    var frame = CGRect.zero
    var bounds: CGRect { CGRect(origin: .zero, size: frame.size) }
    func addSublayer(_ layer: CALayer) {}
    func setNeedsDisplay() {}
}

enum CATransaction {
    static func begin() {}
    static func setDisableActions(_ value: Bool) {}
    static func commit() {}
}

final class UIScreen {
    static let main = UIScreen()
    let scale: CGFloat = 3
    let maximumFramesPerSecond = 120
}

final class UIWindow {
    let screen = UIScreen.main
}

class UIView: NSObject {
    var bounds = CGRect.zero
    var frame: CGRect { didSet { bounds.size = frame.size } }
    var window: UIWindow?
    let layer = CALayer()
    var backgroundColor: UIColor?
    var isUserInteractionEnabled = true
    var isHidden = false
    var clipsToBounds = false
    var subviews: [UIView] = []
    var redrawRequests = 0
    override init() { frame = .zero; super.init() }
    init(frame: CGRect) { self.frame = frame; super.init(); bounds.size = frame.size }
    required init?(coder: NSCoder) { frame = .zero; super.init() }
    func addSubview(_ view: UIView) { subviews.append(view) }
    func setNeedsLayout() {}
    func layoutIfNeeded() { layoutSubviews() }
    func layoutSubviews() {}
    func setNeedsDisplay() { redrawRequests += 1 }
}

final class UITextView: UIView {
    var text = ""
    var textColor: UIColor?
    var contentSize = CGSize(width: 300, height: 1000)
    var contentOffset = CGPoint.zero
    var offsetWrites = 0
    func setContentOffset(_ value: CGPoint, animated: Bool) {
        contentOffset = value
        offsetWrites += 1
    }
}

final class ClockOverlayView: UIView {
    func configure(height: CGFloat, hidden: Bool, showsFPS: Bool) {}
}

final class CADisplayLink: NSObject {
    static var lastCreated: CADisplayLink?
    static var creations = 0
    private let target: NSObject
    private let selector: Selector
    var preferredFramesPerSecond = 0
    var timestamp: CFTimeInterval = 0
    var invalidated = false
    init(target: Any, selector: Selector) {
        self.target = target as! NSObject
        self.selector = selector
        super.init()
        Self.creations += 1
        Self.lastCreated = self
    }
    func add(to runLoop: RunLoop, forMode mode: RunLoop.Mode) {}
    func invalidate() { invalidated = true }
    func step(_ time: CFTimeInterval) {
        precondition(!invalidated)
        timestamp = time
        _ = target.perform(selector, with: self)
    }
}

enum AppDebugLogger {
    static func log(_ message: String) {}
}

@main
struct TextScrollingTests {
    static func main() {
        let view = PiPHiddenReferenceRenderView(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        let text = view.subviews.compactMap { $0 as? UITextView }.first!
        view.setText("test content")
        view.setClockMode(false, isHidden: false, height: 44)
        view.configure(isActive: true)
        let link = CADisplayLink.lastCreated!
        link.step(1)
        link.step(1.05)
        precondition(text.contentOffset.y > 0)

        view.setTextScrollingEnabled(false)
        let offset = text.contentOffset
        let writes = text.offsetWrites
        for frame in 1...120 { link.step(1.05 + Double(frame) / 60) }
        precondition(text.contentOffset == offset && text.offsetWrites == writes)
        precondition(text.redrawRequests == 120)
        precondition(!link.invalidated && CADisplayLink.creations == 1)
        precondition(view.diagnosticSummary.contains("textScrolling=false"))

        view.setTextScrollingEnabled(true)
        link.step(3.05 + 1.0 / 60)
        let expectedDelta = (text.contentSize.height - text.bounds.height) / 2.4 / 60
        precondition(abs(text.contentOffset.y - offset.y - expectedDelta) < 0.001)
        precondition(CADisplayLink.creations == 1)

        var clockFrames = 0
        view.onClockFrame = { _ in clockFrames += 1 }
        view.setTextScrollingEnabled(false)
        view.setClockMode(true, isHidden: false, height: 44)
        link.step(3.1)
        precondition(clockFrames == 1 && text.isHidden && !view.clockOverlay.isHidden)
        view.setClockMode(false, isHidden: false, height: 44)
        let frozen = text.contentOffset
        link.step(3.2)
        precondition(text.contentOffset == frozen)
        view.stop()
        precondition(link.invalidated)
        view.configure(isActive: true)
        let nextLink = CADisplayLink.lastCreated!
        nextLink.step(4)
        nextLink.step(4.1)
        precondition(text.contentOffset == frozen)
        view.configure(isActive: false)
        precondition(nextLink.invalidated)
        print("PASS: production renderer freezes/resumes text without jumps, retains one update link, respects clock mode and persisted disabled startup")
    }
}
