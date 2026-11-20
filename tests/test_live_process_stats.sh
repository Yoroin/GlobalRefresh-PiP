#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-live-stats.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
cp "$ROOT/tests/live_process_stats.swift" "$TEMP/main.swift"
awk '/^final class PiPLiveProcessStatsMonitor:/ { copy=1 }
     copy { print }
     copy && /^}/ { exit }' "$ROOT/pip_swift/pip_swift/PiPViews.swift" >> "$TEMP/main.swift"
printf '\nrunLiveStatsTests()\n' >> "$TEMP/main.swift"
xcrun swiftc "$TEMP/main.swift" -o "$TEMP/test"
"$TEMP/test"
python3 - "$ROOT/pip_swift/pip_swift/PiPViews.swift" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
popover = source.split('private var pipStatusInfoPopover:', 1)[1].split('private struct PiPLiveProcessStatsView:', 1)[0]
assert popover.index('Last stopped:') < popover.index('PiPLiveProcessStatsView()')
stats = source.split('private struct PiPLiveProcessStatsView:', 1)[1].split('private struct PiPRuntimeText:', 1)[0]
assert '.onDisappear' in stats and 'setVisible(false)' in stats
assert 'scenePhase' not in stats and '.physicalFootprintMB' in stats and '.threadCount' in stats
assert stats.count('PiPRollingMetricText(') == 2
runtime = source.split('private struct PiPRuntimeText:', 1)[1].split('private struct PiPRollingMetricText:', 1)[0]
assert 'PiPRollingMetricText(label: label, value: fallbackDuration)' in runtime
rolling = source.split('private struct PiPNumericRoll:', 1)[1].split('private struct ActionButton:', 1)[0]
assert 'accessibilityReduceMotion' in rolling and '#available(iOS 16.0, *), !reduceMotion' in rolling
assert '.numericText(countsDown: true)' in rolling and '.easeInOut(duration: 0.22), value: value' in rolling
assert '.modifier(PiPNumericRoll(value: value))' in source
assert '.modifier(PiPNumericRoll(value: detail))' in source
print('PASS: runtime, memory, threads and height use the reversed numeric transition without changing sampling')
PY
