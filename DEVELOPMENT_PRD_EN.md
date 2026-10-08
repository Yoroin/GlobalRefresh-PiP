# GlobalRefresh-PiP v1.1.1

## 120Hz PiP Integration PRD

**Status:** Developer integration reference
**Baseline:** `v1.0.9` GitHub tag
**Audience:** Developers who want to add the PiP refresh-rate layer to an existing iOS floating-window app

> Updated on 2026-10-09 for the 1.1.1 implementation. Existing v1.0.9 code examples remain historical references; sections 5.4 and 13 describe the new default combination.

> Strikethrough marks an old usage no longer used in the 1.1.1 default VideoCall + PiP-only combination, not an Apple API deprecation or removal from foreground pages or other compatibility modes. Old code blocks remain historical comparisons, not current integration steps.

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

The original v1.0.9 route examples remain historical references. Sections 5.4 and 13 cover the new 1.1.1 default content-update and coexistence implementation; other compatibility modes are not equivalent to it.

## 3. Recommended Integration Model

### 3.1 Default route: VideoCall

Third-party developers should normally use `VideoCall` as the default foundation:

1. Keep the existing app's overlay UI and user interaction.
2. Mount that UI into `AVPictureInPictureVideoCallViewController`.
3. Create a content source with `activeVideoCallSourceView` and the content controller.
4. Keep `preferredContentSize`, source-view constraints, and internal content constraints synchronized.
5. ~~Use the main refresh driver to request the target ProMotion rate for PiP.~~ The new default retains independent content updates; foreground refresh requests are separate.
6. After the PiP window is docked, reduce the content height to `0.1pt` when a visually hidden overlay is desired.

The developer is integrating a lower-level PiP implementation, not copying a complete GlobalRefresh app.

### 3.2 Optional route: PlayerLayer

~~Use `PlayerLayer` as the preferred workaround for the default route's 60fps synchronization issues.~~ Version 1.1.1 addresses those old issues in the default combination; PlayerLayer remains a compatibility alternative with more lifecycle complexity, a minimum height of about `1pt`, and a thin visible line.

It should not replace `VideoCall` as the default route. The two routes have different PiP content pipelines and different trade-offs.

## 4. Two Formal Routes

| Area | `VideoCall` | `PlayerLayer` |
| --- | --- | --- |
| PiP source | `AVPictureInPictureVideoCallViewController` content source | `AVPlayerLayer` content source |
| Content | Custom text, clock, or overlay view | H.264 placeholder media played by `AVPlayer` |
| Refresh path | ~~Main `CADisplayLink` and strict `CAFrameRateRange` request for PiP~~; replaced by independent content updates in the new default | Continuous media pipeline plus route-specific activity driver |
| Minimum height | `0.1pt` | `1pt` |
| Visual hiding | Can be visually hidden | A thin line may remain |
| Best use | Daily use and 80 Hz fallback scenes | ~~Preferred workaround for 60fps games/comments~~; retained as a compatibility alternative |
| Main risk | ~~May pull refresh scheduling upward and expose 60 Hz app mismatch~~; addressed in the 1.1.1 default VideoCall + PiP-only combination, not equivalent to other compatibility modes | More complex player, media, and sizing lifecycle |

These are not two public APIs that guarantee 120 Hz. They are two PiP content pipelines that can influence refresh scheduling differently.

## 5. Refresh-Rate Implementation

### 5.1 ~~Old VideoCall Refresh Coupling~~

~~Use the main `CADisplayLink` strict target range and `Info.plist` refresh configuration to drive VideoCall PiP.~~ This old coupling is not used in the new default combination. The code below is a historical comparison; foreground pages still have independent refresh requests.

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

### 5.4 Version 1.1.1 Default Update

The default VideoCall + PiP-only combination retains content updates without the old strict PiP 120Hz request. It adds coexistence protection against displacement or interruption by other PiP windows and supports direct 0.1pt startup.

The previous route comparison and fixed-refresh examples describe v1.0.9. PlayerLayer remains a compatibility alternative, not the first recommendation for the default route's old stuttering issue. Foreground refresh requests remain separate; `CADisableMinimumFrameDurationOnPhone` is not globally removed. See section 13 for implementation and risks.

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

## 9. ~~Silent Audio as the Default Keep-Alive~~

~~Use a silent looping audio file, an `.playback` audio session and `setActive(true)` as the default keep-alive for a newly integrated app.~~ This historical integration approach is not recommended. Optional audio strategies remain available in GlobalRefresh and are separate from the new default PiP-only chain; the audio APIs themselves are not deprecated.

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
4. ~~Add the old strict PiP refresh request for the "force 120" behavior.~~ Integrate independent content updates and assess the private coexistence adapter separately, as described in section 13.
5. ~~Use PlayerLayer as the first workaround for the default route's 60fps mismatch.~~ Keep it as an isolated compatibility alternative.
6. Avoid silent audio keep-alive and avoid claiming capabilities that iOS does not expose as guarantees.

## 13. 1.1.1 Content Updates and PiP Coexistence Protection

### 13.1 Integration Scope

An existing floating-window app can retain its interface and business logic while using the default VideoCall route as a backend reference for the content host, synchronized sizing, direct hidden startup and coexistence protection.

The new default combination is VideoCall + PiP-only, enabled in code for iOS 15–27. This range does not prove validation on every OS, device or third-party app.

The goal is high-refresh assistance and full hiding while allowing another app's PiP to run alongside ours without displacing or interrupting it in compatible scenarios. The changes also address some 60fps game/comment stuttering and screen-lock issues with directly hidden startup.

### 13.2 Changes from v1.0.9

| Area | Historical v1.0.9 default | 1.1.1 default combination |
| --- | --- | --- |
| Refresh/content | Strict target request through the main high-refresh driver | Continued PiP content updates without the previous strict 120Hz request |
| Text scrolling | Coupled to the older content-host implementation | Controls text movement only; content updates remain active |
| Other PiP | Could displace this app's window | Internal content-type provider and playback-state adaptation for coexistence |
| Hidden entry | Usually start, then shrink | Set 0.1pt before startup when inactive; resize the existing window when active |
| Demo switch | Related to the older driver | Affects foreground pages/animations only, not background PiP |
| PlayerLayer | Alternative for certain 60fps scenarios | Retains its compatibility flow; not migrated to the new default combination |

~~The previous use of `preferredFrameRateRange` fixed to `minimum = maximum = preferred = 120`, `preferredFramesPerSecond = 120`, and coupling the demo switch to background PiP~~ is no longer used in this default combination. This is not a global removal of these fields. Foreground refresh requests and `CADisableMinimumFrameDurationOnPhone` have separate uses.

### 13.3 Coexistence Implementation

The public container remains `AVPictureInPictureVideoCallViewController` with `AVPictureInPictureController.ContentSource(activeVideoCallSourceView:contentViewController:)`.

Additional private system integration uses:

- `platformAdapter` and `pegasusProxy` to obtain the current instance's internal objects.
- `pictureInPictureProxyContentType:` to provide the participating instance's content type.
- `updatePlaybackStateUsingBlock:` and `setContentType:` to submit a playback-state content-type change.

These are private system interfaces, not a third-party library or documented public PiP API.

```text
Select VideoCall + PiP-only on a supported OS range
    -> Prepare the instance-scoped provider during construction
    -> Start with contentType = 4 and the original source geometry/user height
    -> Receive pictureInPictureControllerDidStartPictureInPicture
    -> Wait 1 second from successful startup
    -> Verify original controller/adapter/proxy identity, active and not suspended
    -> Submit contentType = 6 once
    -> Continue content updates and record diagnostic checkpoints
```

`PiPCoexistenceExperiment.postStartTransitionDelay` is currently 1 second. It does not start at button press and is not a recurring repair loop. Values 4 and 6 are internal implementation values, not publicly documented Apple enum meanings. A successful local mutation does not alone establish remote system acceptance.

Validate runtime method existence and signatures before invocation. Scope configuration to participating instances, verify session tokens and object identity in delayed work, and skip unsupported adaptations.

On stop, `restore()` invalidates the token, clears instance associations/references and conditionally restores the local content type. Class-level hooks remain dormant without instance configuration; full removal requires a process restart. Do not describe this as clearing all system-side residue.

### 13.4 Content Updates, Stuttering and Screen Lock

`PiPHiddenReferenceRenderView` retains content updates with `PiPHiddenReferenceOptions.requests120 = false`. The current content-driver target is `contentFramesPerSecond = 60`; this does not imply a 60Hz system-wide refresh rate. Turning off text movement does not stop the entire content host.

Removing the old strict PiP 120Hz request eliminates one potential source of competition with 60fps content. Users have reported successful high-refresh assistance, smooth comments and automatic screen locking. This is not proof that one field caused every issue or that every device behaves identically.

Direct hidden startup sets 0.1pt before creation/start, rather than opening a large window and then shrinking it. Coexistence, content updates, hidden geometry and automatic screen locking require separate acceptance tests; setting type 6 alone does not guarantee all four effects.

### 13.5 Source Map

- `pip_swift/pip_swift/PiPCoexistenceExperiment.swift`: mode/options, content host, construction adaptation, provider, one-shot state submission and cleanup.
- `pip_swift/pip_swift/ViewController.swift`: combination selection, construction, unified hidden entry, didStart wiring and stop cleanup.
- `pip_swift/pip_swift/MainTabBarController.swift`: separation of foreground requests from the PiP driver.
- `pip_swift/pip_swift/FrameRateTestTabBarController.swift`: foreground demo/sampling, not system-wide or other-app measurements.
- `pip_swift/pip_swift/PiPShortcutIntents.swift`: native actions and unified hidden entry.

Construction-time preparation is required; copying only the post-start mutation is insufficient. Relevant entry points include `prepareHiddenReference(...)`, `prepareForStartIfRequested(...)`, `schedulePostStartUpdateIfRequested(controller:)` and `restore()`. Follow the actual default-combination ordering in `ViewController.swift`.

Repository: [Yoroin/GlobalRefresh-PiP](https://github.com/Yoroin/GlobalRefresh-PiP). Check the source version when reading; v1.0.9 links are historical references, not the 1.1.1 implementation.

### 13.6 Risks and Compatibility

- P0: private interfaces carry App Store rejection and OS-update compatibility risks. Dynamic selector lookup does not make them public APIs.
- P0: runtime hooks and invocation signatures require strict validation and instance scoping to prevent crashes or effects on unrelated flows.
- P1: the 1-second timing requires tests for slow startup, suspension and rapid stop/restart.
- P1: coexistence does not prevent termination under memory pressure/system policy, provide permanent background permission or restart PiP after process death.
- P1: Audio Keep-alive and Lock-screen Audio Enhancement remain available in the app but are not part of this default chain. Silent looping audio has conflict, power and background-purpose review risks.
- P1: PlayerLayer and non-PiP-only strategies do not automatically inherit this protection.

The original v1.0.9 “deprecated audio” chapter is historical integration guidance, not a claim that 1.1.1 removed every audio strategy. Likewise, the old fixed-refresh examples are historical, not instructions to reintroduce them into the new default chain.

### 13.7 Acceptance Checklist

- [ ] Cold first startup and subsequent starts preserve expected animation, position and controls.
- [ ] Visible start, direct 0.1pt start, active resizing and slider feedback agree.
- [ ] Home, native action and imported URL entry behavior match.
- [ ] Test another app's PiP startup/playback/close and verify actual PiP/high-refresh behavior, not only the “Running” label.
- [ ] Closing our PiP does not stop another app's playback.
- [ ] Test automatic screen locking, manual lock/unlock with and without docking first.
- [ ] Test Bilibili comments/video, 60fps games, volume keys and external video/ad audio.
- [ ] Stopping text movement retains content updates; foreground switch does not change background PiP.
- [ ] Unsupported runtimes, slow starts, suspension and rapid restart do not crash or mutate stale sessions.
- [ ] Test long runs, Low Power Mode, memory pressure, interruption and cold-start time records.
- [ ] Record pass/fail/unverified per OS/device across iOS 15–27; do not substitute code range for hardware validation.

### 13.8 Attribution

This project started from [CaiWanFeng/PiP](https://github.com/CaiWanFeng/PiP) and is continuously developed and maintained by [Yoroin](https://github.com/Yoroin/GlobalRefresh-PiP). Preserve attribution to the original demo author and subsequent developer, project links and the source of reused code.
