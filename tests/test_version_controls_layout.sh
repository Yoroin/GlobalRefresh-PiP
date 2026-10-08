#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-version-layout.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
printf 'import Foundation\nimport CoreGraphics\nstruct Metrics { var versionFAQRowCenterY: CGFloat }\nstruct LayoutProbe { var layout: Metrics; var versionDescriptionFrame: CGRect; var versionDescriptionReferenceHeight: CGFloat\n' > "$TEMP/main.swift"
awk '/^    private var fixedFAQRowCenterY:/ { copy=1 }
     copy && /^    private var languageSwitchAnimation:/ { exit }
     copy { sub(/private var/, "var"); print }' \
    "$ROOT/pip_swift/pip_swift/PiPViews.swift" >> "$TEMP/main.swift"
printf '}\n' >> "$TEMP/main.swift"
cat "$ROOT/tests/version_controls_layout.swift" >> "$TEMP/main.swift"
xcrun swiftc "$TEMP/main.swift" -o "$TEMP/test"
"$TEMP/test"
