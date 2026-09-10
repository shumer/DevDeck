#!/bin/bash
# Run the offline suite. Exits non-zero if any expectation failed.
#
# Any arguments are section filters: `./run-tests.sh projects docker` runs only the sections
# whose names contain one of those words. No arguments runs everything, which is what CI does.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
swift run --package-path "$HERE" DevDeckTests "$@"
