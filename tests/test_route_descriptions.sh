#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-route-text.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
printf 'import Foundation\nimport AppKit\n' > "$TEMP/descriptions.swift"
awk '/^enum PiPHiddenReferenceOptions /{copy=1} /^final class PiPHiddenReferenceRenderView/{exit} copy' \
    "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" >> "$TEMP/descriptions.swift"
awk '/^enum PiPRouteDescriptions / { copy=1 }
     /^private extension PiPEngineRoute / { exit }
     copy' "$ROOT/pip_swift/pip_swift/PiPViews.swift" >> "$TEMP/descriptions.swift"
xcrun swiftc "$TEMP/descriptions.swift" "$ROOT/tests/route_descriptions.swift" -o "$TEMP/test"
"$TEMP/test"
