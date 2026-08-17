<p align="center">
  <img src="assets/app-icon.png" alt="Global Refresh PiP icon" width="96" height="96">
</p>

# Global Refresh PiP

<h3>
  <a href="README.md">Simplified Chinese</a> | English | <a href="DEVELOPMENT_PRD.md">开发文档 PRD</a> | <a href="DEVELOPMENT_PRD_EN.md">Development Document PRD</a>
</h3>

> An experimental iOS Picture-in-Picture overlay for ProMotion behavior, custom PiP sizing, and background keep-alive testing.

GlobalRefresh PiP explores a practical iOS behavior: on some ProMotion iPhones, certain apps or system scenes may fall back to around 80 Hz even though the hardware can refresh at 120 Hz. A tiny docked Picture-in-Picture window can sometimes keep iOS in a higher-refresh scheduling path, improving scrolling and animation smoothness in those scenes.

The project is also useful as a reference for developers who want to build a custom-height PiP overlay using `AVPictureInPictureVideoCallViewController`, without necessarily enabling any forced 120 Hz behavior.

## Overview

This project continues development on top of the original PiP sample by CaiWanFeng. The current version is maintained by Yoroin and focuses on:

- custom-height iOS Picture-in-Picture overlays
- near-invisible docked PiP windows
- PiP-based background keep-alive experiments
- ProMotion refresh-rate behavior testing
- VideoCall and PlayerLayer PiP route comparison
- iOS 15+ compatibility and iOS 26-style UI adaptation
- diagnostic logging for PiP, background state, and frame-rate behavior

Please note:

- This project is intended only for learning, research, and personal-device testing.
- The effect depends on system Picture in Picture behavior, device refresh-rate capability, and each app's own refresh-rate policy.
- A 60 Hz device, or an app that is strictly locked to 60 Hz, cannot become 120 Hz just because of this project.
- Background keep-alive is not a permanent system-level background permission. It may still be affected by memory pressure, system policy, or other PiP apps.

## What This Project Is Useful For

- Building a custom-height iOS PiP overlay
- Studying `AVPictureInPictureVideoCallViewController` as a PiP content route
- Comparing VideoCall and PlayerLayer based PiP behavior
- Testing how `CADisplayLink` frame-rate hints affect ProMotion devices
- Keeping a tiny PiP window docked and quickly shrinking it to a near-invisible height
- Investigating PiP-based background keep-alive behavior and its limits

## What It Does Not Guarantee

- It does not turn 60 Hz hardware into 120 Hz hardware.
- It cannot override every app's own frame-rate policy.
- It does not provide a permanent background execution entitlement.
- Results may differ across iOS versions, devices, and foreground apps.
- The PlayerLayer route cannot fully hide because its underlying PiP surface has a 1 pt minimum.

## PiP Route Comparison

| Route | Advantages | Limitations | Recommended Use |
| --- | --- | --- | --- |
| Default: VideoCall | Supports a minimum height of 0.1 pt and can be visually hidden; better compatibility; more stable for daily use | Requests high-refresh behavior aggressively, so some 60 Hz locked games or danmaku scenes may stutter because of refresh-rate mismatch | Most apps, 80 Hz fallback scenes, and users who need the floating window to fully hide |
| New: PlayerLayer | Can improve stutter caused by some 60 Hz locked apps becoming unsynchronized with 120 Hz, such as Bilibili danmaku speed fluctuation or occasional Brawl Stars lobby drops | Limited by the underlying route to a minimum of 1 pt, so it cannot fully hide and may leave a thin visible line; this is a testing entry | Only try this route when you encounter 60 Hz locked scene stutter |

In short: the default route hides better and is recommended for most users. The new route is mainly for specific 60 Hz locked stutter cases, but it cannot fully hide at 0.1 pt.

## Features

- PiP background keep-alive
- Custom floating-window height, down to 0.1 pt
- Adjustable side-docked floating-window size
- Start or stop floating-window text scrolling
- Remember floating-window height
- Frame-rate demo page for comparing 80 Hz and 120 Hz behavior
- Tutorial and FAQ pages
- iOS 26 Liquid Glass-style UI adaptation
- Blur-style fallback UI for older iOS versions
- iOS 15 / iOS 16 compatibility improvements
- Debug mode for copying recent diagnostic logs when reporting issues

## Usage

1. Open the app and tap "Enable PiP" on the home page.
2. Drag the floating window to the side of the screen until it docks.
3. To hide the floating window, adjust its height to 0.1 pt after it starts.
4. If you run into issues, open Debug Mode from the About/FAQ tools and copy the diagnostic log.

![Demo](assets/demo.gif)

## Developer Notes

If you only want to use the default `VideoCall` route to implement a custom-height Picture in Picture floating window, and do not need this project's forced 120 Hz behavior, keep the `AVPictureInPictureVideoCallViewController` + `AVPictureInPictureController.ContentSource` route.

The basic idea is to create a transparent `AVPictureInPictureVideoCallViewController`, use `preferredContentSize` to control the floating-window size, and attach your custom view inside the content view:

```swift
let contentController = AVPictureInPictureVideoCallViewController()
contentController.preferredContentSize = CGSize(width: 300, height: customHeight)
contentController.view.backgroundColor = .clear
contentController.view.isOpaque = false

let contentSource = AVPictureInPictureController.ContentSource(
    activeVideoCallSourceView: sourceView,
    contentViewController: contentController
)

let pipController = AVPictureInPictureController(contentSource: contentSource)
```

When changing the height later, update both `preferredContentSize` and your custom view constraints. If you need visual hiding, you can reduce the height to a very small value such as `0.1 pt`; otherwise, use a more conservative height.

If you do not need forced 120 Hz, avoid copying this project's high-refresh driver fields:

- Do not enable `CADisableMinimumFrameDurationOnPhone` in `Info.plist`
- Do not pin `CADisplayLink.preferredFrameRateRange` to `minimum = maximum = preferred = 120`
- Do not pin `preferredFramesPerSecond` to `120`
- If you still need a DisplayLink, let the system adapt, for example:

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

In short: for custom height only, keep the `VideoCall` PiP container and `preferredContentSize`, and remove the forced 120 Hz fields so the system can decide the refresh rate.

## Self-Signing

The exported unsigned IPA can be signed and installed with tools such as:

- Bullfrog Assistant
- AltStore
- Sideloadly
- TrollStore
- Other sideloading or self-signing tools

Use your own Apple ID, certificate, or device environment to sign and install the app.

## Changelog

### 1.0.9 fix1 (2026.7.13)

- Fixed an issue where interface icons could disappear after switching appearance on iOS versions below 26.
- Appearance detection now runs only in the foreground and stops polling when the app enters the background.
- Debug Mode is now disabled after an app update, and old diagnostics are cleared to prevent monitors and retained logs from continuing to use memory.
- Cleaned up and limited generated floating-window video caches to prevent storage usage from continuously growing for some users.

### 1.0.9 (2026.7.8)

- Rolled the high-refresh driver fields back to the stable 1.0.7 behavior, fixing 120 Hz unlock failures on some iOS versions.
- Added an engine switch testing entry. It can improve Bilibili danmaku and Brawl Stars stutter caused by some 60 Hz locked scenes becoming unsynchronized with 120 Hz. The new route cannot fully hide and has a 1 pt minimum; the default VideoCall route still supports 0.1 pt hiding.
- Added the home-page "One-tap 0.1 pt" button for quickly adjusting height after the floating window is docked.
- Optimized floating-window components to avoid two white dots at 0.1 pt. This only applies to iOS 16+.
- Reduced resource usage after hiding: text scrolling and clock refresh pause at 0.1 pt to reduce unnecessary long-running background work and heat.
- Removed the Background Interruption Alert beta feature to reduce false positives.
- Improved dark-mode switching logic and moved the button to the home page.
- Added lower-iOS Shortcut compatibility attempts. If Shortcuts do not work, use More Settings > Manual Shortcut Import.
- Added English localization.
- Simplified Debug Mode. When Debug Mode is off, logging stops completely to reduce performance overhead.
- Improved frame-rate detection logic and some animation details.
- Enabled the original text floating window, PiP conflict alert, persistent PiP status, and remembered PiP height by default.
- Added manual height input.
- Known issue: using a Shortcut to open and hide PiP in one step may leave the floating window undocked, which can prevent auto-lock. It is generally recommended to enable PiP first, drag it to the side until it docks, then tap "One-tap 0.1 pt".

### 1.0.8 (2026.6.19)

- Built with Xcode 27 beta, compatible with iOS 15 through iOS 27.
- Added PiP clock, network speed, and frame-rate detection. Because opening PiP can enable global 120 Hz by default, temporarily turn off the Frame Rate Demo force-120 switch before using frame-rate detection.
- Clock PiP is forcibly disabled below iOS 26 to avoid breaking global 120 Hz on older systems. Text PiP is unaffected.
- Added a Dark Mode switch in Home > More Settings. When off, the app follows the system appearance; when on, it stays in dark mode.
- Added separate PiP Conflict Alert and Background Interruption Alert beta switches in Home > More Settings. PiP Conflict Alert notifies you when another Picture in Picture app pushes this PiP away. Background Interruption Alert beta is off by default and uses polling plus scheduled local notifications to help detect whether the app is still alive in the background. The frequency mainly affects detection speed and false-positive risk; it does not mean battery use increases linearly.
- Improved home layout stability and fixed slight page shifts after some state changes.
- Added system Shortcuts: Open and Hide PiP, Open PiP, and Hide PiP, for one-tap Control Center actions. To add them, long-press Control Center, add a Shortcut, then select Global Refresh. Control Center Shortcut tiles require iOS 18+. If two dots appear on screen, it means the PiP close button was not hidden; restore the PiP window to normal size and tap it once, and it will auto-hide next time.
- Added a persistent PiP status switch for checking runtime.
- Added dark-mode app icon support.
- Improved the PiP stop flow.
- Improved the force-refresh demo description. This switch currently affects PiP 120 Hz behavior both when enabled and disabled.

### 1.0.7 (2026.6.8)

- To reduce power usage, the app now defaults to a more power-efficient PiP-only keep-alive route after testing. Background keep-alive remains strong, and this also resolves some audio-conflict cases.
- The current keep-alive mode can be checked below the version number or on the home page.
- The old route is no longer recommended, but it can still be switched manually in Debug Mode if needed.
- Added PiP status detection on the home page, making it easier to check whether PiP is active, hidden, or killed in the background. Tap it to view each session's runtime and last stop time, which helps estimate background retention.
- Moved the Stop Scrolling button into a secondary menu to avoid confusion.

### 1.0.6 (2026.6.6)

- Added a keep-alive route switch in Debug Mode. You can try switching to the more power-efficient PiP-only keep-alive route, though background retention may decrease and lower iOS versions may have compatibility issues.
- Fixed an issue where PiP could reopen automatically after being closed and then sent to the background.
- Added a copy diagnostics log feature in Debug Mode to help investigate power changes and infer background keep-alive interruption periods.

### 1.0.5 (2026.6.6)

- Fixed stutter for some iOS 16 users, a possible camera-related crash for some iOS 16 users, and an issue where custom PiP height did not take effect. Thanks to the testers who provided crash logs and helped verify the fix.
- Fixed audio-conflict issues reported by some users.
- Improved the UI on older iOS versions. Components that do not support Liquid Glass use Gaussian blur instead.

### 1.0.4 (2026.6.4)

- Fixed crashes on older iOS devices. Verified on iOS 15.8.

### 1.0.3 (2026.6.4)

- Added remembered default behavior for scrolling PiP. Added a Remember PiP Height switch on the home page.
- Attempted to fix an issue where lower iOS 16 versions could not open PiP.

### 1.0.2 (2026.6.3)

- Changed the minimum custom PiP height to 0.1 pt, allowing the floating window to be fully hidden visually.

### 1.0.1 (2026.5.27)

- Removed the rotate-window feature.
- Added custom PiP height adjustment with a continuous slider.
- Added start/stop scrolling controls.

### 1.0.0 (2026.5.26)

- Added background keep-alive and floating-window size changes on top of the original project.

## Debug Logs

The About page provides a Debug Mode switch. When enabled, it can copy recent diagnostic logs for checking:

- Whether PiP was prepared successfully
- Whether the system allows Picture in Picture
- Foreground/background keep-alive state
- Audio interruptions and recovery
- Compatibility branches for older iOS versions

Logs are stored locally only. They are copied to the clipboard only after the user taps the copy button.

## Credits

This project is based on [CaiWanFeng/PiP](https://github.com/CaiWanFeng/PiP). Thanks to CaiWanFeng for the original PiP sample.

- Original project: [CaiWanFeng/PiP](https://github.com/CaiWanFeng/PiP)
- Original author: CaiWanFeng
- Current project: [Yoroin/GlobalRefresh-PiP](https://github.com/Yoroin/GlobalRefresh-PiP)
- Current modified version maintained by: Yoroin

If you modify, redistribute, or publish an app based on this project, please keep the credits for CaiWanFeng, Yoroin, and the related project links. Do not claim this project or a modified version as a completely original work.

## Disclaimer

This project is provided only for learning and personal testing. Users are responsible for the risks involved in installation, signing, and use. Do not use this project for platform-rule violations, commercial infringement, or other improper purposes.
