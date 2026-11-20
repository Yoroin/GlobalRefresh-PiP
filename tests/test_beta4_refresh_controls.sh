#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-beta4-controls.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
cp "$ROOT/tests/beta4_refresh_controls.swift" "$TEMP/main.swift"
awk '/^enum PiPRefreshRequestTrial / { copy=1 } /^enum PiPVisibilityRefreshPolicy / { exit } copy' \
    "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift" >> "$TEMP/main.swift"
printf '\nrunBeta4RefreshTests()\n' >> "$TEMP/main.swift"
xcrun swiftc "$TEMP/main.swift" -o "$TEMP/test"
"$TEMP/test"
python3 - "$ROOT/pip_swift/pip_swift/PiPViews.swift" <<'PY'
from pathlib import Path
import re
import sys
view_path = Path(sys.argv[1])
source = view_path.read_text()
assert source.count('private var refreshRequestTrialMenu:') == 1
assert len(re.findall(r'^\s*refreshRequestTrialMenu\s*$', source, flags=re.M)) == 1
assert re.search(r'#if PIP_REFRESH_COMPARISON\s+refreshRequestTrialMenu\s+#endif', source)
project = view_path.parent.parent / 'pip_swift.xcodeproj' / 'project.pbxproj'
assert 'PIP_REFRESH_COMPARISON' not in project.read_text(), 'The comparison menu must stay hidden in default builds'
assert 'trialBackgroundMode' in source and 'trialContent120' in source
assert 'BackgroundMode.systemDefault.rawValue' in source
assert 'BackgroundMode.visibilityPaused.rawValue' in source
assert 'BackgroundMode.explicit120.rawValue' in source
assert '.disabled(trialContent120)' in source
assert 'background: .visibilityPaused, contentFPS: 30' in source
assert 'background: .systemDefault, contentFPS: 30' in source
assert 'background: .explicit120, contentFPS: 30' in source
assert 'background: .systemDefault, contentFPS: 60' in source
stats = source.split('private struct PiPLiveProcessStatsView:', 1)[1].split('private struct PiPRuntimeText:', 1)[0]
assert 'HStack(spacing: 10)' in stats and 'VStack(' not in stats
assert '%.0f MB' in stats and '%.1f MB' not in stats
assert '.lineLimit(1)' in stats and '.minimumScaleFactor(' in stats
driver = Path(sys.argv[1]).with_name('MainTabBarController.swift').read_text()
assert 'PiPRefreshRequestTrial.shouldPauseBackgroundDriver(' in driver
assert 'background driver RUNNING:' in driver and 'background driver APPLIED: stopped' in driver
assert driver.index('refreshDisplayLink?.invalidate()', driver.index('private func startRefreshDriver')) < driver.index('CADisplayLink(target:', driver.index('private func startRefreshDriver'))
print('PASS: Home comparison hidden by default; selectors and four presets preserved; status and driver behavior unchanged')
PY
