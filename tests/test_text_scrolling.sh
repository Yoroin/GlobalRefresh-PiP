#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP=$(mktemp -d /tmp/pip-text-scrolling.XXXXXX)
trap 'rm -rf "$TEMP"' EXIT
printf 'import Foundation\nimport CoreGraphics\n' > "$TEMP/render.swift"
awk '/^enum PiPHiddenReferenceOptions /{copy=1} /^final class PiPCoexistenceExperiment/{exit} copy' \
    "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" >> "$TEMP/render.swift"
xcrun swiftc "$ROOT/tests/text_scrolling.swift" "$TEMP/render.swift" -o "$TEMP/test"
"$TEMP/test"
SOURCE="$ROOT/pip_swift/pip_swift/ViewController.swift"
[[ $(rg -cF 'hiddenReferenceRenderView?.setTextScrollingEnabled(isScrollingEnabled)' "$SOURCE") == 2 ]]
rg -qF 'content-update link retained' "$SOURCE"
