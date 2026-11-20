import AVKit
import Foundation
import ObjectiveC

enum PiPRefreshRequestTrial {
    enum BackgroundMode: String, CaseIterable {
        case visibilityPaused
        case systemDefault
        case explicit120
    }

    static let backgroundModeKey = "pip.refreshRequestTrial.backgroundMode.beta4"
    static let background120Key = "pip.refreshRequestTrial.background120.v1"
    static let content120Key = "pip.refreshRequestTrial.content120.v1"
    static let content60Key = "pip.refreshRequestTrial.content60.v1"
    static let baselineMigrationKey = "pip.refreshRequestTrial.beta4Defaults.v1"
    static let releaseBaselineMigrationKey = "pip.refreshRequestTrial.release112Defaults.v1"
    static let didChangeNotification = Notification.Name("PiPRefreshRequestTrialChanged")
    static var backgroundMode: BackgroundMode {
        BackgroundMode(rawValue: UserDefaults.standard.string(forKey: backgroundModeKey) ?? "") ?? .visibilityPaused
    }
    static var background120: Bool { backgroundMode == .explicit120 }
    static var content120: Bool { UserDefaults.standard.bool(forKey: content120Key) }
    static var baselineContentFPS: Int { UserDefaults.standard.bool(forKey: content60Key) ? 60 : 30 }

    static func migrateDefaultBaselineIfNeeded(isReleaseBuild: Bool = false) {
        let defaults = UserDefaults.standard
        let migrationKey = isReleaseBuild ? releaseBaselineMigrationKey : baselineMigrationKey
        guard !defaults.bool(forKey: migrationKey) else { return }
        defaults.set(false, forKey: background120Key)
        defaults.set(false, forKey: content120Key)
        defaults.set(false, forKey: content60Key)
        defaults.set(BackgroundMode.visibilityPaused.rawValue, forKey: backgroundModeKey)
        defaults.set(true, forKey: migrationKey)
        let build = isReleaseBuild ? "Release" : "Beta4"
        AppDebugLogger.logRuntime("\(build) refresh defaults: backgroundMode=visibilityPaused, content120=false, baselineContentFPS=30; other preferences preserved")
    }

    static func shouldPauseBackgroundDriver(eligible: Bool, isBackground: Bool, visibilityPause: Bool) -> Bool {
        eligible && isBackground && visibilityPause && backgroundMode == .visibilityPaused
    }

    static func select(background: BackgroundMode, contentFPS: Int, content120: Bool = false) {
        let defaults = UserDefaults.standard
        defaults.set(background.rawValue, forKey: backgroundModeKey)
        defaults.set(background == .explicit120, forKey: background120Key)
        defaults.set(contentFPS == 60, forKey: content60Key)
        defaults.set(content120, forKey: content120Key)
        notifyChanged()
    }

    static func requestsBackground120(eligible: Bool) -> Bool {
        eligible && background120
    }

    static func configureContent(_ link: CADisplayLink, maximumFPS: Int) {
        if content120 {
            let target = Float(min(120, maximumFPS))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: target, maximum: target, preferred: target)
        } else {
            // Reset a previous strict range before restoring the selected baseline.
            link.preferredFrameRateRange = .default
            link.preferredFramesPerSecond = min(baselineContentFPS, maximumFPS)
        }
    }

    static var summary: String {
        "backgroundMode=\(backgroundMode.rawValue), background120=\(background120), content120=\(content120), baselineContentFPS=\(baselineContentFPS); requested policy only, not measured system FPS"
    }

    static func notifyChanged() {
        AppDebugLogger.logRuntime("Refresh request trial settings: \(summary)")
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

enum PiPVisibilityRefreshPolicy {
    static let preferenceKey = "pip.experiment.visibilityRefresh"
    static let pauseContentUpdates = false
    static let pauseExtraBackgroundDriver = true
    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: preferenceKey) == nil ? true : defaults.bool(forKey: preferenceKey)
    }

    static func shouldPause(enabled: Bool, eligible: Bool, active: Bool, hidden: Bool,
                            suspended: Bool, stashedOrUnderLock: Bool?, protectedDataUnavailable: Bool) -> Bool {
        enabled && eligible && active
            && (hidden || suspended || stashedOrUnderLock == true || protectedDataUnavailable)
    }
}

// Observe the private signal without changing the system's visibility or playback state.
final class PiPVisibilityObserver {
    private final class Observation {
        let callback: (Bool) -> Void
        init(callback: @escaping (Bool) -> Void) { self.callback = callback }
    }
    private static var associationKey: UInt8 = 0
    private static var installed: [ObjectIdentifier: IMP] = [:]
    private weak var proxy: NSObject?
    private var observation: Observation?

    @discardableResult
    func install(proxy: NSObject, onChange: @escaping (Bool) -> Void) -> Bool {
        precondition(Thread.isMainThread)
        reset()
        guard let cls = object_getClass(proxy), Self.installHook(on: cls) else { return false }
        let observation = Observation(callback: onChange)
        self.proxy = proxy
        self.observation = observation
        objc_setAssociatedObject(proxy, &Self.associationKey, observation, .OBJC_ASSOCIATION_RETAIN)
        for name in ["isStashedOrUnderLock", "stashedOrUnderLock"] {
            let selector = NSSelectorFromString(name)
            guard let getter = class_getInstanceMethod(cls, selector),
                  method_getNumberOfArguments(getter) == 2 else { continue }
            let encoding = Self.encoding(getter, argument: nil)
            if encoding == "B" {
                typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
                onChange(unsafeBitCast(method_getImplementation(getter), to: Getter.self)(proxy, selector))
                break
            } else if encoding == "c" {
                typealias Getter = @convention(c) (AnyObject, Selector) -> Int8
                onChange(unsafeBitCast(method_getImplementation(getter), to: Getter.self)(proxy, selector) != 0)
                break
            }
        }
        return true
    }

    func reset() {
        if let proxy, let observation,
           (objc_getAssociatedObject(proxy, &Self.associationKey) as? Observation) === observation {
            objc_setAssociatedObject(proxy, &Self.associationKey, nil, .OBJC_ASSOCIATION_RETAIN)
        }
        proxy = nil
        observation = nil
    }

    static func proxy(for controller: NSObject) -> NSObject? {
        func object(_ owner: NSObject, _ name: String) -> NSObject? {
            let selector = NSSelectorFromString(name)
            guard let cls = object_getClass(owner), let method = class_getInstanceMethod(cls, selector),
                  method_getNumberOfArguments(method) == 2, encoding(method, argument: nil) == "@" else { return nil }
            typealias Getter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
            return unsafeBitCast(method_getImplementation(method), to: Getter.self)(owner, selector)?.takeUnretainedValue() as? NSObject
        }
        guard let adapter = object(controller, "platformAdapter") else { return nil }
        return object(adapter, "pegasusProxy")
    }

    private static func deliver(_ owner: NSObject, _ value: Bool) {
        guard let observation = objc_getAssociatedObject(owner, &associationKey) as? Observation else { return }
        DispatchQueue.main.async { [weak owner, weak observation] in
            guard let owner, let observation,
                  (objc_getAssociatedObject(owner, &associationKey) as? Observation) === observation else { return }
            observation.callback(value)
        }
    }

    private static func encoding(_ method: Method, argument: UInt32?) -> String {
        guard let value = argument.map({ method_copyArgumentType(method, $0) }) ?? method_copyReturnType(method) else { return "" }
        defer { free(value) }
        return String(cString: value)
    }

    private static func installHook(on cls: AnyClass) -> Bool {
        let selector = NSSelectorFromString("_setStashedOrUnderLock:reason:")
        guard let method = class_getInstanceMethod(cls, selector), method_getNumberOfArguments(method) == 4,
              encoding(method, argument: nil) == "v" else { return false }
        let identity = ObjectIdentifier(cls)
        if let installedIMP = installed[identity] { return method_getImplementation(method) == installedIMP }
        let original = method_getImplementation(method)
        let boolean = encoding(method, argument: 2)
        let reason = encoding(method, argument: 3)
        let replacement: IMP
        switch (boolean, reason) {
        case ("B", "q"):
            typealias Original = @convention(c) (AnyObject, Selector, Bool, Int) -> Void
            let call = unsafeBitCast(original, to: Original.self)
            let block: @convention(block) (NSObject, Bool, Int) -> Void = { owner, value, reason in
                call(owner, selector, value, reason)
                deliver(owner, value)
            }
            replacement = imp_implementationWithBlock(block)
        case ("c", "q"):
            typealias Original = @convention(c) (AnyObject, Selector, Int8, Int) -> Void
            let call = unsafeBitCast(original, to: Original.self)
            let block: @convention(block) (NSObject, Int8, Int) -> Void = { owner, value, reason in
                call(owner, selector, value, reason)
                deliver(owner, value != 0)
            }
            replacement = imp_implementationWithBlock(block)
        case ("B", "@"):
            typealias Original = @convention(c) (AnyObject, Selector, Bool, AnyObject?) -> Void
            let call = unsafeBitCast(original, to: Original.self)
            let block: @convention(block) (NSObject, Bool, AnyObject?) -> Void = { owner, value, reason in
                call(owner, selector, value, reason)
                deliver(owner, value)
            }
            replacement = imp_implementationWithBlock(block)
        case ("c", "@"):
            typealias Original = @convention(c) (AnyObject, Selector, Int8, AnyObject?) -> Void
            let call = unsafeBitCast(original, to: Original.self)
            let block: @convention(block) (NSObject, Int8, AnyObject?) -> Void = { owner, value, reason in
                call(owner, selector, value, reason)
                deliver(owner, value != 0)
            }
            replacement = imp_implementationWithBlock(block)
        default:
            return false
        }
        if !class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)) {
            method_setImplementation(method, replacement)
        }
        installed[identity] = replacement
        return true
    }

    deinit { reset() }
}

// Scoped to the controller being constructed; ordinary adapters retain their getter.
enum PiPHiddenReferenceControls {
    static let proxyHiddenStyle = 5
    private static var associationKey: UInt8 = 0
    private static var installed: Set<ObjectIdentifier> = []
    private typealias Getter = @convention(c) (AnyObject, Selector) -> Int
    private final class Construction {
        var adapter: NSObject?
        var hits = 0
    }
    private static var construction: Construction?

    static func hidesDuringNativeConstruction(systemMajorVersion: Int) -> Bool {
        PiPNativePostStartTrial.supportsSystemMajorVersion(systemMajorVersion)
            && supportsMaintainedHiding(systemMajorVersion: systemMajorVersion)
    }

    static func makeNativeController(source: AVPictureInPictureController.ContentSource, systemMajorVersion: Int) -> AVPictureInPictureController? {
        if hidesDuringNativeConstruction(systemMajorVersion: systemMajorVersion) {
            // Restore released iOS16+ control initialization without installing an early content-type provider.
            if let styled = makeController(source: source) { return styled }
            AppDebugLogger.logCritical("PiP construction styling unavailable; using native controller")
        }
        return AVPictureInPictureController(contentSource: source)
    }

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
        AppDebugLogger.logCritical("Hidden reference controls applied DURING construction: _proxyControlsStyle=5, hits=\(context.hits); override RELEASED after construction; native content type unchanged by controls policy; animation/controls require device validation")
        return value
    }

    static func clear(adapter: NSObject) {
        objc_setAssociatedObject(adapter, &associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func supportsMaintainedHiding(systemMajorVersion: Int) -> Bool {
        systemMajorVersion >= 16
    }

    static func maintainHidden(adapter: NSObject) -> Bool {
        guard Thread.isMainThread, let adapterClass = object_getClass(adapter),
              install(adapterClass: adapterClass) else { return false }
        objc_setAssociatedObject(adapter, &associationKey, NSNumber(value: true), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return true
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
            if objc_getAssociatedObject(target, &associationKey) != nil { return proxyHiddenStyle }
            if Thread.isMainThread, let context = construction {
                if context.adapter == nil {
                    context.adapter = target
                    objc_setAssociatedObject(target, &associationKey, NSNumber(value: true), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
                if context.adapter === target {
                    context.hits += 1
                    return proxyHiddenStyle
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

enum PiPCoexistencePreferences {
    static let migrationKey = "pip.migration.retiredCoexistencePreferences.v1"
    static let retiredKeys = [
        "pip.experiment.coexistenceProvider6", "pip.experiment.hiddenVideoCallReference",
        "pip.experiment.hidden.request120", "pip.experiment.hidden.animateContent",
        "pip.experiment.hidden.minimumSurface"
    ]

    static func migrate(_ defaults: UserDefaults = .standard) -> [String] {
        guard !defaults.bool(forKey: migrationKey) else { return [] }
        let present = retiredKeys.filter { defaults.object(forKey: $0) != nil }
        for key in retiredKeys { defaults.removeObject(forKey: key) }
        defaults.set(true, forKey: migrationKey)
        return present
    }
}

// Isolated trial: keep native construction until the successful-start callback.
enum PiPNativePostStartTrial {
    static let isEnabled = true
    static func supportsSystemMajorVersion(_ major: Int) -> Bool {
        isEnabled && (15...27).contains(major)
    }
}

// Content refresh remains independent of the private coexistence session.
enum PiPNativeContentRefreshPolicy {
    static let framesPerSecond = 30
    static func supports(systemMajorVersion: Int, isPlayerLayer: Bool, isPiPOnly: Bool) -> Bool {
        PiPNativePostStartTrial.supportsSystemMajorVersion(systemMajorVersion) && !isPlayerLayer && isPiPOnly
    }
}

enum PiPHiddenReferenceOptions {
    // Fixed to the device-tested content-only policy; old switch preferences are ignored.
    static let requests120 = false
    static let animatesContent = true
    static let preservesMinimumSurface = false
    static let contentFramesPerSecond = 30
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
        guard !PiPNativePostStartTrial.supportsSystemMajorVersion(major) else { return false }
        // iOS 15 retains the native VideoCall content host and startup used by 1.1.0.
        return (16...27).contains(major)
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

// Private runtime integration. Restart the process to remove added methods completely.
final class PiPCoexistenceExperiment {
    static let preferenceKey = "pip.experiment.coexistenceProvider6"
    private static var associationKey: UInt8 = 0
    private static var providers: [String: IMP] = [:]
    private typealias ObjectGetter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    private typealias IntegerGetter = @convention(c) (AnyObject, Selector) -> Int
    private typealias IntegerSetter = @convention(c) (AnyObject, Selector, Int) -> Void
    private typealias RespondsGetter = @convention(c) (AnyObject, Selector, Selector) -> Bool
    private typealias StateMutation = @convention(block) (AnyObject) -> Void
    private typealias StateUpdater = @convention(c) (AnyObject, Selector, StateMutation) -> Void

    private final class Configuration: NSObject {
        private weak var proxy: NSObject?
        private let lock = NSLock()
        private var calls = 0
        private var requestedType = 6
        private let followsPlaybackPhase: Bool
        private var isObtainingProxy = false
        let traceID = UUID().uuidString
        init(proxy: NSObject?, followsPlaybackPhase: Bool = false, initialType: Int = 4) {
            self.proxy = proxy
            self.followsPlaybackPhase = followsPlaybackPhase
            requestedType = followsPlaybackPhase ? initialType : 6
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
        func beginProxyLookup() {
            lock.lock()
            isObtainingProxy = true
            lock.unlock()
        }
        func finishProxyLookup(_ candidate: NSObject?) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            isObtainingProxy = false
            guard let candidate, proxy == nil || proxy === candidate else { return false }
            proxy = candidate
            return true
        }
        func typeForQuery(_ candidate: NSObject?) -> Int? {
            lock.lock()
            defer { lock.unlock() }
            guard let candidate else { return nil }
            if proxy == nil, isObtainingProxy, followsPlaybackPhase, Thread.isMainThread { proxy = candidate }
            guard candidate === proxy else { return nil }
            calls += 1
            return followsPlaybackPhase ? requestedType : 6
        }
        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return calls
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
    private var nativePostStartSession = false
    private var postStartWorkItems: [DispatchWorkItem] = []
    private var preparationID: UUID?
    private weak var preparationController: AVPictureInPictureController?
    private var transitionRunID: UUID?
    private var mutationID: UUID?
    private var transitionDeadline: TimeInterval?
    private var preparationCount = 0
    private var preparationMayRetry = true
    private var preparationAdapterIdentity: ObjectIdentifier?
    private var preparationProxyIdentity: ObjectIdentifier?
    private var transitionCheckCount = 0
    private var transitionAttemptCount = 0
    private var transitionWriteCount = 0
    private var lastLocalReadback: Int?
    private var transitionStage = "idle"
    private var sessionEligibility: (() -> Bool)?
    private weak var maintainedControlsAdapter: NSObject?
    var onPostStartStateApplied: (() -> Void)?
    private var shouldContinueExperiment: Bool {
        (Self.isRequested || nativePostStartSession) && (sessionEligibility?() ?? true)
    }
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
        prepared.beginProxyLookup()
        objc_setAssociatedObject(candidate, &Self.associationKey, prepared, .OBJC_ASSOCIATION_RETAIN)
        let candidateProxy = obtainProxy()
        guard prepared.finishProxyLookup(candidateProxy), let candidateProxy else {
            objc_setAssociatedObject(candidate, &Self.associationKey, nil, .OBJC_ASSOCIATION_RETAIN)
            return false
        }
        let succeeded = install(adapter: candidate, proxy: candidateProxy, prepared: prepared)
        if !succeeded {
            objc_setAssociatedObject(candidate, &Self.associationKey, nil, .OBJC_ASSOCIATION_RETAIN)
        }
        if succeeded {
            AppDebugLogger.logCritical("Hidden reference EARLY provider prepared before controls/automatic-start: initialType=4; provider follows 4->6 after startup; \(diagnosticDescription). Cold animation, controls and independent 120Hz require device validation.")
        }
        return succeeded
    }

    var diagnosticDescription: String {
        let evidence = "stage=\(transitionStage), preparationAttempts=\(preparationCount)/3, checks=\(transitionCheckCount)/4, updaterAttempts=\(transitionAttemptCount)/3, actualWrites=\(transitionWriteCount), mutationApplied=\(postStartSubmitted), localReadback=\(lastLocalReadback.map(String.init) ?? "unknown"), systemCoexistence=unverified"
        guard let adapter, let proxy, let configuration else { return "coexistenceProvider=false, \(evidence)" }
        let delegate = Self.object(proxy, selector: "delegate")
        return "coexistenceProvider=true, nativePostStart=\(nativePostStartSession), originalType=\(originalContentType.map(String.init) ?? "unknown"), variant=bounded-startup-\(Self.postStartTransitionDelay)s, traceSession=\(configuration.traceID), providerCalls=\(configuration.callCount), postStartScheduled=\(postStartScheduled), postStartSubmitted=\(postStartSubmitted), requestedContentType=6, localContentType=\(Self.contentType(of: proxy).map(String.init) ?? "unknown"), adapterClass=\(NSStringFromClass(type(of: adapter))), proxyDelegateMatches=\(delegate === adapter), \(evidence)"
    }

    @discardableResult
    func install(adapter candidate: NSObject, proxy candidateProxy: NSObject) -> Bool {
        install(adapter: candidate, proxy: candidateProxy, prepared: nil)
    }

    private func install(adapter candidate: NSObject, proxy candidateProxy: NSObject, prepared: Configuration?, afterNativeStart: Bool = false) -> Bool {
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
              previousType == 4 || (afterNativeStart && previousType == 3) || (prepared != nil && previousType == 6),
              Self.addScopedProvider(to: base) else {
            AppDebugLogger.log("PiP class-provider beta skipped: unsupported signature, original provider or content type")
            return false
        }

        let token = UUID()
        let configuration = prepared ?? Configuration(proxy: candidateProxy)
        self.configuration = configuration
        installationID = token
        originalContentType = afterNativeStart || prepared == nil ? previousType : 4
        adapter = candidate
        proxy = candidateProxy
        objc_setAssociatedObject(candidate, &Self.associationKey, configuration, .OBJC_ASSOCIATION_RETAIN)
        let setterIMP = unsafeBitCast(method_getImplementation(setter), to: IntegerSetter.self)
        let mutation: StateMutation = { [weak candidate] currentState in
            guard let candidate,
                  (objc_getAssociatedObject(candidate, &Self.associationKey) as? Configuration) === configuration,
                  object_getClass(currentState) === stateClass else { return }
            setterIMP(currentState, setterSelector, configuration.providedType)
        }
        if !afterNativeStart {
            unsafeBitCast(method_getImplementation(update), to: StateUpdater.self)(candidateProxy, updateSelector, mutation)
        }
        AppDebugLogger.logCritical("PiP class-provider prepared \(afterNativeStart ? "AFTER native didStart; no initial state write" : "BEFORE start"): no isa change; \(diagnosticDescription). Remote acceptance, coexistence and 120Hz unverified; source/size/audio/frame-rate unchanged.")
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

    func schedulePostStartUpdateIfRequested(controller: AVPictureInPictureController, useNativePostStart: Bool = false,
                                           isSessionEligible: @escaping () -> Bool = { true }) {
        guard controller.isPictureInPictureActive else { return }
        if useNativePostStart {
            guard preparationID == nil || preparationController !== controller else { return }
            if adapter != nil { restore() }
            sessionEligibility = isSessionEligible
            let token = UUID()
            preparationID = token
            preparationController = controller
            preparationCount = 0
            transitionDeadline = ProcessInfo.processInfo.systemUptime + 9
            prepareNativeSession(controller: controller, token: token)
            return
        }
        sessionEligibility = isSessionEligible
        schedulePreparedTransition(controller: controller)
    }

    private func prepareNativeSession(controller: AVPictureInPictureController, token: UUID) {
        guard preparationID == token, preparationController === controller,
              sessionEligibility?() != false,
              controller.isPictureInPictureActive, preparationCount < 3,
              ProcessInfo.processInfo.systemUptime < (transitionDeadline ?? 0) else { return }
        preparationCount += 1
        transitionStage = "preparing"
        if prepareAfterNativeStart(controller: controller) {
            schedulePreparedTransition(controller: controller)
        } else if preparationMayRetry && preparationCount < 3 {
            transitionStage = "preparation-retry-scheduled"
            checkpoint("native preparation unavailable; bounded retry, no PiP restart")
            let work = DispatchWorkItem { [weak self, weak controller] in
                guard let self, let controller else { return }
                self.prepareNativeSession(controller: controller, token: token)
            }
            postStartWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + (preparationCount == 1 ? 0.5 : 1.0), execute: work)
        } else {
            transitionStage = "preparation-exhausted"
            AppDebugLogger.logCritical("PiP coexistence preparation exhausted: \(diagnosticDescription); native PiP preserved; system coexistence NOT confirmed")
        }
    }

    private func schedulePreparedTransition(controller: AVPictureInPictureController) {
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

    private func prepareAfterNativeStart(controller: AVPictureInPictureController) -> Bool {
        preparationMayRetry = true
        guard Thread.isMainThread, controller.isPictureInPictureActive else { return false }
        guard let candidate = Self.object(controller, selector: "platformAdapter"),
              let candidateProxy = Self.object(candidate, selector: "pegasusProxy") else {
            AppDebugLogger.logCritical("Native post-start coexistence skipped: runtime unavailable; native PiP left running")
            return false
        }
        if let identity = preparationAdapterIdentity, identity != ObjectIdentifier(candidate) {
            preparationMayRetry = false
            return false
        }
        if let identity = preparationProxyIdentity, identity != ObjectIdentifier(candidateProxy) {
            preparationMayRetry = false
            return false
        }
        preparationAdapterIdentity = ObjectIdentifier(candidate)
        preparationProxyIdentity = ObjectIdentifier(candidateProxy)
        if nativePostStartSession, adapter === candidate, proxy === candidateProxy,
           installationID != nil { return true }
        if adapter != nil { restore() }
        guard let previousType = Self.contentType(of: candidateProxy) else { return false }
        guard previousType == 3 || previousType == 4 || previousType == 6 else {
            preparationMayRetry = false
            AppDebugLogger.logCritical("Native coexistence preparation rejected unknown contentType=\(previousType); no overwrite, restart or retry")
            return false
        }
        AppDebugLogger.logCritical("Native post-start BEFORE provider: active=\(controller.isPictureInPictureActive), suspended=\(controller.isPictureInPictureSuspended), systemContentType=\(previousType); no content type was forced before didStart")
        let prepared = Configuration(proxy: candidateProxy, followsPlaybackPhase: true, initialType: previousType)
        nativePostStartSession = true
        guard install(adapter: candidate, proxy: candidateProxy, prepared: prepared, afterNativeStart: true) else {
            preparationMayRetry = false
            nativePostStartSession = false
            AppDebugLogger.logCritical("Native post-start coexistence skipped: unsupported type/signature; native PiP left running, systemContentType=\(previousType)")
            return false
        }
        return true
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

    // Four startup checks, at most three updater calls; no permanent repair loop.
    func schedulePostStartTransition(delay: TimeInterval = PiPCoexistenceExperiment.postStartTransitionDelay, isStillActive: @escaping () -> Bool) {
        guard Thread.isMainThread, shouldContinueExperiment,
              let token = installationID, configuration != nil, !postStartScheduled else { return }
        postStartScheduled = true
        let run = UUID()
        transitionRunID = run
        transitionStage = "scheduled"
        let deadline = transitionDeadline ?? (ProcessInfo.processInfo.systemUptime + max(0, delay) + 7.5)
        transitionDeadline = deadline
        AppDebugLogger.logCritical("PiP post-start transition SCHEDULED: firstDelay=\(delay)s, checks<=4, updaterAttempts<=3, startupWindow<=9s; \(diagnosticDescription)")
        for offset in [0.0, 1.5, 4.0, 7.0] {
            let interval = max(0, delay) + offset
            guard ProcessInfo.processInfo.systemUptime + interval < deadline else { continue }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.installationID == token, self.transitionRunID == run,
                      self.shouldContinueExperiment, ProcessInfo.processInfo.systemUptime <= deadline else { return }
                self.transitionCheckCount += 1
                guard isStillActive() else {
                    self.transitionStage = "check-deferred-ineligible"
                    self.checkpoint("startup check skipped: inactive/suspended/replaced; remaining checks are bounded")
                    return
                }
                self.lastLocalReadback = self.proxy.flatMap { Self.contentType(of: $0) }
                if self.lastLocalReadback == 6 {
                    self.transitionStage = "local-readback-6"
                    self.checkpoint("LOCAL READBACK 6; no redundant write; system coexistence remains unverified")
                    return
                }
                guard self.transitionAttemptCount < 3 else {
                    self.transitionStage = "attempts-exhausted"
                    self.checkpoint("startup attempts exhausted; no restart or infinite retry")
                    return
                }
                guard let type = self.lastLocalReadback, type == 3 || type == 4 else {
                    self.transitionStage = "unsupported-local-type"
                    self.checkpoint("unknown content type left unchanged")
                    return
                }
                self.submitPostStartContentType(token: token, isStillActive: isStillActive)
            }
            postStartWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
        }
        let finish = DispatchWorkItem { [weak self] in
            guard let self, self.installationID == token, self.transitionRunID == run else { return }
            self.mutationID = nil
            self.transitionRunID = nil
            if isStillActive() { self.lastLocalReadback = self.proxy.flatMap { Self.contentType(of: $0) } }
            self.transitionStage = isStillActive() && self.lastLocalReadback == 6
                ? "window-ended-local-6" : "window-ended-unconfirmed"
            self.checkpoint("STARTUP WINDOW ENDED; no further updater calls; system coexistence remains unverified")
        }
        postStartWorkItems.append(finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - ProcessInfo.processInfo.systemUptime), execute: finish)
    }

    private func submitPostStartContentType(token: UUID, isStillActive: @escaping () -> Bool) {
        let updateSelector = NSSelectorFromString("updatePlaybackStateUsingBlock:")
        let setterSelector = NSSelectorFromString("setContentType:")
        guard let adapter, let proxy, let configuration, installationID == token,
              let proxyClass = object_getClass(proxy),
              let update = Self.method(proxyClass, selector: updateSelector, result: "v", arguments: ["@?"]),
              let state = Self.object(proxy, selector: "playbackState"),
              let stateClass = object_getClass(state),
              Self.method(stateClass, selector: setterSelector, result: "v", arguments: ["q"]) != nil else {
            checkpoint("post-start submission skipped: unsupported runtime")
            return
        }
        transitionAttemptCount += 1
        let attempt = UUID()
        mutationID = attempt
        transitionStage = "updater-invoked"
        checkpoint("post-start submission BEFORE")
        let mutation: StateMutation = { [weak self, weak adapter] currentState in
            guard Thread.isMainThread, let self, self.installationID == token, self.mutationID == attempt,
                  self.shouldContinueExperiment, isStillActive(), let adapter,
                  (objc_getAssociatedObject(adapter, &Self.associationKey) as? Configuration) === configuration,
                  object_getClass(currentState) === stateClass,
                  let setter = Self.method(stateClass, selector: setterSelector, result: "v", arguments: ["q"]) else { return }
            configuration.setRequestedType(6)
            unsafeBitCast(method_getImplementation(setter), to: IntegerSetter.self)(currentState, setterSelector, 6)
            self.postStartSubmitted = true
            self.transitionWriteCount += 1
            self.transitionStage = "mutation-applied"
            AppDebugLogger.logCritical("PiP post-start state mutation APPLIED: traceSession=\(configuration.traceID), value=6; remote acceptance unverified")
            DispatchQueue.main.async { [weak self] in
                guard let self, self.installationID == token else { return }
                self.onPostStartStateApplied?()
            }
        }
        unsafeBitCast(method_getImplementation(update), to: StateUpdater.self)(proxy, updateSelector, mutation)
        checkpoint("updater RETURNED; this is not evidence of mutation or remote acceptance")
        let verification = DispatchWorkItem { [weak self] in
            guard let self, self.installationID == token, self.mutationID == attempt else { return }
            self.lastLocalReadback = self.proxy.flatMap { Self.contentType(of: $0) }
            self.transitionStage = self.lastLocalReadback == 6 ? "local-readback-6" : "local-readback-not-6"
            self.mutationID = nil
            self.checkpoint("LOCAL READBACK after updater; system coexistence requires separate competing-PiP test/system logs")
        }
        postStartWorkItems.append(verification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: verification)
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
                return configuration != nil
            }
            return originalResponds(object, respondsSelector, selector)
        }
        let providerBlock: @convention(block) (AnyObject, AnyObject?) -> Int = { object, queriedProxy in
            let candidate = queriedProxy as? NSObject
            let configuration = objc_getAssociatedObject(object, &associationKey) as? Configuration
            return configuration?.typeForQuery(candidate) ?? candidate.flatMap { contentType(of: $0) } ?? 4
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

    func maintainControlsHidden(controller: AVPictureInPictureController, systemMajorVersion: Int, resubmitAfterTransition: Bool = false) -> Bool {
        guard Thread.isMainThread,
              PiPHiddenReferenceControls.supportsMaintainedHiding(systemMajorVersion: systemMajorVersion),
              controller.isPictureInPictureActive,
              let candidate = Self.object(controller, selector: "platformAdapter"),
              let candidateProxy = Self.object(candidate, selector: "pegasusProxy"),
              Self.object(candidateProxy, selector: "delegate") === candidate,
              let proxyClass = object_getClass(candidateProxy),
              let getter = Self.method(proxyClass, selector: NSSelectorFromString("controlsStyle"), result: "q") else { return false }
        let setterSelector = NSSelectorFromString("setControlsStyle:animated:withCompletionHandler:")
        guard let setter = Self.method(proxyClass, selector: setterSelector, result: "v", arguments: ["q", "B", "@?"])
            ?? Self.method(proxyClass, selector: setterSelector, result: "v", arguments: ["q", "c", "@?"]) else {
            AppDebugLogger.logCritical("PiP proxy controls hiding skipped: unsupported setter signature; native controller unchanged")
            return false
        }
        if let previous = maintainedControlsAdapter, previous !== candidate {
            PiPHiddenReferenceControls.clear(adapter: previous)
        }
        let applied = PiPHiddenReferenceControls.maintainHidden(adapter: candidate)
        guard applied else { return false }
        maintainedControlsAdapter = candidate
        let getterIMP = unsafeBitCast(method_getImplementation(getter), to: IntegerGetter.self)
        let getterSelector = NSSelectorFromString("controlsStyle")
        let before = getterIMP(candidateProxy, getterSelector)
        let requested = PiPHiddenReferenceControls.proxyHiddenStyle
        if before != requested || resubmitAfterTransition {
            // The proxy caches its own style; an adapter getter or unchanged outer value does not send it.
            typealias ControlsSetter = @convention(c) (AnyObject, Selector, Int, Bool, AnyObject?) -> Void
            unsafeBitCast(method_getImplementation(setter), to: ControlsSetter.self)(candidateProxy, setterSelector, requested, false, nil)
            let after = getterIMP(candidateProxy, getterSelector)
            AppDebugLogger.logCritical("PiP PROXY controls hiding submitted: previous=\(before), requested=\(requested), after=\(after), resubmittedAfterTransition=\(resubmitAfterTransition), animated=false; proxy readback only, remote controls require device validation")
            return after == requested
        }
        return true
    }

    func clearMaintainedControls() {
        if let maintainedControlsAdapter { PiPHiddenReferenceControls.clear(adapter: maintainedControlsAdapter) }
        maintainedControlsAdapter = nil
    }

    static func setControlsStyleIfSupported(_ style: Int, on controller: AVPictureInPictureController) -> Bool {
        let selector = NSSelectorFromString("setControlsStyle:")
        guard let type = object_getClass(controller),
              let setter = method(type, selector: selector, result: "v", arguments: ["q"]) else { return false }
        unsafeBitCast(method_getImplementation(setter), to: IntegerSetter.self)(controller, selector, style)
        return true
    }

    static func controlsStyle(of controller: AVPictureInPictureController) -> Int? {
        let selector = NSSelectorFromString("controlsStyle")
        guard let type = object_getClass(controller),
              let getter = method(type, selector: selector, result: "q") else { return nil }
        return unsafeBitCast(method_getImplementation(getter), to: IntegerGetter.self)(controller, selector)
    }

    func cancelPendingTransition() {
        for work in postStartWorkItems { work.cancel() }
        postStartWorkItems.removeAll()
        preparationID = nil
        preparationController = nil
        preparationAdapterIdentity = nil
        preparationProxyIdentity = nil
        transitionRunID = nil
        mutationID = nil
        transitionDeadline = nil
        sessionEligibility = nil
        transitionStage = "canceled"
        installationID = nil
        postStartScheduled = false
    }

    func restore() {
        cancelPendingTransition()
        clearMaintainedControls()
        nativePostStartSession = false
        installationID = nil
        referenceStartupSubmitted = false
        postStartScheduled = false
        postStartSubmitted = false
        preparationCount = 0
        transitionCheckCount = 0
        transitionAttemptCount = 0
        transitionWriteCount = 0
        lastLocalReadback = nil
        defer {
            adapter = nil
            proxy = nil
            configuration = nil
            originalContentType = nil
        }
        guard let adapter else { return }
        let calls = configuration?.callCount ?? 0
        objc_setAssociatedObject(adapter, &Self.associationKey, nil, .OBJC_ASSOCIATION_RETAIN)
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
