#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /private/tmp/pip-beta5-video.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
printf 'import Foundation\nimport AVFoundation\nimport CoreVideo\nimport CoreGraphics\n' > "$TEMP/video.swift"
awk '/^private enum PlaceholderVideoFactory/ { copy=1; sub("private enum", "enum") }
     copy && /private static func makePixelBuffer/ {exit} copy {print}' \
    "$ROOT/pip_swift/pip_swift/ViewController.swift" >> "$TEMP/video.swift"
# Only UIKit text drawing is substituted; AVAssetWriter, backpressure, validation and replacement are real.
printf '%s\n' 'static func makePixelBuffer(size: CGSize, text: String) -> CVPixelBuffer? {
    var result: CVPixelBuffer?
    guard CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &result) == kCVReturnSuccess else { return nil }
    return result
} }' >> "$TEMP/video.swift"
xcrun swiftc -suppress-warnings "$TEMP/video.swift" "$ROOT/tests/beta5_backing_video.swift" -o "$TEMP/test"
mkdir "$TEMP/media"
"$TEMP/test" "$TEMP/media"
