#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-controls-resubmit.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
cp "$ROOT/tests/controls_resubmission.swift" "$TEMP/main.swift"
awk '/^    private func maintainPiPControlsHidden\(/ { copy=1; sub("private func", "func") }
     copy { print }
     copy && /^    }/ { exit }' "$ROOT/pip_swift/pip_swift/ViewController.swift" >> "$TEMP/main.swift"
printf '}\nrunTests()\n' >> "$TEMP/main.swift"
xcrun swiftc "$TEMP/main.swift" -o "$TEMP/test"
"$TEMP/test"
rg -Fq 'resubmitAfterTransition: true' "$ROOT/pip_swift/pip_swift/ViewController.swift"
