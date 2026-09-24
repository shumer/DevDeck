#!/bin/bash
# What the Arc card checks, asked from a terminal.
#
# The card says "running" when the project's health URL answers 2xx, whoever is answering it.
# That is deliberate - a stack started by hand in a terminal counts - but it means another
# project on the same port, or a container left over from an older checkout, will hold a card
# green after everything you started has stopped. This prints what the app sees, so the two
# can be compared: the address it asks, who answers, who is listening on that port, and which
# containers belong to the checkout.
#
# Reads only settings and Docker. Nothing is started, stopped or changed.
set -u

DEFAULTS_DOMAIN="com.shumer.devdeck"

say() { printf '%s\n' "$*"; }
rule() { printf '%s\n' "------------------------------------------------------------"; }

value_of() {
  # One field of one project, out of the JSON the app stores in its preferences.
  local index="$1" field="$2"
  printf '%s' "$PROJECTS_JSON" | plutil -extract "$index.$field" raw -o - - 2>/dev/null
}

say "DevDeck: Arc local stack check"
say "date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
if [ -d /Applications/DevDeck.app ]; then
  say "app: $(defaults read /Applications/DevDeck.app/Contents/Info CFBundleShortVersionString 2>/dev/null) (build $(defaults read /Applications/DevDeck.app/Contents/Info CFBundleVersion 2>/dev/null))"
else
  say "app: not in /Applications"
fi
say "docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'not answering')"
rule

PROJECTS_B64="$(defaults export "$DEFAULTS_DOMAIN" - 2>/dev/null | plutil -extract 'arc\.projects' raw -o - - 2>/dev/null)"
if [ -z "$PROJECTS_B64" ]; then
  say "No Arc projects are configured in DevDeck (or its preferences could not be read)."
  exit 0
fi
PROJECTS_JSON="$(printf '%s' "$PROJECTS_B64" | base64 -d 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null)"

# The command the card itself runs, so both sides are looking at the same list.
LIST_COMMAND="docker ps --format '{{.Names}}\t{{.Image}}\t{{.Label \"com.docker.compose.project.working_dir\"}}'"
CONTAINERS="$(eval "$LIST_COMMAND" 2>/dev/null)"

index=0
while true; do
  title="$(value_of "$index" title)"
  [ -z "$title" ] && break
  folder="$(value_of "$index" folder)"
  explicit="$(value_of "$index" localURL)"
  health_path="$(value_of "$index" healthPath)"
  [ -z "$health_path" ] && health_path="/release"

  # The address the card asks: what was typed in settings, or the port out of the checkout's
  # .env, the way the app reads it.
  if [ -n "$explicit" ]; then
    base="$explicit"
  else
    port_in_env=""
    if [ -n "$folder" ] && [ -f "$folder/.env" ]; then
      port_in_env="$(grep -E '^[[:space:]]*(export[[:space:]]+)?PORT=' "$folder/.env" | tail -1 | sed -E 's/.*PORT=//; s/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//' | tr -d '[:space:]')"
    fi
    if [ -z "$port_in_env" ] || [ "$port_in_env" = "80" ]; then
      base="http://localhost"
    else
      base="http://localhost:$port_in_env"
    fi
  fi
  origin="$(printf '%s' "$base" | sed -E 's#^([a-z]+://[^/]+).*#\1#')"
  health="$origin/${health_path#/}"
  port="$(printf '%s' "$origin" | sed -E 's#^[a-z]+://[^:]+:?##')"
  [ -z "$port" ] && port=80

  say "PROJECT: $title"
  say "  folder:      ${folder:-(not set)}"
  if [ -n "$explicit" ]; then
    say "  local URL:   $base  (typed in settings)"
  else
    say "  local URL:   $base  (from the checkout's .env)"
  fi
  say "  health URL:  $health   <- the card calls this one 'running' when it answers 2xx"

  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 "$health" 2>/dev/null)"
  say "  answer:      HTTP ${code:-none}$( [ "${code:0:1}" = "2" ] && printf ' (the card shows RUNNING)' || printf ' (the card shows stopped)' )"
  server="$(curl -sI --max-time 6 "$health" 2>/dev/null | grep -iE '^(server|x-powered-by|via):' | tr -d '\r' | paste -sd '; ' -)"
  [ -n "$server" ] && say "  answered by: $server"

  listeners="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | tail -n +2 | awk '{print $1" (pid "$2")"}' | sort -u | paste -sd ', ' -)"
  say "  port $port:   ${listeners:-nothing is listening}"

  if [ -n "$folder" ]; then
    mine="$(printf '%s\n' "$CONTAINERS" | awk -F '\t' -v root="$folder" 'NF>=3 && ($3 == root || index($3, root "/") == 1) {print $1"  "$2}')"
    count="$(printf '%s' "$mine" | grep -c . )"
    say "  containers of this checkout: $count"
    [ "$count" != "0" ] && printf '%s\n' "$mine" | sed 's/^/    /'
  fi

  sharing="$(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null | grep -E "(^|[^0-9]):$port->" | awk -F '\t' '{print $1"  "$2}')"
  [ -n "$sharing" ] && { say "  containers publishing port $port:"; printf '%s\n' "$sharing" | sed 's/^/    /'; }

  rule
  index=$((index + 1))
done

say "All containers Docker is running, as the card reads them:"
if [ -z "$CONTAINERS" ]; then
  say "  (none, or Docker is not answering)"
else
  printf '%s\n' "$CONTAINERS" | awk -F '\t' '{printf "  %-34s %-40s %s\n", $1, $2, $3}'
fi
rule
say "Send this whole output back. The two lines to read together are 'answer' and 'containers"
say "of this checkout'. An answer of 2xx with none of your own containers means something else"
say "holds that port - usually another Arc checkout, since Fusion names its containers the same"
say "for every one of them and only one can run at a time - and that is what keeps the card"
say "green after your own stack has stopped."
