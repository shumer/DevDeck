#!/bin/bash
# Copy a GitHub token from an env file into the login Keychain, where DevDeck reads it.
#
# Usage: scripts/seed-token.sh [path-to-env-file]
#        default: ~/Projects/CodeStore/AIData/env.local
#
# The token is never echoed and never written into the repository. `-A` is deliberate: the
# app is ad-hoc signed, so its signature changes on every build and a strict ACL would make
# macOS prompt for the Keychain after each rebuild.
set -euo pipefail

ENV_FILE="${1:-$HOME/Projects/CodeStore/AIData/env.local}"
SERVICE="com.shumer.devdeck"
ACCOUNT="github"

if [ ! -f "$ENV_FILE" ]; then
  echo "No env file at $ENV_FILE" >&2
  exit 1
fi

TOKEN="$(grep -E '^(DEVDECK_GITHUB_TOKEN|GITHUB_TOKEN)=' "$ENV_FILE" | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | xargs)"

if [ -z "$TOKEN" ]; then
  echo "No GITHUB_TOKEN or DEVDECK_GITHUB_TOKEN found in $ENV_FILE" >&2
  exit 1
fi

security add-generic-password -U -A -s "$SERVICE" -a "$ACCOUNT" -w "$TOKEN"
echo "Stored a token for $SERVICE/$ACCOUNT in the login Keychain."
echo "Verify with: scripts/smoke-test.sh"
