#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-beta-debug-default.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
cp "$ROOT/tests/beta_debug_default.swift" "$TEMP/test.swift"
awk '/^enum DiagnosticsResetManager / { copy=1 }
     copy { print }
     copy && /^}/ { exit }' "$ROOT/pip_swift/pip_swift/DiagnosticsResetManager.swift" >> "$TEMP/test.swift"
printf '%s\n' 'enum ProcessTerminationDiagnostics {
    static let runActiveKey = "old-process-active"
    static let lastCheckpointDateKey = "old-checkpoint"
    static func dateText(_ t: Double) -> String { String(t) }' >> "$TEMP/test.swift"
awk '/^    static func markBuildTransition\(from / {keep=1} keep {print} keep && /^    }/ {exit}' \
    "$ROOT/pip_swift/pip_swift/AppDebugLogger.swift" >> "$TEMP/test.swift"
printf '%s\n' '}' 'enum KeepAliveLogger {' '    static let sessionActiveKey = "keepalive-active"' \
    '    static let backgroundStartKey = "keepalive-background-start"' >> "$TEMP/test.swift"
awk '/^    static func markBuildTransition\(\)/ {keep=1} keep {print} keep && /^    }/ {exit}' \
    "$ROOT/pip_swift/pip_swift/KeepAliveLogger.swift" >> "$TEMP/test.swift"
printf '}\n' >> "$TEMP/test.swift"
printf '\nrunTests()\n' >> "$TEMP/test.swift"
xcrun swiftc "$TEMP/test.swift" -o "$TEMP/test"
"$TEMP/test"
PLIST="$ROOT/pip_swift/pip_swift/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
DEBUG_DEFAULT="$(/usr/libexec/PlistBuddy -c 'Print :DefaultDebugModeEnabled' "$PLIST")"
if [[ "$VERSION" == *beta* ]]; then [[ "$DEBUG_DEFAULT" == true ]]; else [[ "$DEBUG_DEFAULT" == false ]]; fi
