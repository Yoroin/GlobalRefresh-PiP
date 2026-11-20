# GlobalRefresh-PiP Implementation Guide

[简体中文](IMPLEMENTATION.md) | English

This guide describes the default VideoCall and PiP-only configuration in the `1.1.2` source. See the [README](../README_EN.md) for the project overview, route comparison, installation, and release notes.

## 1. PiP Content Updates and Display Refresh Rate

**30 fps is the PiP content update target, not a display refresh limit.** The default configuration continues updating PiP content with text scrolling disabled. When hidden, stashed, or locked conditions qualify, it pauses only the extra background refresh driver; it does not stop the PiP session or its content updates. iOS schedules display refresh independently.

The demo's 120 Hz switch only controls this app's foreground refresh request. When off, it requests up to 80 Hz without changing background PiP content updates or playback. Compare the same scrolling gesture in Settings on the same device with PiP on and off when checking the system-wide effect. Neither the in-app animation nor the requested rate measures actual system refresh.

- ~~Explicitly request a fixed 120 Hz on the default VideoCall background driver.~~ The current default keeps content updates without that explicit background request.
- ~~Use continuous silent audio as the default keep-alive.~~ PiP-only is the default; other audio modes remain available.

Strikethrough indicates an old use that no longer applies to **the current default combination**. It does not imply that Apple deprecated the API.

## 2. Startup, Coexistence, and Controls

1. **Start PiP first.** The default combination uses native VideoCall startup on iOS 15. It neither adds the newer control-hiding behavior at construction nor forces an initial content type for coexistence.
2. **Attempt coexistence after startup.** After recognizing a supported system state, the first transition is scheduled roughly one second later. The same session gets bounded checks and retries without restarting PiP; closing or replacing it cancels stale work.
3. **Maintain hidden controls separately.** On iOS 16 and later, hide at construction and check after startup, resizing, and a coexistence write. Resubmit the style to the current proxy after the transition instead of relying on the outer property. If the private interface does not match, prefer native controls and startup.
4. **Distinguish suspension from stopping.** A temporarily suspended PiP session is retained for system recovery. Cleanup only runs after it is confirmed inactive and not suspended.

[AVKit content sources](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource-swift.class) are public APIs. The internal coexistence and control-hiding adaptations are not. Content types (commonly `4 → 6`) are runtime details, not documented Apple enum values. Scheduling, applying a write, and local readback are different observations. **Reading back `6` does not prove that the system has accepted coexistence with another PiP.**

The PlayerLayer fallback loops a video. Media generation runs in the background and uses only completed files. Old jobs cannot replace the current player after switching routes, stopping PiP, or replacing the session.

## 3. Compatibility and Verification

| Check | How to verify |
| --- | --- |
| iOS 15 startup | Cold-launch on a device. Try both regular startup and Start & Hide in the default mode. A simulator or local regression test is not a substitute. |
| iOS 16+ controls | Test first startup, reopening after a stop, resizing, and the coexistence transition for a reappearing close control. |
| Coexistence and keep-alive | Leave our PiP running and open another app's PiP. Observe both windows. Log temporary suspension, session stop, and process exit separately. |
| Refresh and side effects | Compare PiP on and off on the same device in the same scene. Also check auto-lock, media playback, and the return-to-Home animation. Do not substitute the in-app demo or a refresh request for system measurements. |
| In-place upgrade | Upgrade from (1.1.1) to (1.1.2). Check that settings, recent logs, and diagnostics were preserved, then start PiP again. |

The deployment target is iOS 15. Hardware, OS version, other apps, and system resources affect results; testing on one device does not establish universal support. [iOS does not grant ordinary apps permanent background execution](https://developer.apple.com/forums/thread/685525). A last heartbeat is the last confirmation, not proof of a memory kill, a process exit, or a PiP stop.

Release builds disable Debug Mode by default but retain a bounded lightweight event log. Detailed performance collection requires Debug Mode. In-place upgrades keep existing exit records and system diagnostics. Review and redact personal information before sharing logs.

## 4. Source Entry Points

| File | Responsibility |
| --- | --- |
| [ViewController.swift](../pip_swift/pip_swift/ViewController.swift) | PiP construction, sizing, content updates, lifecycle, and PlayerLayer media preparation. |
| [PiPCoexistenceExperiment.swift](../pip_swift/pip_swift/PiPCoexistenceExperiment.swift) | Default refresh policy, coexistence, session-scoped retries, and control styles. |
| [MainTabBarController.swift](../pip_swift/pip_swift/MainTabBarController.swift) | Foreground refresh and switching the extra background driver. |
| [AppDebugLogger.swift](../pip_swift/pip_swift/AppDebugLogger.swift) / [MetricKitLogger.swift](../pip_swift/pip_swift/MetricKitLogger.swift) | Lightweight events, detailed archives, and system diagnostics. |

Open `pip_swift/pip_swift.xcworkspace` from the repository root and select the `pip_swift` scheme. Use your own signing configuration for device builds. Run focused regression checks from the repository root on a Mac with Xcode and its command-line tools:

```bash
bash tests/test_ios15_native_content_refresh.sh
bash tests/test_controls_resubmission.sh
bash tests/test_bounded_coexistence_retry.sh
bash tests/test_page_refresh_isolation.sh
bash tests/test_recent_runtime_logs.sh
```

Original example: [CaiWanFeng/PiP](https://github.com/CaiWanFeng/PiP). Continued development and maintenance: [Yoroin](https://github.com/Yoroin/GlobalRefresh-PiP). Retain both attributions; see [NOTICE](../NOTICE).
