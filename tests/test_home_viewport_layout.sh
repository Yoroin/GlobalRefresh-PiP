#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-home-viewport.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
printf 'import Foundation\nimport CoreGraphics\n' > "$TEMP/layout.swift"
awk '/^struct PiPHomeViewportLayout / { copy=1 }
     copy { print }
     copy && /^}/ { exit }' "$ROOT/pip_swift/pip_swift/PiPViews.swift" >> "$TEMP/layout.swift"
xcrun swiftc "$TEMP/layout.swift" "$ROOT/tests/home_viewport_layout.swift" -o "$TEMP/test"
"$TEMP/test"
