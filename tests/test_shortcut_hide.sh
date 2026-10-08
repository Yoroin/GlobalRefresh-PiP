#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-shortcut-hide.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
SOURCE="$ROOT/pip_swift/pip_swift/ViewController.swift"
printf 'import Foundation\nextension ShortcutHideHarness {\n' > "$TEMP/hide.swift"
awk '/^    private func applyOneTapMinimumHeight\(/ { copy=1 }
     /^    private func startPiPFromShortcut\(/ { copy=0 }
     copy { sub(/private func/, "func"); print }' "$SOURCE" >> "$TEMP/hide.swift"
awk '/^    private func startPiPFromShortcut\(/ { copy=1 }
     /^    private func prepareShortcutPiPStartRetryIfNeeded\(/ { exit }
     copy { sub(/private func/, "func"); print }' "$SOURCE" >> "$TEMP/hide.swift"
awk '/^    private func hidePiPFromShortcut\(/ { copy=1 }
     /^    private func applyPlayerLayerMinimumHeightImmediately\(/ { exit }
     copy { sub(/private func/, "func"); print }' "$SOURCE" >> "$TEMP/hide.swift"
awk '/^    private func retryLegacyPiPStartIfNeeded\(/ { copy=1 }
     /^    private func prepareCustomViewForPiPStart\(/ { exit }
     copy { sub(/private func/, "func"); print }' "$SOURCE" >> "$TEMP/hide.swift"
printf '}\nenum ShortcutURLParser {\n' >> "$TEMP/hide.swift"
awk '/^    private static func action\(from url/ { copy=1 }
     /^    private static func postDarwinNotification/ { exit }
     copy { sub(/private static func/, "static func"); print }' "$ROOT/pip_swift/pip_swift/PiPShortcutIntents.swift" >> "$TEMP/hide.swift"
printf '}\n' >> "$TEMP/hide.swift"
awk '/^enum PiPShortcutInstallLinks/ { copy=1 }
     /^enum PiPShortcutActionCenter/ { exit }
     copy { print }' "$ROOT/pip_swift/pip_swift/PiPShortcutIntents.swift" >> "$TEMP/hide.swift"
xcrun swiftc "$TEMP/hide.swift" "$ROOT/tests/shortcut_hide.swift" -o "$TEMP/hide-tests"
"$TEMP/hide-tests"
awk '/^    private func resetPiPStartStateAfterFailure\(/ { copy=1 }
     /^    private func retryPiPStartWithLegacyControlsStyleFallbackIfNeeded/ { exit }
     copy' "$SOURCE" | rg -q 'if !preservingShortcutRetry'
rg -q 'resetPiPStartStateAfterFailure\(preservingShortcutRetry: true\)' "$SOURCE"
awk '/^    private func recoverStalePiPTransition\(/ { copy=1 }
     /^    @discardableResult/ && copy { exit }
     copy' "$SOURCE" | rg -q 'hidePiPAfterShortcutStartIfNeeded\(\)'
printf 'PASS: terminal failure clears queued actions; scheduled retry explicitly retains its target; confirmed-active watchdog applies pending hide\n'
INTENTS="$ROOT/pip_swift/pip_swift/PiPShortcutIntents.swift"
for type in StartFloatingWindowIntent HideFloatingWindowIntent; do
    awk -v type="$type" '$0 ~ "^public struct " type ":" { copy=1 }
         copy && /^}/ { exit }
         copy { print }' "$INTENTS" | rg -q 'isDiscoverable: Bool \{ false \}'
done
COUNT=$(awk '/^public struct AppShortcuts:/ { copy=1 }
            copy && /^}/ { exit }
            copy { print }' "$INTENTS" | rg -c '^        AppShortcut\(')
[[ "$COUNT" == 1 ]]
printf 'PASS: one offered native action and one import; legacy native actions remain hidden rather than deleted\n'
