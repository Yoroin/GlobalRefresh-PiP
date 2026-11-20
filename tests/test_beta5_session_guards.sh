#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /private/tmp/pip-beta5-session.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
SRC="$ROOT/pip_swift/pip_swift/ViewController.swift"
cp "$ROOT/tests/beta5_session_guards.swift" "$TEMP/main.swift"
awk '/^class ViewController:/{vc=1}
     vc && (/^    func pictureInPictureControllerWillStartPictureInPicture/ ||
            /^    func pictureInPictureController\($/ ||
            /^    func pictureInPictureController\(.*failedToStartPictureInPictureWithError/ ||
            /^    private func validateOwnPiPState\(/) {keep=1; sub("private func validateOwnPiPState", "func validateOwnPiPState")}
     keep {print}
     keep && /^    }/ {keep=0}' "$SRC" >> "$TEMP/main.swift"
printf '}\nrun()\n' >> "$TEMP/main.swift"
xcrun swiftc "$TEMP/main.swift" -o "$TEMP/test"
"$TEMP/test"
rg -Fq 'pipController?.delegate = nil' "$SRC"
rg -Fq 'observed === self.pipController' "$SRC"
