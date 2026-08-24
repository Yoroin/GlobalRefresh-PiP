# GlobalRefresh-PiP v1.0.9

## 120Hz PiP Integration PRD

**Status:** Developer integration reference
**Baseline:** `v1.0.9` GitHub tag
**Audience:** Developers who want to add the PiP refresh-rate layer to an existing iOS floating-window app

## 1. Project Positioning

GlobalRefresh-PiP provides a reusable **Picture-in-Picture foundation for floating-window apps**. Its core purpose is to help an ordinary PiP overlay unlock higher system-wide ProMotion refresh-rate behavior on supported devices and in supported app scenes.

This is the behavior commonly called **"force 120"** or **"卡 120"** by users: a persistent PiP window docked to the edge of the screen can help some apps that normally fall back to around 80 Hz reach a higher refresh rate, up to 120 Hz when the device, system, foreground app, PiP state, and system resources allow it.

This project is not intended to replace a third-party app's user interface. Developers can keep their existing overlay, buttons, settings, and business logic, then integrate the PiP content source, refresh request, lifecycle handling, and synchronized sizing from this project as a lower-level implementation.

Compared with common floating-clock utilities, the project focuses on the following combination:

- refresh-rate assistance for ordinary text or clock overlays
- visual hiding down to `0.1pt` with the default `VideoCall` route
- edge-docked PiP operation with background keep-alive behavior
- no advertising in the open-source reference implementation
- a separate `PlayerLayer` route for selected 60 Hz game or danmaku synchronization cases

The project is based on [CaiWanFeng/PiP](https://github.com/CaiWanFeng/PiP) and is maintained by Yoroin.

## 2. Source of Truth

- Repository: [Yoroin/GlobalRefresh-PiP](https://github.com/Yoroin/GlobalRefresh-PiP)
- Formal baseline: [v1.0.9 tag](https://github.com/Yoroin/GlobalRefresh-PiP/tree/v1.0.9)
- Release page: [v1.0.9 release](https://github.com/Yoroin/GlobalRefresh-PiP/releases/tag/v1.0.9)
- Original PiP sample: [CaiWanFeng/PiP](https://github.com/CaiWanFeng/PiP)

This PRD describes only the two public routes exposed by the v1.0.9 formal release. Other experimental or compatibility paths are outside the integration scope.

## 3. Recommended Integration Model

### 3.1 Default route: VideoCall

Third-party developers should normally use `VideoCall` as the default foundation:

1. Keep the existing app's overlay UI and user interaction.
2. Mount that UI into `AVPictureInPictureVideoCallViewController`.
3. Create a content source with `activeVideoCallSourceView` and the content controller.
4. Keep `preferredContentSize`, source-view constraints, and internal content constraints synchronized.
5. Use the main refresh driver to request the target ProMotion rate.
6. After the PiP window is docked, reduce the content height to `0.1pt` when a visually hidden overlay is desired.

The developer is integrating a lower-level PiP implementation, not copying a complete GlobalRefresh app.

### 3.2 Optional route: PlayerLayer

`PlayerLayer` should remain an optional route for selected cases where an app locked around 60 Hz becomes visibly out of sync with a high-refresh PiP path. It is more complex, has a minimum practical height of about `1pt`, and normally leaves a thin visible line.

It should not replace `VideoCall` as the default route. The two routes have different PiP content pipelines and different trade-offs.

## 4. Two Formal Routes

| Area | `VideoCall` | `PlayerLayer` |
| --- | --- | --- |
| PiP source | `AVPictureInPictureVideoCallViewController` content source | `AVPlayerLayer` content source |
| Content | Custom text, clock, or overlay view | H.264 placeholder media played by `AVPlayer` |
| Refresh path | Main `CADisplayLink` and `CAFrameRateRange` request | Continuous media pipeline plus route-specific activity driver |
| Minimum height | `0.1pt` | `1pt` |
| Visual hiding | Can be visually hidden | A thin line may remain |
| Best use | Daily use and 80 Hz fallback scenes | Selected 60 Hz games or danmaku synchronization cases |
| Main risk | May pull refresh scheduling upward and expose 60 Hz app mismatch | More complex player, media, and sizing lifecycle |

These are not two public APIs that guarantee 120 Hz. They are two PiP content pipelines that can influence refresh scheduling differently.

## 5. Refresh-Rate Implementation

### 5.1 VideoCall refresh request

The formal VideoCall route uses the app's main `CADisplayLink`. When the high-refresh option is enabled, the driver requests a strict target range and the project also declares the relevant high-refresh configuration in `Info.plist`.

```swift
if #available(iOS 15.0, *) {
    displayLink.preferredFrameRateRange = CAFrameRateRange(
        minimum: targetRate,
        maximum: targetRate,
        preferred: targetRate
    )
} else {
    displayLink.preferredFramesPerSecond = targetRate
}
```

This is a best-effort scheduling request. It is not a permanent system permission and must not be advertised as a guarantee for every app.

### 5.2 PlayerLayer media pipeline

The PlayerLayer route uses an `AVPlayerLayer` as the PiP content source. A generated H.264 item is played continuously, while a route-specific activity driver checks that the player remains active. The video pipeline, not the activity driver's nominal frequency, produces the media frames.

```swift
let player = AVPlayer(playerItem: playerItem)
let playerLayer = AVPlayerLayer(player: player)

let pipController = AVPictureInPictureController(playerLayer: playerLayer)
pipController?.delegate = delegate
```

The v1.0.9 baseline uses a bounded generated backing video. Do not create an unbounded generation loop or repeatedly create new players without releasing the old item and observers.

### 5.3 Developers who do not need forced 120

If an integrating app only needs an adaptive PiP overlay and does not need the project's high-refresh behavior, do not copy the strict target request or the minimum-frame-duration override. Use an adaptive DisplayLink instead:

```swift
if #available(iOS 15.0, *) {
    displayLink.preferredFrameRateRange = CAFrameRateRange(
        minimum: 30,
        maximum: Float(UIScreen.main.maximumFramesPerSecond),
        preferred: 0
    )
} else {
    displayLink.preferredFramesPerSecond = 0
}
```

## 6. VideoCall Setup and Sizing

```swift
let contentController = AVPictureInPictureVideoCallViewController()
contentController.preferredContentSize = currentPiPSize
contentController.view.backgroundColor = .clear
contentController.view.isOpaque = false

let contentSource = AVPictureInPictureController.ContentSource(
    activeVideoCallSourceView: sourceView,
    contentViewController: contentController
)

let pipController = AVPictureInPictureController(contentSource: contentSource)
pipController?.delegate = delegate
```

The internal custom view should fill the content controller. The PiP container determines the visible window size; the custom view should not be treated as the primary sizing mechanism.

When changing height, update both sides of the geometry chain:

```swift
let size = CGSize(width: currentWidth, height: requestedHeight)
contentController.preferredContentSize = size

sourceWidthConstraint?.update(offset: size.width)
sourceHeightConstraint?.update(offset: size.height)
contentViewWidthConstraint?.update(offset: size.width)
contentViewHeightConstraint?.update(offset: size.height)
```

Recommended v1.0.9 height policy:

- `VideoCall`: clamp to `0.1pt...220pt`.
- `PlayerLayer`: clamp to `1pt...220pt`.
- update the visual geometry immediately during slider preview.
- commit the final size when the user releases the slider.
- treat `0.1pt` as visual hiding, not removal of the PiP object.

## 7. File Map

| File | Responsibility |
| --- | --- |
| `pip_swift/pip_swift/ViewController.swift` | PiP routes, content source, player, lifecycle, sizing, and height actions |
| `pip_swift/pip_swift/MainTabBarController.swift` | Main refresh driver and high-refresh request state |
| `pip_swift/pip_swift/FrameRateTestTabBarController.swift` | Refresh demonstration page and force-120 setting |
| `pip_swift/pip_swift/PiPViews.swift` | Overlay UI, slider, height dialog, and route entry points |
| `pip_swift/pip_swift/Info.plist` | High-refresh configuration and background declarations |
| `pip_swift/pip_swift/BackgroundTaskManager.swift` | Historical audio keep-alive path; not recommended for new integration |
| `README.md` / `README_EN.md` | Public usage, limitations, attribution, and developer notes |

Important v1.0.9 implementation areas in `ViewController.swift` include PiP infrastructure setup, player-item creation, PiP startup, source geometry updates, height preview/commit, and PlayerLayer item reload.

## 8. Height and Lifecycle Requirements

An integration should:

- invalidate every DisplayLink when its route is stopped;
- remove NotificationCenter observers and KVO observers together with their owner;
- avoid registering duplicate end-of-item observers;
- release old `AVPlayerItem`, `AVPlayer`, and `AVPlayerLayer` objects before replacement;
- keep generated media bounded by count and disk size;
- handle PiP start, stop, squeeze, suspend, interruption, and reactivation states;
- keep source-view geometry and content-controller geometry synchronized;
- avoid treating a hidden `0.1pt` surface as a destroyed PiP session.

## 9. Deprecated Audio Keep-Alive

The historical audio keep-alive route uses a silent looping audio file, an `.playback` audio session, and `setActive(true)`. This is not the recommended implementation for a new app.

It creates significant risks:

- it can be interpreted as background audio abuse when no real audio feature exists;
- it may interfere with other media and volume behavior;
- it increases battery and lifecycle complexity;
- declaring background audio without a genuine user-facing audio function can create App Review problems.

Use system PiP as the primary keep-alive mechanism. Do not add silent audio only to avoid normal background suspension.

## 10. App Review and Product Risks

| Priority | Risk | Guidance |
| --- | --- | --- |
| P0 | Using a video-call PiP API for a generic non-call overlay | Document the real user-facing PiP function and review the intended API semantics |
| P0 | Silent audio with `UIBackgroundModes=audio` | Avoid unless the app is genuinely a media/audio product |
| P0 | Claiming guaranteed system-wide 120 Hz or permanent background execution | Use conditional, device-dependent wording |
| P0 | Private or undocumented KVC behavior | Remove it from a public submission build |
| P1 | Long-running hidden `0.1pt` PiP | Explain the visible user control and provide a clear stop path |
| P1 | Dynamic media generation and repeated player replacement | Bound work, release observers, and test cold start and size changes |
| P2 | Claims about other apps' historical FPS or exact system kill reasons | Present only measurements made by the current app |

Relevant Apple guidance includes [AVKit Picture in Picture for video calls](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-for-video-calls), [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession), and the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## 11. Acceptance Checklist

- [ ] Existing overlay UI remains functional after PiP integration.
- [ ] `VideoCall` starts, docks, resizes, hides to `0.1pt`, and stops correctly.
- [ ] `PlayerLayer` starts and stops without duplicate players or observers.
- [ ] Slider preview is immediate and does not generate unbounded media.
- [ ] PiP survives ordinary screen lock/background transitions within system limits.
- [ ] Stop, interruption, squeeze, and reactivation are recorded and recoverable.
- [ ] 60 Hz devices and unsupported app scenes are reported as unsupported rather than promised.
- [ ] No silent audio keep-alive is required for the normal route.
- [ ] Cold install, upgrade install, low-memory, and long locked-screen tests are completed.

## 12. Integration Summary

The recommended third-party architecture is:

1. Keep the third-party app's existing overlay and product UI.
2. Add the v1.0.9 `VideoCall` PiP content source as the default foundation.
3. Synchronize the PiP container size and the app's source-view constraints.
4. Add the refresh request only when the integrating product explicitly needs the "force 120" behavior.
5. Keep `PlayerLayer` as an isolated optional route for special 60 Hz synchronization cases.
6. Avoid silent audio keep-alive and avoid claiming capabilities that iOS does not expose as guarantees.
