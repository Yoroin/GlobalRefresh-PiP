#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-ios15-content.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
SOURCE="$ROOT/pip_swift/pip_swift/ViewController.swift"
printf 'import Foundation\n' > "$TEMP/production.swift"
awk '/^enum PiPNativePostStartTrial / { copy=1 }
     copy { print }
     copy && /^}/ { exit }' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" >> "$TEMP/production.swift"
awk '/^enum PiPNativeContentRefreshPolicy / { copy=1 }
     copy { print }
     copy && /^}/ { exit }' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" >> "$TEMP/production.swift"
awk '/^enum PiPRefreshRequestTrial / { copy=1 }
     copy { print }
     copy && /^}/ { exit }' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" >> "$TEMP/production.swift"
cat "$ROOT/tests/ios15_native_content_refresh.swift" >> "$TEMP/production.swift"
for method in updateNativeContentRefresh stopNativeContentRefresh updateNativeContent; do
    awk -v name="$method" '
        $0 ~ "^    private func " name "\\(" { copy=1; sub("private func", "func") }
        copy { print }
        copy && /^    }/ { exit }
    ' "$SOURCE" >> "$TEMP/production.swift"
done
printf '}\n' >> "$TEMP/production.swift"
printf '\nNativeContentTests.run()\n' >> "$TEMP/production.swift"
xcrun swiftc "$TEMP/production.swift" -o "$TEMP/test"
"$TEMP/test"
rg -Fq 'defer { updateVisibilityDrivenContentRefresh(reason: "content mode or height changed") }' "$SOURCE"
test "$(rg -c 'stopNativeContentRefresh\(\)' "$SOURCE")" -ge 4
! sed -n '/private func updateNativeContentRefresh()/,/private func startPlayerLayerActivityDisplayLinkIfNeeded/p' "$SOURCE" |
    rg -q 'PiPHiddenReferenceMode.begin|prepareForStart|contentType|setValue|play\('
printf 'PASS: native refresh retains startup/stop ownership and no contentType, coexistence or audio mutation; refresh trials are separate\n'
