#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-hidden-switch-tests.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
rg -qF 'guard PiPHiddenReferenceMode.supportsSystemMajorVersion(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),' \
    "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift"
# Compile the production preference/session enums, not copies of their logic.
awk '/^enum PiPHiddenReferenceOptions /{copy=1} /^final class PiPHiddenReferenceRenderView/{exit} copy' \
    "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" > "$TEMP/options.swift"
sed -i '' '1i\
import Foundation\
' "$TEMP/options.swift"
xcrun swiftc "$TEMP/options.swift" "$ROOT/tests/hidden_reference_switches.swift" -o "$TEMP/switch-tests"
"$TEMP/switch-tests"
