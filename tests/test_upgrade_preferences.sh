#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-upgrade-tests.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
printf 'import Foundation\n' > "$TEMP/policy.swift"
for name in PiPCoexistencePreferences PiPNativePostStartTrial; do
    awk -v name="$name" '$0 ~ "^enum " name " " { copy=1 }
         copy { print }
         copy && /^}/ { exit }' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" >> "$TEMP/policy.swift"
done
xcrun swiftc "$TEMP/policy.swift" "$ROOT/tests/upgrade_preferences.swift" -o "$TEMP/test"
"$TEMP/test"
sed -n '/enum PiPRouteDescriptions/,/static var defaultPrefix/p' "$ROOT/pip_swift/pip_swift/PiPViews.swift" |
    rg -Fq '|| PiPNativePostStartTrial.supportsSystemMajorVersion'
printf 'PASS: obsolete-description strikethrough recognizes the native optimized route\n'
