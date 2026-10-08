import AVKit
import Foundation
import ObjectiveC

// Scoped to the controller being constructed; ordinary adapters retain their getter.
enum PiPHiddenReferenceControls {
    private static var associationKey: UInt8 = 0
    private static var installed: Set<ObjectIdentifier> = []
    private typealias Getter = @convention(c) (AnyObject, Selector) -> Int
    private final class Construction {
        var adapter: NSObject?
        var hits = 0
    }
    private static var construction: Construction?

    static func makeController(source: AVPictureInPictureController.ContentSource) -> AVPictureInPictureController? {
        guard let adapterClass = NSClassFromString("AVPictureInPicturePlatformAdapter") else { return nil }
        return withPolicy(adapterClass: adapterClass, make: {
            AVPictureInPictureController(contentSource: source)
        }, adapter: { controller in
            guard let cls = object_getClass(controller),
                  let ivar = class_getInstanceVariable(cls, "_platformAdapter"),
                  let encoding = ivar_getTypeEncoding(ivar), encoding.pointee == 64 else { return nil }
            return object_getIvar(controller, ivar) as? NSObject
        })
    }

    static func withPolicy<T>(adapterClass: AnyClass, make: () -> T, adapter: (T) -> NSObject?) -> T? {
        precondition(Thread.isMainThread)
        guard construction == nil, install(adapterClass: adapterClass) else {
            AppDebugLogger.logCritical("Hidden reference controls unavailable: unsupported signature or nested construction; startup canceled")
            return nil
        }
        let context = Construction()
        construction = context
        defer { construction = nil }
        let value = make()
        guard let captured = context.adapter, captured === adapter(value) else {
            if let captured = context.adapter { clear(adapter: captured) }
            AppDebugLogger.logCritical("Hidden reference controls NOT applied: no matching adapter captured during construction; startup canceled")
            return nil
        }
        clear(adapter: captured)
        AppDebugLogger.logCritical("Hidden reference controls applied DURING construction: _proxyControlsStyle=5, hits=\(context.hits); override RELEASED after construction; first submission now uses content type 4; animation/controls require device validation")
        return value
    }

    static func clear(adapter: NSObject) {
        objc_setAssociatedObject(adapter, &associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static func install(adapterClass: AnyClass) -> Bool {
        let key = ObjectIdentifier(adapterClass)
        if installed.contains(key) { return true }
        let selector = NSSelectorFromString("_proxyControlsStyle")
        guard let method = class_getInstanceMethod(adapterClass, selector),
              method_getNumberOfArguments(method) == 2 else { return false }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        guard String(cString: returnType) == "q" else { return false }
        let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        let block: @convention(block) (AnyObject) -> Int = { object in
            guard let target = object as? NSObject else { return original(object, selector) }
            if objc_getAssociatedObject(target, &associationKey) != nil { return 5 }
            if Thread.isMainThread, let context = construction {
                if context.adapter == nil {
                    context.adapter = target
                    objc_setAssociatedObject(target, &associationKey, NSNumber(value: true), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
                if context.adapter === target {
                    context.hits += 1
                    return 5
                }
            }
            return original(object, selector)
        }
        let replacement = imp_implementationWithBlock(block)
        if !class_addMethod(adapterClass, selector, replacement, method_getTypeEncoding(method)) {
            method_setImplementation(method, replacement)
        }
        installed.insert(key)
        return true
    }
}

enum PiPHiddenReferenceOptions {
    // Fixed to the device-tested content-only policy; old switch preferences are ignored.
    static let requests120 = false
    static let animatesContent = true
    static let preservesMinimumSurface = false
    static let contentFramesPerSecond = 60
    static var summary: String {
        "request120=\(requests120), contentUpdates=\(animatesContent), contentPreferredFPS=\(contentFramesPerSecond), minimumSurface=\(preservesMinimumSurface)"
    }

}

// The session marker scopes private hooks independently of the content policy.
enum PiPHiddenReferenceMode {
    static let preferenceKey = "pip.experiment.hiddenVideoCallReference"
    // This beta makes the validated policy the default, ignoring old opt-in values.
    static let isEnabled = true
    static func supportsSystemMajorVersion(_ major: Int) -> Bool {
        (15...27).contains(major)
    }
    static func supports(systemMajorVersion: Int, isPlayerLayer: Bool, isPiPOnly: Bool) -> Bool {
        isEnabled && supportsSystemMajorVersion(systemMajorVersion) && !isPlayerLayer && isPiPOnly
    }
    static let didChangeNotification = Notification.Name("PiPHiddenReferenceSessionChanged")
    private(set) static var owner: UUID?
    static var suppressesRefreshDriver: Bool { owner != nil }
    static var suppressesStrictRefreshRequest: Bool { owner != nil && !PiPHiddenReferenceOptions.requests120 }

    static func begin(owner token: UUID) {
        precondition(Thread.isMainThread)
        guard owner != token else { return }
        owner = token
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func end(owner token: UUID) {
        precondition(Thread.isMainThread)
        guard owner == token else { return }
        owner = nil
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

// This is a render probe, not a media player or a measurement of system refresh rate.
final class PiPHiddenReferenceRenderView: UIView {
    private let surface = CALayer()
    private let textView = UITextView()
    let clockOverlay = ClockOverlayView()
    var onClockFrame: ((CADisplayLink) -> Void)?
    var onClockVisibilityChange: ((Bool) -> Void)?
    private var showsClock = false
    private var isTextScrollingEnabled = true
    private var contentHeight: CGFloat = 44
    private var clockAppearanceHeight: CGFloat?
    private var clockAppearanceVisible = false
    private var displayLink: CADisplayLink?
    private var preservesMinimumSurface = false
    private var phase: CGFloat = 0
    private var previousTimestamp: CFTimeInterval?
    private var lastLoggedAt: CFTimeInterval = 0
    private var tickCount = 0

    private final class Target: NSObject {
        weak var owner: PiPHiddenReferenceRenderView?
        init(owner: PiPHiddenReferenceRenderView) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
    }
    private lazy var target = Target(owner: self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear
        surface.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(surface)
        textView.backgroundColor = .black
        textView.textColor = .white
        textView.isUserInteractionEnabled = false
        addSubview(textView)
        clockOverlay.isHidden = true
        addSubview(clockOverlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setText(_ text: String) {
        guard textView.text != text else { return }
        textView.text = text
    }

    func setTextScrollingEnabled(_ enabled: Bool) {
        isTextScrollingEnabled = enabled
    }

    func setClockMode(_ enabled: Bool, isHidden: Bool, height: CGFloat) {
        contentHeight = height
        let visible = enabled && !isHidden
        setNeedsLayout()
        guard showsClock != visible else { return }
        showsClock = visible
        textView.isHidden = visible
        clockOverlay.isHidden = !visible
        surface.backgroundColor = (visible ? UIColor.white : UIColor.black).cgColor
        onClockVisibilityChange?(visible)
    }

    func configure(isActive: Bool) {
        preservesMinimumSurface = PiPHiddenReferenceOptions.preservesMinimumSurface
        clipsToBounds = !preservesMinimumSurface
        setNeedsLayout()
        layoutIfNeeded()
        let shouldAnimate = isActive && PiPHiddenReferenceOptions.animatesContent
        if !shouldAnimate {
            stop()
        } else if displayLink == nil {
            previousTimestamp = nil
            tickCount = 0
            lastLoggedAt = 0
            let link = CADisplayLink(target: target, selector: #selector(Target.tick(_:)))
            link.preferredFramesPerSecond = min(PiPHiddenReferenceOptions.contentFramesPerSecond, UIScreen.main.maximumFramesPerSecond)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let height = preservesMinimumSurface ? max(bounds.height, max(1, 2 / scale)) : bounds.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        textView.frame = surface.frame
        clockOverlay.frame = surface.frame
        if clockAppearanceHeight != contentHeight || clockAppearanceVisible != showsClock {
            clockAppearanceHeight = contentHeight
            clockAppearanceVisible = showsClock
            clockOverlay.configure(height: contentHeight, hidden: !showsClock, showsFPS: false)
        }
        CATransaction.commit()
    }

    private func tick(_ link: CADisplayLink) {
        if !showsClock, isTextScrollingEnabled, let previousTimestamp {
            phase = (phase + CGFloat(min(0.1, link.timestamp - previousTimestamp) / 2.4))
                .truncatingRemainder(dividingBy: 1)
        }
        previousTimestamp = link.timestamp
        setNeedsLayout()
        layoutIfNeeded()
        if showsClock {
            onClockFrame?(link)
            // Keep content rendering on the existing link, without a second clock/FPS driver.
            clockOverlay.layer.setNeedsDisplay()
        } else if isTextScrollingEnabled {
            let maxOffset = max(0, textView.contentSize.height - textView.bounds.height)
            textView.setContentOffset(CGPoint(x: 0, y: maxOffset * phase), animated: false)
        } else {
            // Freeze visible text without stopping the content-update link.
            textView.setNeedsDisplay()
        }
        tickCount += 1
        if lastLoggedAt == 0 || link.timestamp - lastLoggedAt >= 10 {
            AppDebugLogger.log("Hidden reference render probe: mode=\(showsClock ? "clock" : "text"), textScrolling=\(isTextScrollingEnabled), ticks=\(tickCount), host=\(bounds.size), surface=\(surface.bounds.size), attached=\(window != nil); \(PiPHiddenReferenceOptions.summary); callbacks do not prove rendered frames or global 120Hz")
            lastLoggedAt = link.timestamp
            tickCount = 0
        }
    }

    var diagnosticSummary: String {
        "mode=\(showsClock ? "clock" : "text"), textScrolling=\(isTextScrollingEnabled), contentPreferredFPS=\(displayLink?.preferredFramesPerSecond ?? 0), clockContentHeight=\(contentHeight), host=\(bounds.size), surface=\(surface.bounds.size), animating=\(displayLink != nil), attached=\(window != nil)"
    }

    deinit { displayLink?.invalidate() }
}

// Default-off, private API experiment. Restart the process to remove added methods completely.
final class PiPCoexistenceExperiment {
    static let preferenceKey = "pip.experiment.coexistenceProvider6"
    private static var associationKey: UInt8 = 0
    private static var traceKey: UInt8 = 0
    private static var traceHooks: Set<String> = []
    private static let threadTraceKey = "com.yoroin.pip.contentTypeTrace.context"
    private static var providers: [String: IMP] = [:]
    private typealias VoidMethod = @convention(c) (AnyObject, Selector) -> Void
    private typealias ObjectGetter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    private typealias IntegerGetter = @convention(c) (AnyObject, Selector) -> Int
    private typealias IntegerSetter = @convention(c) (AnyObject, Selector, Int) -> Void
    private typealias RespondsGetter = @convention(c) (AnyObject, Selector, Selector) -> Bool
    private typealias StateMutation = @convention(block) (AnyObject) -> Void
    private typealias StateUpdater = @convention(c) (AnyObject, Selector, StateMutation) -> Void

    private final class Configuration: NSObject {
        weak var proxy: NSObject?
        private let lock = NSLock()
        private var calls = 0
        private var traceCounts: [String: Int] = [:]
        private var tracingActive = true
        private var requestedType = 6
        let followsPlaybackPhase: Bool
        var isObtainingProxy = false
        let traceID = UUID().uuidString
        init(proxy: NSObject?, followsPlaybackPhase: Bool = false) {
            self.proxy = proxy
            self.followsPlaybackPhase = followsPlaybackPhase
            requestedType = followsPlaybackPhase ? 4 : 6
        }
        var providedType: Int {
            lock.lock()
            defer { lock.unlock() }
            return followsPlaybackPhase ? requestedType : 6
        }
        func setRequestedType(_ value: Int) {
            lock.lock()
            requestedType = value
            lock.unlock()
        }
        func recordCall() -> Int {
            lock.lock()
            defer { lock.unlock() }
            calls += 1
            return calls
        }
        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return calls
        }
        func trace(_ event: String, details: String, limit: Int = 6) {
            guard AppDebugLogger.isDebugModeEnabled else { return }
            lock.lock()
            let count = traceCounts[event, default: 0]
            let allowed = tracingActive && count < limit
            if allowed { traceCounts[event] = count + 1 }
            lock.unlock()
            guard allowed else { return }
            let stack = Thread.callStackSymbols.prefix(18).joined(separator: " <- ")
            AppDebugLogger.logCritical("PiP WRITE-TRACE session=\(traceID) [\(event) #\(count + 1)]: \(details); threadMain=\(Thread.isMainThread); stack=\(stack)")
        }
        func endTracing() {
            lock.lock()
            tracingActive = false
            lock.unlock()
        }
    }

    static let postStartTransitionDelay: TimeInterval = 1

    private weak var adapter: NSObject?
    private weak var proxy: NSObject?
    private var configuration: Configuration?
    private var originalContentType: Int?
    private var installationID: UUID?
    private var postStartScheduled = false
    private var postStartSubmitted = false
    private var referenceStartupSubmitted = false
    private static var isRequested: Bool {
        PiPHiddenReferenceMode.isEnabled && PiPHiddenReferenceMode.suppressesRefreshDriver
    }

    @discardableResult
    func prepareForStartIfRequested(controller: AVPictureInPictureController, isVideoCall: Bool) -> Bool {
        guard Self.isRequested else { return false }
        guard PiPHiddenReferenceMode.supportsSystemMajorVersion(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
              isVideoCall, !controller.isPictureInPictureActive else { return false }
        guard let adapter = Self.object(controller, selector: "platformAdapter"),
              let proxy = Self.object(adapter, selector: "pegasusProxy"),
              let expected = NSClassFromString("PGPictureInPictureProxy"),
              proxy.isKind(of: expected) else {
            AppDebugLogger.log("PiP class-provider beta skipped: pre-start adapter/proxy unavailable")
            return false
        }
        return install(adapter: adapter, proxy: proxy)
    }

    func prepareHiddenReference(controller: AVPictureInPictureController) -> Bool {
        guard Thread.isMainThread,
              let adapter = Self.object(controller, selector: "platformAdapter") else { return false }
        return prepareHiddenReference(adapter: adapter) {
            guard let proxy = Self.object(adapter, selector: "pegasusProxy"),
                  let expected = NSClassFromString("PGPictureInPictureProxy"),
                  proxy.isKind(of: expected) else { return nil }
            return proxy
        }
    }

    // The provider and its initial value must exist before the lazy proxy getter runs.
    func prepareHiddenReference(adapter candidate: NSObject, obtainProxy: () -> NSObject?) -> Bool {
        guard Thread.isMainThread, adapter == nil,
              objc_getAssociatedObject(candidate, &Self.associationKey) == nil,
              let base = object_getClass(candidate), Self.addScopedProvider(to: base) else { return false }
        let prepared = Configuration(proxy: nil, followsPlaybackPhase: true)
        objc_setAssociatedObject(candidate, &Self.associationKey, prepared, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        prepared.isObtainingProxy = true
        let candidateProxy = obtainProxy()
        prepared.isObtainingProxy = false
        guard let candidateProxy,
              prepared.proxy == nil || prepared.proxy === candidateProxy else {
            objc_setAssociatedObject(candidate, &Self.associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            prepared.endTracing()
            return false
        }
        prepared.proxy = candidateProxy
        let succeeded = install(adapter: candidate, proxy: candidateProxy, prepared: prepared)
        if !succeeded {
            objc_setAssociatedObject(candidate, &Self.associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            prepared.endTracing()
        }
        if succeeded {
            AppDebugLogger.logCritical("Hidden reference EARLY provider prepared before controls/automatic-start: initialType=4; provider follows 4->6 after startup; \(diagnosticDescription). Cold animation, controls and independent 120Hz require device validation.")
        }
        return succeeded
    }

    var diagnosticDescription: String {
        guard let adapter, let proxy, let configuration else { return "coexistenceProvider=false" }
        let delegate = Self.object(proxy, selector: "delegate")
        return "coexistenceProvider=true, variant=post-start-once-\(Self.postStartTransitionDelay)s, traceSession=\(configuration.traceID), providerCalls=\(configuration.callCount), postStartScheduled=\(postStartScheduled), postStartSubmitted=\(postStartSubmitted), requestedContentType=6, localContentType=\(Self.contentType(of: proxy).map(String.init) ?? "unknown"), adapterClass=\(NSStringFromClass(type(of: adapter))), proxyDelegateMatches=\(delegate === adapter)"
    }

    @discardableResult
    func install(adapter candidate: NSObject, proxy candidateProxy: NSObject) -> Bool {
        install(adapter: candidate, proxy: candidateProxy, prepared: nil)
    }

    private func install(adapter candidate: NSObject, proxy candidateProxy: NSObject, prepared: Configuration?) -> Bool {
        guard Thread.isMainThread else { return false }
        if let adapter { return adapter === candidate && proxy === candidateProxy }
        let updateSelector = NSSelectorFromString("updatePlaybackStateUsingBlock:")
        let setterSelector = NSSelectorFromString("setContentType:")
        guard let base = object_getClass(candidate),
              let proxyClass = object_getClass(candidateProxy),
              let update = Self.method(proxyClass, selector: updateSelector, result: "v", arguments: ["@?"]),
              let state = Self.object(candidateProxy, selector: "playbackState"),
              let stateClass = object_getClass(state),
              let setter = Self.method(stateClass, selector: setterSelector, result: "v", arguments: ["q"]),
              let previousType = Self.contentType(of: candidateProxy),
              previousType == 4 || (prepared != nil && previousType == 6),
              Self.addScopedProvider(to: base) else {
            AppDebugLogger.log("PiP class-provider beta skipped: unsupported signature, original provider or content type")
            return false
        }

        let token = UUID()
        let configuration = prepared ?? Configuration(proxy: candidateProxy)
        self.configuration = configuration
        installationID = token
        originalContentType = prepared == nil ? previousType : 4
        adapter = candidate
        proxy = candidateProxy
        objc_setAssociatedObject(candidate, &Self.associationKey, configuration, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        Self.installWriteTrace(adapter: candidate, proxy: candidateProxy, state: state, configuration: configuration)
        let setterIMP = unsafeBitCast(method_getImplementation(setter), to: IntegerSetter.self)
        let mutation: StateMutation = { [weak self, weak candidate] currentState in
            guard self?.installationID == token, let candidate,
                  (objc_getAssociatedObject(candidate, &Self.associationKey) as? Configuration) === configuration,
                  object_getClass(currentState) === stateClass else { return }
            setterIMP(currentState, setterSelector, configuration.providedType)
        }
        unsafeBitCast(method_getImplementation(update), to: StateUpdater.self)(candidateProxy, updateSelector, mutation)
        AppDebugLogger.logCritical("PiP class-provider beta prepared BEFORE start: no isa change; \(diagnosticDescription). Remote acceptance, coexistence and 120Hz unverified; source/size/audio/frame-rate unchanged.")
        for delay in [0.25, 0.75, 2.0, 3.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.installationID == token else { return }
                self.checkpoint("startup +\(delay)s")
            }
        }
        return true
    }

    func checkpoint(_ event: String) {
        guard configuration != nil else { return }
        AppDebugLogger.logCritical("PiP class-provider checkpoint [\(event)]: \(diagnosticDescription)")
    }

    func schedulePostStartUpdateIfRequested(controller: AVPictureInPictureController) {
        guard controller.isPictureInPictureActive else { return }
        let isStillActive = { [weak controller, weak self] in
            guard let controller, let self, controller.isPictureInPictureActive,
                  !controller.isPictureInPictureSuspended,
                  let adapter = Self.object(controller, selector: "platformAdapter"),
                  let proxy = Self.object(adapter, selector: "pegasusProxy") else { return false }
            return adapter === self.adapter && proxy === self.proxy
        }
        if PiPHiddenReferenceMode.suppressesRefreshDriver {
            beginReferenceStartupProtection(isStillActive: isStillActive)
        }
        schedulePostStartTransition(isStillActive: isStillActive)
    }

    // Standby reference path: one type-4 startup window before the existing delayed type-6 submission.
    func beginReferenceStartupProtection(isStillActive: @escaping () -> Bool) {
        guard Thread.isMainThread, PiPHiddenReferenceMode.suppressesRefreshDriver,
              let referenceOwner = PiPHiddenReferenceMode.owner,
              Self.isRequested, !referenceStartupSubmitted, !postStartScheduled,
              isStillActive(), let token = installationID, let adapter, let proxy, let configuration,
              let proxyClass = object_getClass(proxy),
              let update = Self.method(proxyClass, selector: NSSelectorFromString("updatePlaybackStateUsingBlock:"), result: "v", arguments: ["@?"]),
              let state = Self.object(proxy, selector: "playbackState"), let stateClass = object_getClass(state),
              Self.method(stateClass, selector: NSSelectorFromString("setContentType:"), result: "v", arguments: ["q"]) != nil else { return }
        referenceStartupSubmitted = true
        let mutation: StateMutation = { [weak self, weak adapter] currentState in
            guard let self, self.installationID == token, !self.postStartSubmitted,
                  PiPHiddenReferenceMode.owner == referenceOwner, Self.isRequested, isStillActive(),
                  let adapter, (objc_getAssociatedObject(adapter, &Self.associationKey) as? Configuration) === configuration,
                  object_getClass(currentState) === stateClass,
                  let setter = Self.method(stateClass, selector: NSSelectorFromString("setContentType:"), result: "v", arguments: ["q"]) else { return }
            configuration.setRequestedType(4)
            unsafeBitCast(method_getImplementation(setter), to: IntegerSetter.self)(currentState, NSSelectorFromString("setContentType:"), 4)
            AppDebugLogger.logCritical("Hidden reference beta startup protection: value=4, duration=\(Self.postStartTransitionDelay)s after didStart; standby will request value=6; sleep/120/danmaku effects unverified")
        }
        unsafeBitCast(method_getImplementation(update), to: StateUpdater.self)(proxy, NSSelectorFromString("updatePlaybackStateUsingBlock:"), mutation)
    }

    // One post-start transition, not a repair loop. The predicate also checks controller identity.
    func schedulePostStartTransition(delay: TimeInterval = PiPCoexistenceExperiment.postStartTransitionDelay, isStillActive: @escaping () -> Bool) {
        guard Thread.isMainThread, Self.isRequested,
              let token = installationID, configuration != nil, !postStartScheduled else { return }
        postStartScheduled = true
        AppDebugLogger.logCritical("PiP post-start transition scheduled: delay=\(delay)s; \(diagnosticDescription)")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.installationID == token else { return }
            guard Self.isRequested, isStillActive() else {
                self.checkpoint("post-start transition canceled: disabled/inactive/suspended/replaced")
                return
            }
            self.submitPostStartContentType(token: token, isStillActive: isStillActive)
            for offset in [0.25, 0.75, 2.0, 6.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + offset) { [weak self] in
                    guard let self, self.installationID == token else { return }
                    self.checkpoint("post-start submission +\(offset)s; controllerEligible=\(isStillActive())")
                }
            }
        }
    }

    private func submitPostStartContentType(token: UUID, isStillActive: @escaping () -> Bool) {
        let updateSelector = NSSelectorFromString("updatePlaybackStateUsingBlock:")
        let setterSelector = NSSelectorFromString("setContentType:")
        guard let adapter, let proxy, let configuration, installationID == token,
              !postStartSubmitted,
              let proxyClass = object_getClass(proxy),
              let update = Self.method(proxyClass, selector: updateSelector, result: "v", arguments: ["@?"]),
              let state = Self.object(proxy, selector: "playbackState"),
              let stateClass = object_getClass(state),
              Self.method(stateClass, selector: setterSelector, result: "v", arguments: ["q"]) != nil else {
            checkpoint("post-start submission skipped: unsupported runtime")
            return
        }
        postStartSubmitted = true
        checkpoint("post-start submission BEFORE")
        let mutation: StateMutation = { [weak self, weak adapter] currentState in
            guard let self, self.installationID == token,
                  Self.isRequested, isStillActive(), let adapter,
                  (objc_getAssociatedObject(adapter, &Self.associationKey) as? Configuration) === configuration,
                  object_getClass(currentState) === stateClass,
                  let setter = Self.method(stateClass, selector: setterSelector, result: "v", arguments: ["q"]) else { return }
            configuration.setRequestedType(6)
            unsafeBitCast(method_getImplementation(setter), to: IntegerSetter.self)(currentState, setterSelector, 6)
            AppDebugLogger.logCritical("PiP post-start state mutation APPLIED: traceSession=\(configuration.traceID), value=6; remote acceptance unverified")
        }
        unsafeBitCast(method_getImplementation(update), to: StateUpdater.self)(proxy, updateSelector, mutation)
        checkpoint("post-start submission RETURNED; remote acceptance unverified")
    }

    // PG queries respondsToSelector dynamically. Hide the added method from non-participating instances.
    private static func addScopedProvider(to base: AnyClass) -> Bool {
        let providerSelector = NSSelectorFromString("pictureInPictureProxyContentType:")
        if let existing = class_getInstanceMethod(base, providerSelector) {
            return providers.values.contains { $0 == method_getImplementation(existing) }
        }
        let respondsSelector = NSSelectorFromString("respondsToSelector:")
        guard let responds = method(base, selector: respondsSelector, result: "B", arguments: [":"]),
              let encoding = method_getTypeEncoding(responds) else { return false }
        let originalResponds = unsafeBitCast(method_getImplementation(responds), to: RespondsGetter.self)
        let responseBlock: @convention(block) (AnyObject, Selector) -> Bool = { object, selector in
            if selector == providerSelector {
                let configuration = objc_getAssociatedObject(object, &associationKey) as? Configuration
                configuration?.trace("provider respondsToSelector", details: "returning=true")
                return configuration != nil
            }
            return originalResponds(object, respondsSelector, selector)
        }
        let providerBlock: @convention(block) (AnyObject, AnyObject?) -> Int = { object, queriedProxy in
            if let configuration = objc_getAssociatedObject(object, &associationKey) as? Configuration {
                configuration.trace("provider entry", details: "queryMatches=\(queriedProxy === configuration.proxy)")
            }
            guard let configuration = objc_getAssociatedObject(object, &associationKey) as? Configuration else {
                return (queriedProxy as? NSObject).flatMap { contentType(of: $0) } ?? 4
            }
            if configuration.proxy == nil, configuration.followsPlaybackPhase,
               configuration.isObtainingProxy, Thread.isMainThread,
               let queriedProxy = queriedProxy as? NSObject {
                configuration.proxy = queriedProxy
            }
            guard let proxy = configuration.proxy, queriedProxy === proxy else {
                return (queriedProxy as? NSObject).flatMap { contentType(of: $0) } ?? 4
            }
            let providedType = configuration.providedType
            let count = configuration.recordCall()
            if count <= 2 {
                let stack = Thread.callStackSymbols.prefix(12).joined(separator: " <- ")
                AppDebugLogger.logCritical("PiP class-provider CALLED #\(count): returning \(providedType); threadMain=\(Thread.isMainThread); stack=\(stack)")
            }
            return providedType
        }
        let providerIMP = imp_implementationWithBlock(providerBlock)
        let responseIMP = imp_implementationWithBlock(responseBlock)
        guard class_addMethod(base, providerSelector, providerIMP, "q@:@") else {
            imp_removeBlock(providerIMP)
            imp_removeBlock(responseIMP)
            return false
        }
        class_replaceMethod(base, respondsSelector, responseIMP, encoding)
        providers[NSStringFromClass(base)] = providerIMP
        return true
    }

    // Bounded instrumentation only: every wrapper forwards the original arguments exactly once.
    private static func installWriteTrace(adapter: NSObject, proxy: NSObject, state: NSObject, configuration: Configuration) {
        objc_setAssociatedObject(proxy, &traceKey, configuration, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(state, &traceKey, configuration, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        let setterSelector = NSSelectorFromString("setContentType:")
        if let stateClass = object_getClass(state),
           let setter = method(stateClass, selector: setterSelector, result: "v", arguments: ["q"]),
           let encoding = method_getTypeEncoding(setter) {
            let key = "\(NSStringFromClass(stateClass)).setContentType:"
            if !traceHooks.contains(key) {
                let original = unsafeBitCast(method_getImplementation(setter), to: IntegerSetter.self)
                let block: @convention(block) (AnyObject, Int) -> Void = { object, value in
                    let context = (objc_getAssociatedObject(object, &traceKey) as? Configuration)
                        ?? (Thread.current.threadDictionary[threadTraceKey] as? Configuration)
                    context?.trace("setContentType", details: "state=\(Unmanaged.passUnretained(object).toOpaque()), newValue=\(value)", limit: 24)
                    original(object, setterSelector, value)
                }
                class_replaceMethod(stateClass, setterSelector, imp_implementationWithBlock(block), encoding)
                traceHooks.insert(key)
            }
        }
        let adapterHook = installUpdateTrace(owner: adapter, selectorName: "_updateProxyPlaybackState", association: true)
        let proxyHook = installUpdateTrace(owner: proxy, selectorName: "_updatePlaybackStateContentTypeIfNeeded", association: false)
        AppDebugLogger.logCritical("PiP WRITE-TRACE armed: session=\(configuration.traceID), adapterUpdate=\(adapterHook), proxyRecalculate=\(proxyHook), setter=\(object_getClass(state).map(NSStringFromClass) ?? "unknown"); bounded stacks, original arguments/results unchanged; timing may be affected. Restart app to fully clear hooks.")
    }

    private static func installUpdateTrace(owner: NSObject, selectorName: String, association: Bool) -> Bool {
        let selector = NSSelectorFromString(selectorName)
        guard let type = object_getClass(owner),
              let implementation = method(type, selector: selector, result: "v"),
              let encoding = method_getTypeEncoding(implementation) else { return false }
        let key = "\(NSStringFromClass(type)).\(selectorName)"
        if traceHooks.contains(key) { return true }
        let original = unsafeBitCast(method_getImplementation(implementation), to: VoidMethod.self)
        let block: @convention(block) (AnyObject) -> Void = { object in
            let context = (association
                ? objc_getAssociatedObject(object, &associationKey)
                : objc_getAssociatedObject(object, &traceKey)) as? Configuration
            guard let context else { original(object, selector); return }
            let dictionary = Thread.current.threadDictionary
            let previous = dictionary[threadTraceKey]
            dictionary[threadTraceKey] = context
            defer {
                if let previous { dictionary[threadTraceKey] = previous }
                else { dictionary.removeObject(forKey: threadTraceKey) }
            }
            if let proxy = context.proxy, let state = Self.object(proxy, selector: "playbackState") {
                objc_setAssociatedObject(state, &traceKey, context, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            context.trace(selectorName, details: "owner=\(Unmanaged.passUnretained(object).toOpaque())")
            original(object, selector)
        }
        class_replaceMethod(type, selector, imp_implementationWithBlock(block), encoding)
        traceHooks.insert(key)
        return true
    }

    func restore() {
        installationID = nil
        referenceStartupSubmitted = false
        postStartScheduled = false
        postStartSubmitted = false
        defer {
            adapter = nil
            proxy = nil
            configuration = nil
            originalContentType = nil
        }
        guard let adapter else { return }
        let calls = configuration?.callCount ?? 0
        configuration?.endTracing()
        if let proxy {
            objc_setAssociatedObject(proxy, &Self.traceKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if let state = Self.object(proxy, selector: "playbackState") {
                objc_setAssociatedObject(state, &Self.traceKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
        objc_setAssociatedObject(adapter, &Self.associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if let proxy, let previous = originalContentType, Self.contentType(of: proxy) == 6,
           let state = Self.object(proxy, selector: "playbackState"), let type = object_getClass(state),
           let setter = Self.method(type, selector: NSSelectorFromString("setContentType:"), result: "v", arguments: ["q"]) {
            unsafeBitCast(method_getImplementation(setter), to: IntegerSetter.self)(state, NSSelectorFromString("setContentType:"), previous)
        }
        AppDebugLogger.logCritical("PiP class-provider beta disabled for instance: providerCalls=\(calls); adapter isa unchanged; class hooks remain dormant; no remote send/restart. Full runtime-method removal requires app restart.")
    }

    deinit { restore() }

    private static func object(_ owner: NSObject, selector name: String) -> NSObject? {
        let selector = NSSelectorFromString(name)
        guard let type = object_getClass(owner), let method = method(type, selector: selector, result: "@") else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: ObjectGetter.self)(owner, selector)?.takeUnretainedValue() as? NSObject
    }

    private static func contentType(of proxy: NSObject) -> Int? {
        guard let state = object(proxy, selector: "playbackState"), let type = object_getClass(state),
              let getter = method(type, selector: NSSelectorFromString("contentType"), result: "q") else { return nil }
        return unsafeBitCast(method_getImplementation(getter), to: IntegerGetter.self)(state, NSSelectorFromString("contentType"))
    }

    private static func method(_ type: AnyClass, selector: Selector, result: String, arguments: [String] = []) -> Method? {
        guard let method = class_getInstanceMethod(type, selector),
              method_getNumberOfArguments(method) == arguments.count + 2 else { return nil }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        guard String(cString: returnType) == result else { return nil }
        for (index, expected) in arguments.enumerated() {
            guard let type = method_copyArgumentType(method, UInt32(index + 2)) else { return nil }
            let actual = String(cString: type)
            free(type)
            guard actual == expected else { return nil }
        }
        return method
    }
}
