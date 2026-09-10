#!/bin/bash
# Hit the real GitHub and GitLab APIs with the same clients the panels use, and print what
# came back.
#
# Reads the tokens from the Keychain (see scripts/seed-token.sh) or from GITHUB_TOKEN and
# GITLAB_TOKEN in the environment, and the GitLab instances from the app's own settings.
# Prints counts only - never a token.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
swift run --package-path "$HERE" DevDeckSmoke
