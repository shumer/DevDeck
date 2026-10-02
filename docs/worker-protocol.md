# WSL worker protocol — v1 in development

Implementation: `Sources/DevDeckWorkerProtocol` and Linux-only executable `DevDeckWorker`.
The native macOS product graph does not include these targets.

Launch inside the selected distribution:

```text
DevDeckWorker --distribution Ubuntu-24.04 --language en
```

If WSL_DISTRO_NAME is present it must match the argument. Stdout contains JSON only; startup and
transport diagnostics use stderr without echoing requests. Language is optional (defaults to en),
limited to en/ru/de/es/fr/it and fixed for the process; packaged original tables live in Localizations.
Each request/response is one UTF-8
JSON object followed by LF. The maximum frame is 1 MiB excluding LF. Oversized input is drained
to the next newline; subsequent requests can recover. EOF processes the final unterminated
frame. Requests may finish out of order; clients correlate IDs. The session allows up to 16
operations, rejects duplicate active IDs and serializes mutations by canonical project path.
EOF cancels pending operations, reaps their CLI process sessions and exits. Completed generic
project servers intentionally outlive the worker, as they do on Mac; cancelling their readiness
check removes only the newly started owned server.

```json
{"protocolVersion":1,"id":"status-1","operation":"project.status","project":{"id":"ddev.project.shop","distribution":"Ubuntu-24.04","kind":"ddev","path":"/home/user/projects/shop"}}
```

Every response includes protocolVersion, distribution and the correlated id. Unparseable or
oversized input has no trustworthy id. Success may carry capabilities, projects, status, logs,
remote, attention or suggestion; acknowledgements and no-match detection may have none of these.
failure includes error.code and a fixed error.message. Optional fields are omitted. The host must
validate version and distribution before accepting a response.

Arc projects may carry `arc: {organization?, site?, localURL?, healthPath?}` and optional existing
startCommand/stopCommand fields. Missing options retain no-install Fusion commands, `.env` local
origin and `/release` health path. Status may carry optional localEditorURL resolved by ArcProject.
An empty path is accepted only for Arc status/check, returning unavailable without commands or attention
probes; lifecycle/log/preflight requests return missingFolder. Bounds, HTTP URLs, organization/site
syntax and health paths are validated before dispatch. The Windows host resolves configured typed
link templates; tokens and project command execution remain outside that presentation resolver.

| Operation | Result | Current behaviour |
| --- | --- | --- |
| hello | capabilities | Advertises only implemented operations |
| ddev.list | projects | Existing DDEVKit inventory parser; distro/path/name/state |
| project.probe | optional suggestion | Plain local folder; existing ProjectProbe reads Compose/package/workspace/Make/env without commands or network |
| project.check | status | Ephemeral settings read through the existing project service; fresh result without card settling or attention observations |
| project.status | status | Existing DDEVKit, ArcKit or ProjectKit service; stable ID/state/branch/site/version |
| project.logs | logs | Existing kit tails, newest 400 lines / 262144 UTF-8 bytes, source/detail and optional absolute Linux filePath |
| attention.dismiss | attention | Dismisses a remembered local problem; live health/sync faults remain |
| project.preflight | success/error | Checks Docker and Fusion tool/port ownership without starting anything |
| project.start / stop / restart | status/error | Executes the selected project's command and confirms its resulting state |
| cancel | success/error | Cancels targetRequestID while stdin remains open |
| remote.snapshot | remote | Shared GitHub PR/inbox/Actions or GitLab MR snapshot, account failures and attention |
| remote.verify | success/error | Minimal read-only identity query; does not return token or identity |
| remote.markRead | success/error | Marks 1–50 validated numeric notification IDs for exactly one account |
| remote.markRest | success/error | Marks non-personal unread notifications from at most ten pages; preserves reviews/mentions/assignments/security |

DDEV status exports optional versionsLine from the shared config formatter (for example,
php 8.4 · mysql 8.0). It is independent of Arc engineVersion and runtime state. Legacy responses
without it remain valid; Windows bounds it to 512 UTF-8 bytes without control characters.
The host owns tool visibility, and new project forms default xhgui off.

Status additionally exports optional repositoryURL and resolved toolLinks (label/url) from the shared
integration, including DDEV Mailpit/xhgui. The host accepts bounded HTTP(S) targets without credentials.

Arc and plain local statuses may also carry optional `checkSummary: {tone, state, detail}` and
`checkedAt` (Unix seconds). These preserve the original kit's settings `CheckSummary`, including
its localized state and diagnostic detail; tone is `good`, `busy`, `bad` or `idle`. The summary is
the answer to this request, even when the existing polling policy keeps the card's preceding
successful state after a transient failure. A host must still correlate the request ID and exact
project/check identity before updating the owning form; neither a cached card state nor an answer
for a former address is a current settings check. An Arc project without a folder can have an
unavailable summary without a timestamp. DDEV omits both fields because its original settings
form has no separate health-check row.

Protocol1 responses without these additions remain valid; clients can retain their existing state
presentation when no summary is supplied. Producers limit state to 512 UTF-8 bytes without control
characters, and detail to 16384 UTF-8 bytes, retaining only LF/tab among control characters and
complete Unicode scalars at the boundary. The Windows client rejects unknown tones, oversized or
malformed text, and non-finite timestamps or values outside 0–253402300799. Treat the strings as
diagnostic text, never executable instructions or link targets. Reading these fields does not run
a lifecycle command, start a service or store a credential. The additive `project.check` operation
returns this original service answer directly and carries no attention. Settings health checks and
the DDEV browser-test lookup use it so an edited address/folder cannot seed another running state,
advance the real card's bad-poll threshold or alter its remembered problem/alert episode. It uses
the same validation and read-only health/Docker boundaries as `project.status`, which remains the
deck's observed/settled polling operation. Capabilities advertise `project.check`; this does not
change protocol1. Older workers without that capability need an isolated settings worker rather
than sending unsaved drafts through the deck's `project.status` attention session.

Project references accept ddev, arc and local kinds, with an optional display title (up to 512 UTF-8
bytes, no controls) independent of the stable ID. Paths must be absolute Linux paths without UNC,
backslashes, traversal components or control characters. Spaces and Unicode remain literal.
The directory must exist inside the worker's distribution. These validation rules route requests;
they do not form a filesystem sandbox for a local process running as the user.

Error codes: invalidRequest, invalidRequestID, unsupportedVersion, unsupportedOperation,
missingProject, wrongDistribution, invalidProject, missingFolder, ddevUnavailable,
frameTooLarge, responseTooLarge, workerBusy, projectBusy, duplicateRequestID, missingTarget,
operationNotFound, cancelled, commandFailed, outcomeNotConfirmed, dockerUnavailable,
linuxNodeUnavailable, fusionUnavailable, composeUnavailable, preflightUnavailable, portConflict,
missingRemote, invalidRemote, remoteUnavailable, credentialsRejected, remoteActionFailed.
DDEV unavailable is distinct from an empty inventory.

Long commands emit response-shaped event frames containing `event: {kind: "progress", line: "…"}`
and the same request ID/distribution/version. Clients consume these until the final response without
an event. Output is stripped of terminal escapes, limited to 2048 characters per line and throttled
to ten events per second. Do not persist raw project CLI logs as telemetry.

Local project references add startCommand, stopCommand, holdsProcess, requiresDocker and healthURL.
Optional subtitle (512 UTF-8 bytes without controls) and openURL (bounded credential-free HTTP(S))
map through the original LocalProject; missing/blank openURL falls back to healthURL. Status siteURL
is the opening address, while healthURL alone decides readiness. project.probe returns suggestion
with subtitle/startCommand/stopCommand/holdsProcess/requiresDocker/healthURL, or no suggestion for
an unrecognised folder. Clients validate this optional response before offering it to the form.
Persistent foreground commands use a dedicated Linux process session, an application-owned log/PID
directory and a PID/start-time identity record. Stop verifies that identity before signalling the
group, then waits for termination; stale or replaced PIDs cannot stop unrelated processes. A returning
start command requires an HTTP(S) health URL. These command fields are user configuration, never
credential storage. Runtime files use a filename-safe mapping without changing the persisted card ID.

Fusion uses the already-installed project CLI (`npx --no-install`), a generated Compose configuration
and Docker's published-port ownership for preflight. A conflict fails before any start/restart command;
the worker never stops the stack holding the port. Restart does not start another stack if Stop failed.
Windows serializes project mutations across its distro workers because Docker is shared.

Remote requests carry `remote: {cardID, kind, accounts, threadIDs?}`. Each account contains stable id,
label, HTTPS endpoint, organizations, repositories and optional token. Kinds are pullRequests, inbox,
actions and mergeRequests. Tokens travel only through stdin; no disk/environment fallback exists.
They live in a per-request in-memory store. Upstream errors are converted to sanitized failure kinds.
The optional memory-only cacheScope is the native host's SHA256 token namespace. Cached transports
are bounded to 64 provider/account/endpoint/credential scopes and retain validators/bodies, never
clients, token stores or authorization headers. Unscoped requests get fresh transports. Notification
mutations invalidate the account cache. Inbox snapshots optionally carry pollIntervalSeconds (60–86400).
Requests validate account counts/IDs, endpoints, repository slugs and tokens before querying.
Notification mutations require one account and strictly numeric thread IDs; all-read is not exposed.
Partial mutation failure instructs refresh because already-completed patches cannot be rolled back.
Remote snapshots include rows, partial failures, caps and shared attention metadata with dedup keys.
Snapshots/status/action responses may additionally carry `attention: {scope, items, alerts,
dockerState?, containerStartAllowed?}`. Scope is the remote card ID or `local:<distribution>`.
Items include stable id/dedup key, tier/mark, translated title/subtitle, optional Unix since, validated
action and enabled/dismissible flags. Alerts include stable episode ID, shared kind/source, translated
title/subtitle/body/subject, click target and quiet flag. Account diagnostics carry no upstream error
body or credential. All-account errors may include an empty diagnostic remote snapshot plus attention;
the host must keep treating this as a failed fetch and preserve its previous rows. Status optionally
includes `notAnswering` and `syncBroken`. Settling, failure episodes, health grace and intentional-stop
suppression use the existing shared Swift policies. Runtime/update release qualification remains open.

Offline tests use fake commands and API responses. Separate live checks include owned process/CLI
fixtures and an opt-in actual DDEV fixture with isolated XDG config and shared router/agent omitted.
Before production deployment, qualify runtime dependencies in both Ubuntu and Debian, Windows
client interop, cancellation and process cleanup. Native Mac validation remains independent.

Local status requests may include refreshCycle (1–128 UTF-8 bytes, no controls). One explicit
cycle shares a DDEV list task/result per worker; changing the cycle retries even unavailable CLI.
Omitting the cycle forces a fresh read, as do discovery/import and action confirmation. Native
Windows local and remote traffic use independent worker connections in the same distribution.
Distribution reset closes both; a channel fault reconnects only that channel.
