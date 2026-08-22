import SwiftUI
import UIKit
import QuartzCore

enum GlobalRefresh2LaunchCelebration {
    static let didFinishNotification = Notification.Name("globalRefresh.launchCelebration.didFinish")

    private static let seenKey = "globalRefresh.launchCelebration.seen.1.1.0.tutorial-v7"
    private static var latestChangelogSeenKey: String {
        "globalRefresh.latestChangelog.seen.\(L10n.versionDisplay)"
    }
    private(set) static var isPresenting = false

    static var shouldPresent: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-GR1LaunchCelebrationPreview")
            || ProcessInfo.processInfo.environment["GR1_LAUNCH_CELEBRATION_PREVIEW"] == "1" {
            return true
        }
#endif
        return !UserDefaults.standard.bool(forKey: seenKey)
    }

    static var shouldDeferFirstRunAuthorization: Bool {
        shouldPresent || isPresenting
    }

    static var shouldPresentLatestChangelog: Bool {
#if DEBUG
        if ProcessInfo.processInfo.environment["GR1_LATEST_CHANGELOG_PREVIEW"] == "1" {
            return true
        }
#endif
        return !UserDefaults.standard.bool(forKey: latestChangelogSeenKey)
    }

    static func markLatestChangelogPresented() {
        UserDefaults.standard.set(true, forKey: latestChangelogSeenKey)
    }

    static func markPresented() {
        isPresenting = true
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    static func markFinished() {
        guard isPresenting else { return }
        isPresenting = false
        NotificationCenter.default.post(name: didFinishNotification, object: nil)
    }
}

struct GlobalRefresh2LaunchCelebrationView: View {
    let onFinished: () -> Void

    private enum Page: Equatable {
        case celebration
        case tutorial
    }

    @State private var isContentVisible = false
    @State private var frameTimestamp = CACurrentMediaTime()
    @State private var startedAt: TimeInterval?
    @State private var leavingAt: TimeInterval?
    @State private var hasFinished = false
    @State private var page: Page = .celebration
    @State private var scheduledPageChange: DispatchWorkItem?
    @State private var scheduledFinish: DispatchWorkItem?

    var body: some View {
        let exitProgress = leavingAt.map {
            CGFloat(min(1, max(0, (frameTimestamp - $0) / 0.34)))
        } ?? 0
        let pageStart = startedAt ?? frameTimestamp
        let pageElapsed = max(0, frameTimestamp - pageStart)
        let pageDuration = page == .celebration ? 5.0 : 7.7
        let pageProgress = min(1, pageElapsed / pageDuration)

        GeometryReader { proxy in
            ZStack {
                LaunchDisplayLinkDriver(timestamp: $frameTimestamp)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)

                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                Group {
                    if page == .celebration {
                        celebrationPage(proxy: proxy)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.985)),
                                removal: .opacity.combined(with: .scale(scale: 1.025))
                            ))
                    } else {
                        LaunchPiPTutorialPage(
                            elapsed: pageElapsed,
                            progress: CGFloat(pageProgress),
                            availableHeight: proxy.size.height,
                            topInset: proxy.safeAreaInsets.top,
                            bottomInset: proxy.safeAreaInsets.bottom
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.975)))
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { handleTap() }
        }
        .opacity(1 - exitProgress)
        .scaleEffect(1 + exitProgress * 0.025)
        .onAppear { start() }
        .onDisappear {
            scheduledPageChange?.cancel()
            scheduledFinish?.cancel()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(L10n.text("全局高刷 \(L10n.versionDisplay)", "Global Refresh \(L10n.versionDisplay)")))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(L10n.text("轻触继续或跳过启动动画", "Tap to continue or skip the launch animation")))
    }

    private func celebrationPage(proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Text(L10n.text("全局高刷悬浮窗", "Global Refresh PiP"))
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .tracking(0.8)
                .padding(.top, max(proxy.safeAreaInsets.top + 26, 54))

            Spacer(minLength: 20)

            LaunchPiPStatusAnimation(time: frameTimestamp)
                .frame(width: 190, height: 142)
                .scaleEffect(isContentVisible ? 1 : 0.68)
                .opacity(isContentVisible ? 1 : 0)

            Text(L10n.text("全局高刷", "Global Refresh"))
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundColor(Color(UIColor.label))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.top, 22)

            Text(L10n.versionDisplay)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Color(UIColor.systemBlue))
                .padding(.horizontal, 18)
                .frame(minHeight: 42)
                .background(launchVersionBackground)
                .padding(.top, 12)

            Text(L10n.text("正在准备高刷体验", "Preparing your refresh experience"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .padding(.top, 18)

            Spacer(minLength: 24)

            LaunchPageFooter(
                progress: CGFloat(min(1, max(0, (frameTimestamp - (startedAt ?? frameTimestamp)) / 5.0))),
                selectedPage: 0,
                hint: L10n.text("轻触继续", "Tap to continue")
            )
            .padding(.bottom, max(proxy.safeAreaInsets.bottom + 24, 42))
        }
        .padding(.horizontal, 24)
    }

    private var launchVersionBackground: some View {
        let shape = Capsule()
        return shape
            .fill(Color(UIColor.systemBlue).opacity(0.1))
            .overlay(shape.strokeBorder(Color(UIColor.systemBlue).opacity(0.26), lineWidth: 1))
    }

    private func start() {
        withAnimation(.interpolatingSpring(mass: 0.72, stiffness: 210, damping: 24, initialVelocity: 0.08)) {
            isContentVisible = true
        }
        startedAt = CACurrentMediaTime()
        let workItem = DispatchWorkItem { advanceToTutorial() }
        scheduledPageChange = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: workItem)
    }

    private func handleTap() {
        if page == .celebration {
            advanceToTutorial()
        } else {
            finish()
        }
    }

    private func advanceToTutorial() {
        guard !hasFinished, page == .celebration else { return }
        scheduledPageChange?.cancel()
        startedAt = CACurrentMediaTime()
        withAnimation(.interpolatingSpring(mass: 0.82, stiffness: 175, damping: 23, initialVelocity: 0.04)) {
            page = .tutorial
        }
        let workItem = DispatchWorkItem { finish() }
        scheduledFinish = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.7, execute: workItem)
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        scheduledPageChange?.cancel()
        scheduledFinish?.cancel()
        leavingAt = CACurrentMediaTime()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            onFinished()
        }
    }
}

private struct LaunchPiPTutorialPage: View {
    let elapsed: TimeInterval
    let progress: CGFloat
    let availableHeight: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func smooth(_ value: Double) -> Double {
        let x = clamp(value)
        return x * x * (3 - 2 * x)
    }

    private func segment(_ start: Double, _ end: Double) -> Double {
        smooth((elapsed - start) / (end - start))
    }

    var body: some View {
        let stageHeight = min(600, max(410, availableHeight - topInset - bottomInset - 150))

        VStack(spacing: 0) {
            Text(L10n.text("隐藏悬浮窗，只需三步", "Hide PiP in three steps"))
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(Color(UIColor.label))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .padding(.top, max(topInset + 18, 48))

            Text(L10n.text("打开、吸附到侧边，再缩小到 0.1pt", "Open, dock it to the side, then shrink to 0.1pt"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            LaunchPiPTutorialStage(elapsed: elapsed)
                .frame(maxWidth: 370)
                .frame(height: stageHeight)
                .padding(.top, 16)

            Spacer(minLength: 0)

            LaunchPageFooter(
                progress: progress,
                selectedPage: 1,
                hint: L10n.text("轻触跳过", "Tap to skip")
            )
            .padding(.top, 8)
            .padding(.bottom, max(bottomInset + 24, 42))
        }
        .padding(.horizontal, 16)
    }
}

struct LaunchPiPTutorialStage: View {
    let elapsed: TimeInterval

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func smooth(_ value: Double) -> Double {
        let x = clamp(value)
        return x * x * (3 - 2 * x)
    }

    private func segment(_ start: Double, _ end: Double) -> Double {
        smooth((elapsed - start) / (end - start))
    }

    private func mix(_ start: CGFloat, _ end: CGFloat, _ progress: Double) -> CGFloat {
        start + (end - start) * CGFloat(progress)
    }

    private var instruction: String {
        if elapsed < 1.8 {
            return L10n.text("点击“打开悬浮窗”", "Tap “Open PiP”")
        } else if elapsed < 4.2 {
            return L10n.text("拖动悬浮窗到屏幕侧边吸附", "Drag PiP to the edge")
        } else if elapsed < 5.3 {
            return L10n.text("点击“一键 0.1pt”", "Tap “One-tap 0.1pt”")
        } else if elapsed < 6.5 {
            return L10n.text("悬浮窗由上下向中间收缩", "PiP collapses vertically toward the center")
        }
        return L10n.text("完成 · 悬浮窗保持运行并已隐藏", "Done · PiP stays active and hidden")
    }

    var body: some View {
        let tapOpen = segment(0.45, 0.98)
        let appear = segment(0.9, 1.75)
        let drag = segment(2.1, 3.9)
        let tapHide = segment(4.3, 5.05)
        let collapse = segment(5.05, 6.4)
        let finalFade = segment(6.2, 6.5)

        GeometryReader { proxy in
            let width = proxy.size.width
            let pipWidth: CGFloat = 148
            let pipHeight = mix(78, 0.7, collapse)
            let pipStartX = width * 0.5
            let pipEndX = width + pipWidth * 0.5 - 10
            let pipX = mix(pipStartX, pipEndX, drag)
            let pipY = mix(154, 194, collapse)

            let isOpening = elapsed < 1.75
            let isDragging = elapsed >= 1.75 && elapsed < 4.15
            let fingerOpacity: Double = {
                if isOpening {
                    return clamp(segment(0.18, 0.5) - segment(1.18, 1.6))
                }
                if isDragging {
                    return clamp(segment(1.82, 2.2) - segment(3.8, 4.15))
                }
                return clamp(segment(4.1, 4.43) - segment(5.2, 5.5))
            }()
            let fingerX: CGFloat = {
                if isOpening { return width * 0.5 }
                if isDragging { return mix(width * 0.5, width - 8, drag) }
                return width * 0.5
            }()
            let fingerY: CGFloat = isOpening
                ? proxy.size.height - 72
                : (isDragging ? 154 : proxy.size.height - 130)
            let fingerScale: CGFloat = {
                if isOpening { return 1 - CGFloat(sin(tapOpen * .pi)) * 0.2 }
                if !isDragging { return 1 - CGFloat(sin(tapHide * .pi)) * 0.2 }
                return 0.98
            }()

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.94))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color(UIColor.separator).opacity(0.24), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 22, y: 10)

                VStack(spacing: 0) {
                    HStack {
                        Text(L10n.text("首页", "Home"))
                            .font(.system(size: 25, weight: .black, design: .rounded))
                            .foregroundColor(Color(UIColor.label))
                        Spacer()
                        Text(L10n.text("⚙ 更多设置", "⚙ Settings"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color(UIColor.label))
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(Capsule().fill(Color(UIColor.tertiarySystemGroupedBackground)))
                            .overlay(Capsule().stroke(Color(UIColor.separator).opacity(0.2), lineWidth: 1))
                    }

                    HStack(spacing: 7) {
                        Text(L10n.text("当前保活模式", "Keep-alive"))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                        Text(L10n.text("PiP 保活-低功耗", "PiP · Low Power"))
                            .foregroundColor(Color(UIColor.systemBlue))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(UIColor.systemBlue).opacity(0.08)))
                            .overlay(Capsule().stroke(Color(UIColor.systemBlue).opacity(0.22), lineWidth: 1))
                        Spacer()
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.top, 7)

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Circle()
                                .fill(appear > 0.5 ? Color(UIColor.systemGreen) : Color(UIColor.systemGray3))
                                .frame(width: 7, height: 7)
                            Text(appear > 0.5
                                 ? (collapse > 0.7 ? L10n.text("运行中 · 已隐藏", "Active · Hidden") : L10n.text("悬浮窗运行中", "PiP active"))
                                 : L10n.text("悬浮窗未运行", "PiP inactive"))
                            Spacer()
                            Text("VideoCall")
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(UIColor.secondaryLabel))

                        Text(tutorialElapsedText(active: appear > 0.5))
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .foregroundColor(Color(UIColor.label))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(height: 84)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(UIColor.systemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(UIColor.separator).opacity(0.2), lineWidth: 1))
                    .padding(.top, 12)

                    HStack {
                        Text(L10n.text("自定义悬浮窗高度", "Custom PiP height"))
                        Spacer()
                        Text(collapse > 0.65 ? "0.1pt" : "44pt")
                            .foregroundColor(Color(UIColor.systemBlue))
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 15)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color(UIColor.tertiarySystemGroupedBackground)))
                    .padding(.top, 10)

                    Spacer(minLength: 18)

                    tutorialButton(L10n.text("一键 0.1pt", "One-tap 0.1pt"), emphasized: true)
                        .padding(.top, 10)

                    tutorialButton(L10n.text("打开悬浮窗", "Open PiP"), emphasized: false)
                        .padding(.top, 10)

                    Text(instruction)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(height: 30)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 17)
                .padding(.top, 18)

                RoundedRectangle(cornerRadius: mix(17, 1, collapse), style: .continuous)
                    .fill(Color.black)
                    .overlay {
                        if collapse < 0.04 {
                            Text("120 Hz")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: pipWidth, height: max(0.7, pipHeight))
                    .overlay(RoundedRectangle(cornerRadius: mix(17, 1, collapse), style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.26 * (1 - finalFade)), radius: 14, y: 7)
                    .scaleEffect(0.18 + CGFloat(appear) * 0.82)
                    .opacity(appear * (1 - finalFade))
                    .position(x: pipX, y: pipY)

                ZStack {
                    Circle()
                        .stroke(Color(UIColor.systemBlue).opacity(0.42), lineWidth: 2)
                        .frame(width: 38, height: 38)

                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.48), radius: 2, x: 0, y: 1)
                }
                    .frame(width: 40, height: 40)
                    .scaleEffect(fingerScale)
                    .opacity(fingerOpacity)
                    .position(x: fingerX, y: fingerY)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .accessibilityHidden(true)
    }

    private func tutorialButton(_ title: String, emphasized: Bool) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundColor(Color(UIColor.label))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.systemBlue).opacity(emphasized ? 0.13 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(UIColor.systemBlue).opacity(emphasized ? 0.42 : 0.32), lineWidth: 1.25)
            )
    }

    private func tutorialElapsedText(active: Bool) -> String {
        guard active else { return "00:00:00" }
        let seconds = max(0, Int(elapsed - 1.25))
        return String(format: "00:00:%02d", min(seconds, 99))
    }
}

private struct LaunchPageFooter: View {
    let progress: CGFloat
    let selectedPage: Int
    let hint: String

    var body: some View {
        VStack(spacing: 12) {
            LaunchProgressBar(progress: progress)
                .frame(height: 4)

            HStack {
                HStack(spacing: 7) {
                    pageIndicator(selected: selectedPage == 0)
                    pageIndicator(selected: selectedPage == 1)
                }
                Spacer()
                Text(hint)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .frame(width: 210)
    }

    private func pageIndicator(selected: Bool) -> some View {
        Capsule()
            .fill(selected ? Color(UIColor.systemBlue) : Color(UIColor.systemGray4))
            .frame(width: selected ? 22 : 7, height: 7)
    }
}

private struct LaunchPiPStatusAnimation: View {
    let time: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let progress = reduceMotion
            ? 0.5
            : time.truncatingRemainder(dividingBy: 2.8) / 2.8
        let breathing = 0.5 + 0.5 * sin(progress * .pi * 2)
        let statusOpacity = 0.68 + breathing * 0.32

        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color(UIColor.separator).opacity(0.28), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.11), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(UIColor.systemGreen).opacity(statusOpacity))
                        .frame(width: 8, height: 8)
                    Text(L10n.text("悬浮窗", "PiP"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Spacer()
                    Text(L10n.text("运行中", "Active"))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(UIColor.systemGreen))
                }

                Spacer(minLength: 12)

                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text("120")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(Color(UIColor.systemBlue))
                    Text("Hz")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Color(UIColor.systemBlue))
                    Spacer()
                    Text(L10n.text("高刷", "Refresh"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }

                Capsule()
                    .fill(Color(UIColor.systemBlue).opacity(0.13))
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color(UIColor.systemBlue).opacity(0.82 + breathing * 0.18))
                            .frame(width: 42 + breathing * 58, height: 6)
                    }
                    .padding(.top, 10)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .scaleEffect(0.985 + breathing * 0.015)
        .accessibilityHidden(true)
    }
}

private struct LaunchProgressBar: View {
    let progress: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color(UIColor.tertiarySystemFill))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color(UIColor.systemBlue))
                        .frame(width: max(8, proxy.size.width * progress))
                }
        }
        .accessibilityHidden(true)
    }
}

struct LaunchDisplayLinkDriver: UIViewRepresentable {
    @Binding var timestamp: TimeInterval

    func makeCoordinator() -> Coordinator {
        Coordinator(timestamp: $timestamp)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        let displayLink = CADisplayLink(
            target: context.coordinator,
            selector: #selector(Coordinator.step(_:))
        )
        configure(displayLink)
        displayLink.add(to: .main, forMode: .common)
        context.coordinator.displayLink = displayLink
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let displayLink = context.coordinator.displayLink {
            configure(displayLink)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.displayLink?.invalidate()
        coordinator.displayLink = nil
    }

    private func configure(_ displayLink: CADisplayLink) {
        let targetFramesPerSecond = min(120, UIScreen.main.maximumFramesPerSecond)
        if #available(iOS 15.0, *) {
            let target = Float(targetFramesPerSecond)
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: target,
                maximum: target,
                preferred: target
            )
        } else {
            displayLink.preferredFramesPerSecond = targetFramesPerSecond
        }
    }

    final class Coordinator: NSObject {
        var displayLink: CADisplayLink?
        private var timestamp: Binding<TimeInterval>

        init(timestamp: Binding<TimeInterval>) {
            self.timestamp = timestamp
        }

        @objc func step(_ displayLink: CADisplayLink) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                timestamp.wrappedValue = displayLink.timestamp
            }
        }
    }
}
