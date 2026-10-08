#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${1:-/tmp/pip-hidden-reference-no-refresh-derived}"
mkdir -p "$DERIVED"
INFO="$DERIVED/HiddenReference-Info.plist"
cp "$ROOT/pip_swift/pip_swift/Info.plist" "$INFO"
/usr/libexec/PlistBuddy -c 'Delete :CADisableMinimumFrameDurationOnPhone' "$INFO"
xcodebuild -workspace "$ROOT/pip_swift/pip_swift.xcworkspace" \
    -scheme pip_swift -configuration Debug -sdk iphoneos \
    -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
    INFOPLIST_FILE="$INFO" CODE_SIGNING_ALLOWED=NO build -quiet
APP_INFO="$DERIVED/Build/Products/Debug-iphoneos/pip_swift.app/Info.plist"
if /usr/libexec/PlistBuddy -c 'Print :CADisableMinimumFrameDurationOnPhone' "$APP_INFO" >/dev/null 2>&1; then
    echo 'ERROR: no-refresh test build still contains the opt-in key' >&2
    exit 1
fi
echo "No-refresh test build ready: $DERIVED/Build/Products/Debug-iphoneos/pip_swift.app"
