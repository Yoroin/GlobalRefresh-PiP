#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-page-refresh.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
printf 'import Foundation\n' > "$TEMP/preference.swift"
awk '/^enum DemoFrameRatePreference / { copy=1 }
     /^enum FrameRatePreference / { exit }
     copy' "$ROOT/pip_swift/pip_swift/FrameRateTestTabBarController.swift" >> "$TEMP/preference.swift"
printf '\nenum ForegroundRefreshHarness {\n' >> "$TEMP/preference.swift"
awk '/^    private func configureRefreshDriver\(/ { copy=1; sub("private func", "static func") }
     copy { print }
     copy && /^    }/ { exit }' "$ROOT/pip_swift/pip_swift/MainTabBarController.swift" >> "$TEMP/preference.swift"
printf '}\n' >> "$TEMP/preference.swift"
for reference in 'v1.0.9 Legacy109' 'v1.1.0fix Legacy110Fix'; do
    read -r revision name <<< "$reference"
    printf '\nenum %sMain {\n' "$name" >> "$TEMP/preference.swift"
    git -C "$ROOT" show "$revision:pip_swift/pip_swift/MainTabBarController.swift" |
        awk '/^    private func configureRefreshDriver\(/ { copy=1; sub("private func", "static func") }
             copy { print }
             copy && /^    }/ { exit }' >> "$TEMP/preference.swift"
    printf '}\nstruct %sPage {\nlet targetFrameRate: Int\n' "$name" >> "$TEMP/preference.swift"
    git -C "$ROOT" show "$revision:pip_swift/pip_swift/FrameRateTestTabBarController.swift" |
        awk '/^private struct FrameRateDriverView/ { driver=1 }
             driver && /^    private func configure\(/ { copy=1; sub("private func", "func") }
             copy { print }
             copy && /^    }/ { exit }' >> "$TEMP/preference.swift"
    printf '}\n' >> "$TEMP/preference.swift"
done
xcrun swiftc "$TEMP/preference.swift" "$ROOT/tests/page_refresh_isolation.swift" -o "$TEMP/test"
"$TEMP/test"
! rg -q 'DemoFrameRatePreference' "$ROOT/pip_swift/pip_swift/ViewController.swift"
! rg -q 'PiPHiddenReferenceMode.preferenceKey|PiPCoexistenceExperiment.preferenceKey' "$ROOT/pip_swift/pip_swift/PiPViews.swift"
printf 'PASS: PiP controller does not observe demo preference; both experiment controls removed\n'
for file in MainTabBarController.swift GlobalRefresh2LaunchCelebration.swift; do
    rg -q 'DemoFrameRatePreference.configureForegroundRequest' "$ROOT/pip_swift/pip_swift/$file"
done
rg -q 'minimumInterval: isHighRefreshEnabled \? 1.0 / 120.0 : 1.0 / 80.0' "$ROOT/pip_swift/pip_swift/FrameRateTestTabBarController.swift"
rg -q 'targetFrameRate: isHighRefreshEnabled \? 120 : \(isScrollActive \? 80 : 60\)' "$ROOT/pip_swift/pip_swift/FrameRateTestTabBarController.swift"
rg -q 'minimumFrameRateWhenDisabled: 30' "$ROOT/pip_swift/pip_swift/FrameRateTestTabBarController.swift"
printf 'PASS: foreground-only OFF restores released 60/80 requests and comparison cadence; ON unchanged\n'
rg -q 'contentFramesPerSecond = 60' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift"
rg -q 'link.preferredFramesPerSecond = min\(PiPHiddenReferenceOptions.contentFramesPerSecond, UIScreen.main.maximumFramesPerSecond\)' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift"
printf 'PASS: content render callback requests up to 60 fps, capped by the display capability\n'
rg -q 'let clockOverlay = ClockOverlayView\(\)' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift"
test "$(rg -c 'CADisplayLink\(target:' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift")" = 1
! rg -q 'configureForClockRefreshRate|preferredFrameRateRange|Timer\(' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift"
printf 'PASS: clock reuses the original white overlay and one content link without a second clock refresh request\n'
