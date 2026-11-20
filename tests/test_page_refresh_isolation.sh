#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-page-refresh.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
printf 'import Foundation\n' > "$TEMP/preference.swift"
awk '/^enum DemoFrameRatePreference / { copy=1 }
     /^enum FrameRatePreference / { exit }
     copy' "$ROOT/pip_swift/pip_swift/FrameRateTestTabBarController.swift" >> "$TEMP/preference.swift"
printf '\nenum ForegroundRefreshHarness {\nstatic var usesIOS15NativeContentRefresh = false\nstatic var requestsTrialBackground120 = false\n' >> "$TEMP/preference.swift"
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
reject() { if rg -q "$1" "$2"; then echo "Unexpected $1 in $2" >&2; exit 1; fi; }
reject 'DemoFrameRatePreference' "$ROOT/pip_swift/pip_swift/ViewController.swift"
reject 'PiPHiddenReferenceMode.preferenceKey|PiPCoexistenceExperiment.preferenceKey' "$ROOT/pip_swift/pip_swift/PiPViews.swift"
printf 'PASS: PiP controller does not observe demo preference; retired controls remain absent\n'
for file in MainTabBarController.swift GlobalRefresh2LaunchCelebration.swift; do
    rg -q 'DemoFrameRatePreference.configureForegroundRequest' "$ROOT/pip_swift/pip_swift/$file"
done
rg -Fq 'TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: false))' "$ROOT/pip_swift/pip_swift/FrameRateTestTabBarController.swift"
rg -q 'targetFrameRate: isHighRefreshEnabled \? 120 : \(isScrollActive \? 80 : 60\)' "$ROOT/pip_swift/pip_swift/FrameRateTestTabBarController.swift"
rg -q 'let requestedFrameRate = DemoFrameRatePreference.isHighRefreshEnabled' "$ROOT/pip_swift/pip_swift/FrameRateTestTabBarController.swift"
reject 'guard UIApplication.shared.applicationState != .active \|\| selectedIndex != 1' "$ROOT/pip_swift/pip_swift/MainTabBarController.swift"
printf 'PASS: foreground OFF still requests up to80; comparison timeline stays120 with both lanes sampled at80; PiP remains isolated\n'
rg -q 'contentFramesPerSecond = 30' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift"
rg -q 'link.preferredFramesPerSecond = min\(PiPHiddenReferenceOptions.contentFramesPerSecond, UIScreen.main.maximumFramesPerSecond\)' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift"
printf 'PASS: legacy render fallback retains up to30fps; native trial content baseline is checked separately\n'
rg -q 'let clockOverlay = ClockOverlayView\(\)' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift"
test "$(rg -c 'CADisplayLink\(target:' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift")" = 1
sed -n '/^final class PiPHiddenReferenceRenderView/,/^final class PiPCoexistenceExperiment/p' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" > "$TEMP/render.swift"
rg -q 'let clockOverlay = ClockOverlayView' "$TEMP/render.swift"
reject 'configureForClockRefreshRate|preferredFrameRateRange|Timer\(' "$TEMP/render.swift"
printf 'PASS: clock reuses the original white overlay and one content link without a second clock refresh request\n'
