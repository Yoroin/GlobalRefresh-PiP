#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d /tmp/pip-ios15-passive-logs.XXXXXX)"
trap 'rm -rf "$TEMP"' EXIT
SOURCE="$ROOT/pip_swift/pip_swift/ViewController.swift"
rg -Fq 'static func makeNativeController(' "$ROOT/pip_swift/pip_swift/PiPCoexistenceExperiment.swift"
# Content refresh is a separate experiment; startup, source geometry and audio stay unchanged.
awk '
    /^                if usesIOS15NativeContentRefresh {/ { nativeControls=1; next }
    nativeControls && /^                } else {/ { next }
    nativeControls && /pipController = AVPictureInPictureController\(contentSource: contentSource\)/ {
        print "                pipController = AVPictureInPictureController(contentSource: contentSource)"; next
    }
    nativeControls && /^                }/ { nativeControls=0; next }
    nativeControls { next }
    /^    private var shouldLogIOS15PiPStartup/ { skip=1 }
    skip && /^    private func requestPiPStartWhenReady/ { skip=0 }
    skip { next }
    /^        if shouldLogIOS15PiPStartup/ { errorBlock=1; next }
    errorBlock && /^        }/ { errorBlock=0; next }
    errorBlock { next }
    /logIOS15PiPStartupCheckpoint\(/ { next }
    { print }
' "$SOURCE" > "$TEMP/without-logs.swift"
git -C "$ROOT" show 7e3c921:pip_swift/pip_swift/ViewController.swift > "$TEMP/official.swift"
for method in preparePiPInfrastructureIfNeeded setupPiPSourceView setupPip setupCustomView \
              attachCustomViewToPiPContent requestPiPStartWhenReady piPStartRetryDelay \
              schedulePiPStartTimeout retryPiPStartWithLegacyControlsStyleFallbackIfNeeded \
              retryLegacyPiPStartIfNeeded prepareCustomViewForPiPStart configurePiPAudioSession \
              releaseMediaAudioSessionForPiPOnly keepPlaybackAlive; do
    for source in official without-logs; do
        awk -v name="$method" '
            $0 ~ "^    private func " name "\\(" { copy=1 }
            copy { print }
            copy && /^    }/ { exit }
        ' "$TEMP/$source.swift" > "$TEMP/$source-$method.swift"
        test -s "$TEMP/$source-$method.swift"
    done
    diff -B "$TEMP/official-$method.swift" "$TEMP/without-logs-$method.swift"
done
rg -A5 'private var shouldPrepareBackingPlayerForPlayback: Bool' "$SOURCE" | rg -q 'return requiresPlayerLayerForPiP'
rg -A3 'private func deferBackingVideoStartIfNeeded' "$SOURCE" | rg -q 'guard shouldPrepareBackingPlayerForPlayback'
for event in 'native construction' 'readiness' 'startPictureInPicture requested' 'startup timeout' \
             'willStart callback' 'didStart callback' 'failedToStart callback'; do
    rg -Fq "\"$event\"" "$SOURCE"
done
printf 'PASS: original host, readiness, timeouts, retries, audio and media source unchanged; construction factory uses native init on iOS15 (runtime policy tested separately)\n'
