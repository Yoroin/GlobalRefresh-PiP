#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-diagnostics-share.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
SOURCE="$ROOT/pip_swift/pip_swift"
extract_method() {
    awk -v signature="$2" '
        index($0, signature) { copy=1 }
        copy { print }
        copy && /^    }/ { exit }
    ' "$1"
}
cp "$ROOT/tests/diagnostics_share.swift" "$TEMP/main.swift"
awk '/^enum DiagnosticsLogExporter / { copy=1 }
     copy { print }
     copy && /^}/ { exit }' "$SOURCE/VersionViewController.swift" >> "$TEMP/main.swift"
printf '\nextension AppDebugLogger {\n' >> "$TEMP/main.swift"
extract_method "$SOURCE/AppDebugLogger.swift" 'private static func limitEntry(' >> "$TEMP/main.swift"
extract_method "$SOURCE/AppDebugLogger.swift" 'private static func trimMemoryBuffer()' >> "$TEMP/main.swift"
printf '}\ntry runTests()\n' >> "$TEMP/main.swift"
xcrun swiftc "$TEMP/main.swift" -o "$TEMP/test"
"$TEMP/test"
for value in 'maximumEntries = 1200' 'maximumEntryBytes = 16 * 1024' 'maximumBufferBytes = 3_000_000'; do
    rg -Fq "$value" "$SOURCE/AppDebugLogger.swift"
done
rg -Fq 'if newestFirst { entries.reverse() }' "$SOURCE/AppDebugLogger.swift"
rg -Fq 'if newestFirst { samples.reverse() }' "$SOURCE/AppDebugLogger.swift"
rg -Fq 'if newestFirst { events.reverse() }' "$SOURCE/KeepAliveLogger.swift"
rg -Fq 'activity.popoverPresentationController?.sourceView = self.view' "$SOURCE/VersionViewController.swift"
rg -Fq 'activity.completionWithItemsHandler' "$SOURCE/VersionViewController.swift"
rg -Fq 'DiagnosticsLogExporter.abandonedTemporaryDirectories(in: temporaryEntries)' "$SOURCE/DiagnosticsResetManager.swift"
rg -Fq 'message: isDebugModeEnabled ? shareAdvice : diagnosticsDetailNotice' "$SOURCE/VersionViewController.swift"
rg -Fq 'message: diagnosticsDetailNotice' "$SOURCE/VersionViewController.swift"
printf 'PASS: bounded capacity, ordering and iPad share-anchor checks\n'
