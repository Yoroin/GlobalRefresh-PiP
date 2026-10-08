#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-home-one-tap.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
awk '/^    private func togglePiP\(\)/ { copy=1 }
     /^    private func presentPiPCloseConfirmation\(/ { exit }
     copy { print }' "$ROOT/pip_swift/pip_swift/ViewController.swift" |
    rg -q 'if pipController\?\.isPictureInPictureActive != true, !isPiPTransitioning \{'
# Compile the actual Home dispatch method, not a duplicated implementation.
printf 'extension HomeHarness {\n' > "$TEMP/dispatch.swift"
awk '/^    private func startPiPAndHideFromHome\(\)/ { copy=1 }
     /^    private func startHiddenReferencePiP\(/ { exit }
     copy { sub(/private func startPiPAndHideFromHome/, "func startPiPAndHideFromHome"); print }' "$ROOT/pip_swift/pip_swift/ViewController.swift" >> "$TEMP/dispatch.swift"
awk '/^    private var startAndHidePiPButtonTitle: String/ { copy=1 }
     copy { sub(/private var/, "var"); print }
     copy && /^    }/ { exit }' "$ROOT/pip_swift/pip_swift/PiPViews.swift" >> "$TEMP/dispatch.swift"
printf '}\n' >> "$TEMP/dispatch.swift"
xcrun swiftc "$TEMP/dispatch.swift" "$ROOT/tests/home_one_tap.swift" -o "$TEMP/home-tests"
"$TEMP/home-tests"
