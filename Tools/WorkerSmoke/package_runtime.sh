#!/usr/bin/env bash
set -euo pipefail
# Build artifacts only: run inside the qualified Swift container with a dedicated output mount.
BUILD_ROOT="${1:?SwiftPM scratch path required}"
OUTPUT_ROOT="${2:?dedicated output directory required}"
CONFIGURATION="${3:-debug}"
case "$CONFIGURATION" in debug|release) ;; *) printf '%s\n' 'Use debug or release configuration.' >&2; exit 1 ;; esac
case "$(uname -m)" in aarch64) ARCHITECTURE=arm64 ;; x86_64) ARCHITECTURE=x64 ;; *) printf '%s\n' 'Unsupported worker architecture.' >&2; exit 1 ;; esac
mkdir -p "$OUTPUT_ROOT"
cp "$BUILD_ROOT/$CONFIGURATION/DevDeckWorker" "$OUTPUT_ROOT/DevDeckWorker"
mkdir -p "$OUTPUT_ROOT/lib"
SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$OUTPUT_ROOT/Localizations"
cp -a "$SCRIPT_DIRECTORY/../../Resources/Localizations/." "$OUTPUT_ROOT/Localizations/"
cp -a /usr/lib/swift/linux/. "$OUTPUT_ROOT/lib/"
cat > "$OUTPUT_ROOT/run-worker" <<'SH'
#!/bin/sh
set -eu
RUNTIME_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export LD_LIBRARY_PATH="$RUNTIME_ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$RUNTIME_ROOT/DevDeckWorker" "$@"
SH
chmod +x "$OUTPUT_ROOT/run-worker" "$OUTPUT_ROOT/DevDeckWorker"
printf '{"protocolVersion":1,"attentionVersion":1,"toolchain":"Swift 6.3.3 Jammy","architecture":"%s","configuration":"%s","languages":["en","ru","de","es","fr","it"],"releaseQualified":false}\n' "$ARCHITECTURE" "$CONFIGURATION" > "$OUTPUT_ROOT/runtime.json"
