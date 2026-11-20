#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-route-text.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
printf 'import Foundation\nimport AppKit\n' > "$TEMP/descriptions.swift"
awk '/^enum PiPNativePostStartTrial /{copy=1} /^final class PiPHiddenReferenceRenderView/{exit} copy' \
    "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" >> "$TEMP/descriptions.swift"
awk '/^enum PiPRouteDescriptions / { copy=1 }
     /^private extension PiPEngineRoute / { exit }
     copy' "$ROOT/pip_swift/pip_swift/PiPViews.swift" >> "$TEMP/descriptions.swift"
xcrun swiftc "$TEMP/descriptions.swift" "$ROOT/tests/route_descriptions.swift" -o "$TEMP/test"
"$TEMP/test"
rg -qF 'Text(L10n.text("备选方案", "Alternative Route"))' "$ROOT/pip_swift/pip_swift/PiPViews.swift"
rg -qF 'return L10n.text("当前：PlayerLayer 备选方案", "Current: PlayerLayer alternative")' "$ROOT/pip_swift/pip_swift/PiPViews.swift"
rg -qF 'return L10n.text("备", "Alt")' "$ROOT/pip_swift/pip_swift/PiPViews.swift"
rg -qF 'title: L10n.text("确认切换至备选方案", "Switch to the Alternative Route?")' "$ROOT/pip_swift/pip_swift/ViewController.swift"
echo 'PASS: alternative route naming and badge are consistent'
