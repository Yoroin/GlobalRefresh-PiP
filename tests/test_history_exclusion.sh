#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/pip_swift/pip_swift"
if rg -n 'KeepAliveHistory|KeepAliveSessionRecord|KeepAliveSessionEndReason|onShowKeepAliveHistory|pendingKeepAliveHistoryEndReason|pip\.keepAliveHistory' "$SOURCE" "$ROOT/pip_swift/pip_swift.xcodeproj/project.pbxproj"; then
    printf '%s\n' 'FAIL: deferred history feature is still referenced'
    exit 1
fi
test ! -e "$SOURCE/KeepAliveHistory.swift"
for marker in 'private func beginPiPRuntimeSession' 'private func finishPiPRuntimeSession' 'LightweightRuntimeDiagnostics.recordPiPCheckpoint' 'ProcessTerminationDiagnostics.recordCheckpoint'; do
    rg -q -F "$marker" "$SOURCE/ViewController.swift"
done
printf '%s\n' 'PASS: history source, build references and runtime writes excluded; Home runtime and diagnostic checkpoints retained'
