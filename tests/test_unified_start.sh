#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-unified-start.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
SOURCE="$ROOT/pip_swift/pip_swift/ViewController.swift"
# Compile shared start and retry methods from production, with UI-only dependencies stubbed.
printf 'import Foundation\nextension UnifiedStartHarness {\n' > "$TEMP/start.swift"
awk '/^    private func startHiddenReferencePiP\(/ { copy=1 }
     /^    @discardableResult/ && copy { exit }
     copy { sub(/private func/, "func"); print }' "$SOURCE" >> "$TEMP/start.swift"
awk '/^    private func prepareShortcutPiPStartRetryIfNeeded\(/ { copy=1 }
     /^    private func hidePiPFromShortcut\(/ { exit }
     copy { sub(/private func/, "func"); print }' "$SOURCE" >> "$TEMP/start.swift"
printf '}\n' >> "$TEMP/start.swift"
xcrun swiftc "$TEMP/start.swift" "$ROOT/tests/unified_start.swift" -o "$TEMP/start-tests"
"$TEMP/start-tests"
# Guard the entry wiring as well as the shared implementation.
awk '/^    private func startPiPFromShortcut\(/ { copy=1 }
     /BETA5_ANCHOR_SHORTCUT_START_AND_HIDE/ { exit }
     copy' "$SOURCE" | rg -q 'startHiddenReferencePiP\(atMinimumHeight: shouldHideAfterStart, source: "快捷指令", fromShortcut: true\)'
awk '/^    private func hidePiPFromShortcut\(/ { copy=1 }
     /guard let pipController/ && copy { exit }
     copy' "$SOURCE" | rg -q 'startHiddenReferencePiP\(atMinimumHeight: true, source: "快捷指令一键0.1pt", fromShortcut: true\)'
awk '/^    private func togglePiP\(/ { copy=1 }
     /promotePlayerLayerMinimumHeightForNormalStartIfNeeded/ && copy { exit }
     copy' "$SOURCE" | rg -q 'startHiddenReferencePiP\(atMinimumHeight: false, source: "首页开启"\)'
printf 'PASS: Home open, shortcut open/start-and-hide and shortcut one-tap route to the shared hidden-path entry\n'
