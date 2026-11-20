#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-recent-runtime-logs.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
SOURCE="$ROOT/pip_swift/pip_swift"
cp "$ROOT/tests/recent_runtime_logs.swift" "$TEMP/main.swift"
awk '/^final class RecentRuntimeLogStore / { copy=1 }
     /^enum AppDebugLogger / { exit }
     copy { print }' "$SOURCE/AppDebugLogger.swift" >> "$TEMP/main.swift"
awk '/^enum AppDebugLogger / { copy=1 }
     copy { print }
     copy && /^}/ { exit }' "$SOURCE/AppDebugLogger.swift" |
    sed 's@FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)\[0\]@testDirectory@' >> "$TEMP/main.swift"
printf '\ntry runTests()\n' >> "$TEMP/main.swift"
xcrun swiftc "$TEMP/main.swift" -o "$TEMP/test"
"$TEMP/test"
rg -Fq 'recentRuntimeLogs.exportText(newestFirst: newestFirst)' "$SOURCE/AppDebugLogger.swift"
rg -Fq 'AppDebugLogger.resetLogs(includingRecentRuntime: true)' "$SOURCE/DiagnosticsResetManager.swift"
if sed -n '/private var copyDiagnosticsLogButton:/,/private var debugModeStatusLabel:/p' "$SOURCE/PiPViews.swift" | rg -q 'allowsHitTesting\(displayedDebugModeEnabled\)'; then
    printf 'FAIL: diagnostics export is hidden while Debug Mode is off\n'
    exit 1
fi
printf 'PASS: export integration, manual cleanup and debug-off share access\n'
