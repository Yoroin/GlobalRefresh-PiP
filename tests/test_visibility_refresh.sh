#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-visibility-tests.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
printf 'import Foundation\nimport ObjectiveC\n' > "$TEMP/visibility.swift"
awk '/^enum PiPVisibilityRefreshPolicy / { copy=1 }
     /^enum PiPHiddenReferenceControls / { exit }
     copy { print }' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" >> "$TEMP/visibility.swift"
xcrun swiftc "$TEMP/visibility.swift" "$ROOT/tests/visibility_refresh.swift" -o "$TEMP/tests"
"$TEMP/tests"
awk '/^    private func startRefreshDriver\(/ { copy=1 }
     copy { print }
     copy && /^    }/ { exit }' "$ROOT/pip_swift/pip_swift/MainTabBarController.swift" > "$TEMP/driver.swift"
rg -Fq 'refreshDisplayLink = displayLink' "$TEMP/driver.swift"
rg -Fq 'PiPVisibilityRefreshPolicy.pauseExtraBackgroundDriver' "$TEMP/driver.swift"
rg -Fq 'background driver APPLIED: stopped for visibility; content updates retained' "$TEMP/driver.swift"
awk '/PiPRefreshRequestTrial.shouldPauseBackgroundDriver/ { copy=1 }
     copy { print }
     copy && /^        }/ { exit }' "$TEMP/driver.swift" > "$TEMP/visibility-branch.swift"
rg -q 'return' "$TEMP/visibility-branch.swift"
printf 'PASS: group B stops only the extra background link; content-pause policy is disabled\n'
