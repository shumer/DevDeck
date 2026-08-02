#!/bin/bash
# Run the offline suite. Exits non-zero on the first failing expectation.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
swift run --package-path "$HERE" DevDeckTests
