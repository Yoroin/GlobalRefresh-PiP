#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-resource-cleanup.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
SOURCE="$ROOT/pip_swift/pip_swift"
cp "$ROOT/tests/resource_cleanup.swift" "$TEMP/main.swift"
awk '/^    private static func threadUsageSnapshot\(/ { copy=1 }
     copy { print }
     copy && /^    }/ { exit }' "$SOURCE/AppDebugLogger.swift" >> "$TEMP/main.swift"
printf '\n}\nResourceSnapshotHarness.runTests()\n' >> "$TEMP/main.swift"
xcrun swiftc "$TEMP/main.swift" -o "$TEMP/test"
"$TEMP/test"
python3 - "$SOURCE/FrameRateTestTabBarController.swift" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
driver = source.split('private struct FrameRateDriverView: UIViewRepresentable {', 1)[1]
assert '    func dismantleUIView(' not in driver
match = re.search(r'static func dismantleUIView\(_ uiView: UIView, coordinator: Coordinator\) \{([^}]+)\}', driver)
assert match, 'SwiftUI static dismantle hook is missing'
body = match.group(1)
for expected in ('NotificationCenter.default.removeObserver(coordinator)',
                 'coordinator.displayLink?.invalidate()',
                 'coordinator.displayLink = nil'):
    assert expected in body, expected
print('PASS: SwiftUI static dismantle hook removes observers and invalidates/releases the display link')
PY
