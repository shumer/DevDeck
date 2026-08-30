#!/bin/bash
# Copy a GitHub token from an env file into the login Keychain, where DevDeck reads it.
#
# Usage: scripts/seed-token.sh [--account <id>] [--var <NAME>] [path-to-env-file]
#
#   --account   which DevDeck account to seed. `default` is the first account and uses the
#               un-suffixed Keychain key; anything else uses `github.<id>`, exactly as
#               GitHubAccount.tokenKey does. Default: default.
#   --var       which variable to read from the env file. Default: the first of
#               DEVDECK_GITHUB_TOKEN or GITHUB_TOKEN that is present.
#   env file    default: ~/Projects/CodeStore/AIData/env.local
#
# Examples:
#   scripts/seed-token.sh                                   # the default account, GITHUB_TOKEN
#   scripts/seed-token.sh --var SHUMER_GITHUB_TOKEN         # a differently named token
#   scripts/seed-token.sh --account work --var WORK_TOKEN   # a second account
#
# One token per account is the whole point: a fine-grained token is approved per organisation,
# so no single one covers every employer. The deck asks each account in turn and merges what
# comes back.
#
# The token is never echoed and never written into the repository. `-A` is deliberate: the app
# is ad-hoc signed, so its signature changes on every build and a strict ACL would make macOS
# prompt for the Keychain after each rebuild.
set -euo pipefail

SERVICE="com.shumer.devdeck"
ACCOUNT_ID="default"
VARIABLE=""
ENV_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --account) ACCOUNT_ID="${2:-}"; shift 2 ;;
    --var)     VARIABLE="${2:-}";   shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *)         ENV_FILE="$1";       shift ;;
  esac
done

ENV_FILE="${ENV_FILE:-$HOME/Projects/CodeStore/AIData/env.local}"

if [ ! -f "$ENV_FILE" ]; then
  echo "No env file at $ENV_FILE" >&2
  exit 1
fi

# The first account keeps the un-suffixed key, so a token stored before accounts existed keeps
# working with no migration. This must match GitHubAccount.tokenKey.
if [ "$ACCOUNT_ID" = "default" ]; then
  ACCOUNT="github"
else
  ACCOUNT="github.$ACCOUNT_ID"
fi

PATTERN="${VARIABLE:-DEVDECK_GITHUB_TOKEN|GITHUB_TOKEN}"
TOKEN="$(grep -E "^($PATTERN)=" "$ENV_FILE" | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | xargs)"

if [ -z "$TOKEN" ]; then
  echo "No ${VARIABLE:-GITHUB_TOKEN or DEVDECK_GITHUB_TOKEN} found in $ENV_FILE" >&2
  exit 1
fi

# Checked before it is stored: a rejected token that lands in the Keychain silently turns into
# a card that fails for a reason nobody can see.
LOGIN="$(curl -sf -H "Authorization: bearer $TOKEN" https://api.github.com/user \
  | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin).get("login",""))' 2>/dev/null || true)"

if [ -z "$LOGIN" ]; then
  echo "GitHub rejected that token - nothing was stored." >&2
  exit 1
fi

security add-generic-password -U -A -s "$SERVICE" -a "$ACCOUNT" -w "$TOKEN"
echo "Stored the token of $LOGIN for $SERVICE/$ACCOUNT in the login Keychain."
echo "Verify with: scripts/smoke-test.sh"
