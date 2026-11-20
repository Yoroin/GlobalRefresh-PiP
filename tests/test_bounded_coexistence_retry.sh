#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-bounded-retry.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
printf '%s\n' 'import Foundation' 'import ObjectiveC' \
    'final class AVPictureInPictureController: NSObject {' \
    'struct ContentSource {}' 'var isPictureInPictureActive = false' \
    'var isPictureInPictureSuspended = false' '@objc var platformAdapter: NSObject?' \
    'init(contentSource: ContentSource) { super.init() }' '}' > "$TEMP/runtime.swift"
awk '/^enum PiPHiddenReferenceControls / { copy=1 }
     /^final class PiPHiddenReferenceRenderView/ { copy=0 }
     /^final class PiPCoexistenceExperiment/ { copy=1 }
     copy { print }' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" >> "$TEMP/runtime.swift"
xcrun clang -fobjc-arc -c "$ROOT/tests/coexistence_fixture.m" -o "$TEMP/fixture.o"
xcrun swiftc -import-objc-header "$ROOT/tests/coexistence_fixture.h" \
    "$TEMP/runtime.swift" "$ROOT/tests/bounded_retry_runtime.swift" "$TEMP/fixture.o" -framework Foundation -o "$TEMP/test"
"$TEMP/test"
