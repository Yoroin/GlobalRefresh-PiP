#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-frame-v110.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
SOURCE="$ROOT/pip_swift/pip_swift/FrameRateTestTabBarController.swift"
git -C "$ROOT" show v1.1.0:pip_swift/pip_swift/FrameRateTestTabBarController.swift > "$TEMP/old.swift"
extract_card() {
    awk '/^private struct FrameCadenceComparisonCard/ { copy=1 }
         /^struct FrameRateScrollableListView/ { exit }
         copy' "$1"
}
extract_driver() {
    awk '/^private struct FrameRateDriverView/ { copy=1 }
         /^private struct FrameRateGlassIconButtonStyle/ { exit }
         copy' "$1"
}
extract_card "$TEMP/old.swift" |
    sed -e '/^private struct FrameCadenceComparisonCard: View {/a\
    @AppStorage(DemoFrameRatePreference.force120HzKey) private var isHighRefreshEnabled = true\

    ' -e 's/label: "120Hz", sampleRate: 120/label: isHighRefreshEnabled ? "120Hz" : "80Hz", sampleRate: isHighRefreshEnabled ? 120 : 80/' > "$TEMP/old-card.swift"
extract_card "$SOURCE" > "$TEMP/current-card.swift"
cmp "$TEMP/old-card.swift" "$TEMP/current-card.swift"
extract_driver "$TEMP/old.swift" | sed -e 's/FrameRatePreference\./DemoFrameRatePreference./g' -e 's/^    func dismantleUIView(/    static func dismantleUIView(/' > "$TEMP/expected-driver.swift"
extract_driver "$SOURCE" > "$TEMP/current-driver.swift"
cmp "$TEMP/expected-driver.swift" "$TEMP/current-driver.swift"
! rg -q 'FrameCadenceDiagnosticWindow|FrameCadenceTimelineDiagnostics|Frame demo timeline cadence|Frame demo driver cadence|scenePhase|isVisible' "$TEMP/current-card.swift" "$TEMP/current-driver.swift"
printf 'PASS: old120 timeline, motion and driver retained; OFF both balls use80; ON retains80/120 sampling\n'
