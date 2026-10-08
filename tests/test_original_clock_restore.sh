#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-original-clock-tests.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
SOURCE="pip_swift/pip_swift/ViewController.swift"
BASELINE="cca4d5d42399b0fcc5b8b5fa156d26a0cbf0b866"
git -C "$ROOT" show "$BASELINE:$SOURCE" > "$TEMP/baseline.swift"

extract_metrics() {
    awk '/^    private func updateMeasuredFPS\(/{copy=1} /^    private func startPiPSmoothly\(/{exit} copy' "$1"
}
extract_overlay() {
    sed 's/^private final class ClockOverlayView/final class ClockOverlayView/' "$1" |
        awk '/^final class ClockOverlayView/{copy=1} /^private struct NetworkTrafficSample/{exit} copy'
}
extract_metrics "$TEMP/baseline.swift" |
    sed 's/let fpsText = isContentExtremeModeEnabled ?/let fpsText = (isContentExtremeModeEnabled || isHiddenReferenceSession) ?/' > "$TEMP/baseline-metrics.swift"
extract_metrics "$ROOT/$SOURCE" > "$TEMP/current-metrics.swift"
test -s "$TEMP/current-metrics.swift"
diff -u "$TEMP/baseline-metrics.swift" "$TEMP/current-metrics.swift"
extract_overlay "$TEMP/baseline.swift" |
    sed -e 's/func configure(height: CGFloat, hidden: Bool)/func configure(height: CGFloat, hidden: Bool, showsFPS: Bool = true)/' \
        -e 's/fpsLabel.textColor = shouldShowMetrics ?/fpsLabel.textColor = shouldShowMetrics \&\& showsFPS ?/' \
        -e 's/fpsLabel.isHidden = !shouldShowMetrics$/fpsLabel.isHidden = !shouldShowMetrics || !showsFPS/' > "$TEMP/baseline-overlay.swift"
extract_overlay "$ROOT/$SOURCE" > "$TEMP/current-overlay.swift"
test -s "$TEMP/current-overlay.swift"
diff -u "$TEMP/baseline-overlay.swift" "$TEMP/current-overlay.swift"

rg -q 'clockOverlay.configure\(height: contentHeight, hidden: !showsClock, showsFPS: false\)' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift"
test "$(rg -c 'setClockMode\(shouldRenderClockMode, isHidden: isPiPVisuallyHidden, height: clampedPiPHeight\)' "$ROOT/$SOURCE")" = 2
rg -q 'clockOverlayView = probe.clockOverlay' "$ROOT/$SOURCE"
! rg -q 'self.updateMeasuredFPS\(from: link\)' "$ROOT/$SOURCE"
rg -q 'self.updateClockOverlay\(timestamp: link.timestamp, forceNetworkSample: false\)' "$ROOT/$SOURCE"
! rg -q 'PiPHiddenReferenceClock|PiPHiddenReferenceMetrics|App ~|App --fps' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift"
awk '/^    private var shouldRunPiPContentUpdates:/{copy=1} /^    private func updateAutoHiddenOverheadState/{exit} copy' "$ROOT/$SOURCE" > "$TEMP/guards.swift"
test "$(rg -c 'guard !isHiddenReferenceSession else \{ return false \}' "$TEMP/guards.swift")" = 2
printf 'PASS: original clock layout and network logic preserved; FPS hidden and unsampled only on the content-only route; compatibility defaults and hidden lifecycle guards retained\n'
