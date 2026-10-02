#!/bin/bash
# UI-free offline suite; a separate cache never replaces a Mac app's build products.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift run --package-path "$TASK_ROOT" --scratch-path "${DEVDECK_PORTABLE_BUILD:-$TASK_ROOT/.build/portable}" \
  -Xswiftc -warnings-as-errors DevDeckPortableTests "$@"
