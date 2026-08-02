#!/bin/bash
# Hit the real GitHub API with the same client the panels use, and print what came back.
#
# Reads the token from the Keychain (see scripts/seed-token.sh) or from GITHUB_TOKEN in the
# environment. Prints counts only — never the token.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
swift run --package-path "$HERE" DevDeckSmoke
