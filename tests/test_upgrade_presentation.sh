#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/pip_swift/pip_swift/VersionViewController.swift"
PLIST="$ROOT/pip_swift/pip_swift/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
LATEST="$(awk '/static var latest: AppChangelogSection/ { latest=1; print; next }
    latest && /static var version/ { exit }
    latest { print }' "$SOURCE")"
rg -qF "version: L10n.text(\"${VERSION}（" <<< "$LATEST"
rg -qF 'version: L10n.text("1.1.1（26.10.9）"' "$SOURCE"
if rg -qi 'version: L10n\.text\("[0-9.]+beta|AppChangelogCatalog\.version[0-9]+Beta' "$SOURCE"; then
    echo 'FAIL: Beta history must not appear in the public changelog' >&2
    exit 1
fi
rg -qF '优化 上次关闭时间 显示逻辑' "$SOURCE"
PREVIEW="$(sed -n '/private struct PiPUpgradePreviewState/,/final class LatestChangelogViewController/p' "$SOURCE")"
! rg -q 'CADisplayLink|AVAudio|AVPictureInPicture|startPictureInPicture|Timer\(' <<< "$PREVIEW"
rg -qF 'UIAccessibility.isReduceMotionEnabled' <<< "$PREVIEW"
rg -qF 'UIApplication.willResignActiveNotification' <<< "$PREVIEW"
rg -qF 'NotificationCenter.default.removeObserver(self)' <<< "$PREVIEW"
rg -qF 'playback.stop()' <<< "$PREVIEW"
rg -qF 'LaunchPiPTutorialStage(elapsed: elapsed, showsCoexistence: true)' <<< "$PREVIEW"
rg -qF 'paused: !playback.isRunning' <<< "$PREVIEW"
rg -qF 'finishWorkItem?.cancel()' <<< "$PREVIEW"
rg -qF 'var showsCoexistence: Bool = false' "$ROOT/pip_swift/pip_swift/GlobalRefresh2LaunchCelebration.swift"
rg -qF 'for item in AppChangelogCatalog.latest.displayItems' "$SOURCE"
rg -qF 'makeSection(section: AppChangelogCatalog.version111)' "$SOURCE"
rg -qF 'makeSection(version: section.version, items: section.displayItems)' "$SOURCE"
rg -qF 'items.systemLayoutSizeFitting(' "$SOURCE"
rg -qF 'buttons.axis = showsUpgradePreview ? .horizontal : .vertical' "$SOURCE"
! rg -qF 'showsUpgradePreview ? 740' "$SOURCE"
CHANGELOG="$(sed -n '/final class ChangelogViewController:/,/private final class UpdateAvailableViewController:/p' "$SOURCE")"
rg -qF 'make.leading.trailing.equalTo(contentView).inset(24)' <<< "$CHANGELOG"
rg -qF 'make.leading.trailing.equalTo(contentView)' <<< "$CHANGELOG"
rg -qF 'scrollView.contentInsetAdjustmentBehavior = .never' <<< "$CHANGELOG"
! rg -qF 'make.leading.trailing.bottom.equalTo(contentView.safeAreaLayoutGuide)' <<< "$CHANGELOG"
FAQ="$(sed -n '/private final class FAQViewController:/,$p' "$SOURCE")"
rg -qF 'make.leading.trailing.equalTo(contentView).inset(24)' <<< "$FAQ"
rg -qF 'scrollView.contentInsetAdjustmentBehavior = .never' <<< "$FAQ"
! rg -qF 'make.leading.trailing.bottom.equalTo(contentView.safeAreaLayoutGuide)' <<< "$FAQ"
! rg -qF 'make.leading.trailing.equalTo(contentView.safeAreaLayoutGuide).inset(24)' "$ROOT/pip_swift/pip_swift/ViewController.swift"
rg -qF 'segment(4.2, 5.2)' "$ROOT/pip_swift/pip_swift/GlobalRefresh2LaunchCelebration.swift"
rg -qF 'segment(7.15, 8.5)' "$ROOT/pip_swift/pip_swift/GlobalRefresh2LaunchCelebration.swift"
rg -qF 'upgradePreview?.stopPreview()' "$SOURCE"
! rg -qF 'items.addArrangedSubview(scope)' "$SOURCE"
TEMP="$(mktemp -d /tmp/pip-upgrade-playback.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
awk '/^struct AppChangelogSection / { copy=1 }
     /^    static var version110Fix:/ { print "}"; exit }
     copy { print }' "$SOURCE" > "$TEMP/changelog.swift"
cat >> "$TEMP/changelog.swift" <<'SWIFT'
enum L10n {
    static func text(_ zh: String, _ en: String) -> String { zh }
}
let latest = AppChangelogCatalog.latest.displayItems
precondition(latest.map { $0.hasPrefix("* ") } == [true, true] + Array(repeating: false, count: 7))
precondition(latest.contains("新增当前 App 的运存和线程数显示"))
precondition(AppChangelogCatalog.version111.displayItems.filter { $0.hasPrefix("* ") }.count == 3)
SWIFT
xcrun swift "$TEMP/changelog.swift"
printf 'import Foundation\nimport Combine\n' > "$TEMP/playback.swift"
awk '/^private struct PiPUpgradePreviewState/ { copy=1 }
     /^private struct PiPUpgradeTutorialPreview/ { exit }
     copy { sub(/^private /, ""); print }' "$SOURCE" >> "$TEMP/playback.swift"
xcrun swiftc "$TEMP/playback.swift" "$ROOT/tests/upgrade_playback.swift" -o "$TEMP/playback-tests"
"$TEMP/playback-tests"
echo 'PASS: formal release history only, isolated preview and animation lifecycle'
