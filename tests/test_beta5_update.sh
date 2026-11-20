#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /private/tmp/pip-beta5-update.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
SRC="$ROOT/pip_swift/pip_swift/VersionViewController.swift"
printf 'import Foundation\nenum L10n { static func text(_ a: String, _ b: String) -> String { a } }\n' > "$TEMP/version.swift"
sed -n '/^struct AppUpdateInfo /,/^final class VersionViewController/{ /^final class VersionViewController/!p; }' "$SRC" >> "$TEMP/version.swift"
cp "$ROOT/tests/beta5_update.swift" "$TEMP/harness.swift"
for name in setBetaUpdateChannelEnabled checkForUpdates; do
    awk -v name="$name" '$0 ~ "^    private func " name "\\(" { keep=1; sub("private func", "func") } keep { print } keep && /^    }/ {exit}' "$SRC" >> "$TEMP/harness.swift"
done
printf '}\n' >> "$TEMP/harness.swift"
xcrun swiftc "$TEMP/version.swift" "$TEMP/harness.swift" -o "$TEMP/test"
"$TEMP/test"
