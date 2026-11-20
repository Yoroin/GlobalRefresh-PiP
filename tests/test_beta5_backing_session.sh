#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /private/tmp/pip-beta5-preflight.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
SRC="$ROOT/pip_swift/pip_swift"
cp "$ROOT/tests/beta5_backing_session.swift" "$TEMP/main.swift"
awk '/^    private func cancelBackingVideoJob\(/ {copy=1}
     /^    private func makePlayerItem\(/ {copy=0}
     copy {sub("private func", "func"); print}' "$SRC/ViewController.swift" >> "$TEMP/main.swift"
printf '}\n' >> "$TEMP/main.swift"
awk '/^enum GeneratedPiPVideoCache/ {copy=1} /private static let directoryName = / && copy {exit} copy' \
    "$SRC/DiagnosticsResetManager.swift" >> "$TEMP/main.swift"
printf '%s\n' 'static func videoURL(named: String) -> URL { URL(fileURLWithPath: "/").appendingPathComponent(named) }
static func trim(excluding protectedURLs: [URL]) {}
}
run()' >> "$TEMP/main.swift"
xcrun swiftc "$TEMP/main.swift" -o "$TEMP/test"
"$TEMP/test"
rg -A2 'func stopForFullDataReset\(' "$SRC/ViewController.swift" | rg -q 'cancelBackingVideoJob'
