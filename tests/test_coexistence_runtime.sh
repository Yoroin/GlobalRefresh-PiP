#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-coexistence-runtime.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
# Only the UIKit render view is excluded; runtime hooks are compiled from production.
cat > "$TEMP/runtime.swift" <<'SWIFT'
import Foundation
import ObjectiveC
final class AVPictureInPictureController: NSObject {
    struct ContentSource {}
    var isPictureInPictureActive = false
    var isPictureInPictureSuspended = false
    init(contentSource: ContentSource) { super.init() }
}
SWIFT
awk '
    /^enum PiPHiddenReferenceControls / { copy = 1 }
    /^final class PiPHiddenReferenceRenderView/ { copy = 0 }
    /^final class PiPCoexistenceExperiment/ { copy = 1 }
    copy
' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" >> "$TEMP/runtime.swift"
xcrun clang -fobjc-arc -c "$ROOT/tests/coexistence_fixture.m" -o "$TEMP/fixture.o"
xcrun swiftc -import-objc-header "$ROOT/tests/coexistence_fixture.h" \
    "$TEMP/runtime.swift" "$ROOT/tests/coexistence_runtime.swift" "$TEMP/fixture.o" \
    -framework Foundation -o "$TEMP/runtime-tests"
"$TEMP/runtime-tests"
