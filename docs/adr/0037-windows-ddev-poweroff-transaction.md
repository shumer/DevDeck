# 0037 — Windows all-DDEV poweroff transaction

Date: 2026-10-02
Status: Accepted; qualified and active in Windows Preview446868

The Mac menu calls the shared DDEVEnvironment.powerOff rather than stopping configured projects
one at a time. Windows has several WSL polling workers, and their callers may share a Docker server.
The first command can therefore stop sibling-distribution or off-deck DDEV resources before those
workers receive ordinary stop intent. Existing pending reads can clear that intent or overwrite
physical final state. A new menu item alone would lose the Mac stop/attention behavior.

The tray action captures every configured DDEV-bearing distribution and typed project reference,
including hidden cards. Distinct permanent IDs may share a path. The product prompt freezes and
lists distribution names, preserves the original title/action labels and replaces Mac's machine-only
detail with the actual connected-Docker scope: every DDEV project on those servers, including
off-deck/other-WSL projects, router and SSH agent. Routes are not a shutdown filter or an isolation
boundary. The action does not shut down Docker Desktop/WSL. Cancel is the default and initial focus;
Enter, Escape and window close decline, and only an explicit Power off click accepts. A rounded,
wrapped, accessible tool window inherits owner topmost and does not enter the normal task list.

Protocol1 adds optional bounded powerOff context/result and ddev.poweroff.transaction capability:

| Operation | Effect |
| --- | --- |
| ddev.poweroff.prepare | Validate and reserve an exact typed plan, pin existing DDEV intent and advance observation/cache generations; no CLI or checkout probe. Repeating the same token/plan renews the lease without resetting episodes. |
| ddev.poweroff.run | Run unchanged DDEVEnvironment.powerOff once in the captured actor, retain command outcome and reservation, and return a typed ran acknowledgement without physical statuses/attention. |
| ddev.poweroff.finalize | Reconcile one fresh physical inventory against the exact plan and already registered DDEV watches, commit final status/intent observations and release the reservation. |
| ddev.poweroff.abort | Restore a never-run preparation without manufacturing physical state; if a CLI was entered, reconcile instead of claiming an undo. |

The host captures the actual local polling endpoint for each distribution. Every participant must
advertise the capability before any preparation. All must acknowledge prepare, and all renew the
monotonic 600-second lease before each serial command, including participants whose command already
ran. Shared commands run once per unique confirmed DDEV-bearing distribution. Failed commands may
have physical effects; other routes proceed only after the next complete renewal barrier succeeds.
Changed metadata/routes require new confirmation. Settings visibility/compact changes remain
independent. A worker replacement cannot inherit another actor's plan: token, stable instance,
phase, lease, plan IDs/order, result fields and scoped attention must validate before any projection.
The host never reconnects or retries a run after a lost reply. Cleanup uses finalize for every staged
actor after any attempted command, including notRun siblings; without an attempt it uses abort.
Cleanup continues independently of an interrupted run token.

Worker reservations reject overlapping DDEV mutations without cancelling an already running one;
Arc/plain/remote/check/log work retains its ordinary ownership. The prepared overlay leaves base
watch/settler history intact and hides pinned DDEV episodes while busy, retaining unrelated facts.
Observation epochs fence polls that started before staging/final commit. Never-run abort restores
the base state exactly. After any entered CLI, final fresh physical observations bypass ordinary
settling, retain normal intentional-stop semantics and remove the temporary pin. Inventory
invalidation advances generation without cancelling existing consumers. Fresh reconciliation reads
one inventory per actor and shares it across explicit plan IDs and previously registered DDEV
watches; it does not mass-register hidden references or evict unrelated watches.

The worker keeps a bounded set of terminal receipts and one renewable monotonic lease sleeper.
Expiry releases or reconciles abandoned work; old completed/expired tokens cannot start another
command. Run acknowledgements retain the ran wire shape even if expiry/cancellation has already
reconciled the group. The lease clock is independent of wall-clock check timestamps.

Typed outcomes distinguish notRun/succeeded/failed/timedOut/cancelled/unavailable from inventory
notChecked/available/unavailable/invalid. Reconciled results contain every prepared permanent ID in
order with validated status/metadata/check time, plus command/inventory diagnostics. Missing or
malformed inventory never proves stopped. A command's zero exit and configured stopped observations
prove those observations only; they do not verify router/SSH-agent/off-deck teardown. Unknown states
remain unknown/unavailable and partial failures are reported per route.

Native busy presentation is separate from per-card operation/cancellation. The same visible/hidden
HWNDs, chosen compact preference, positions, logs and actual per-card CTS survive. Lifecycle/QR/
refresh controls are gated, compact Stop stays icon-sized, and there is no inert group Cancel.
Presentation generations/token identity reject stale reads, errors, progress and completion.
Never-run abort restores the exact prior snapshot/check time/control eligibility, including an
existing refresh error. A known physical status with a diagnostic retains metadata; without one the
owner shows unavailable. No automatic reveal or global settings/attention/Seen/queue reset occurs.

Final Core149/0, worker345/0, native1328/0 and installer8/0 pass against the warning-free ARM64
package. Native adds23 coordinator and44 group/dialog checks to the1261 baseline.102 synthetic
views pass in six languages; Russian confirmation/expanded busy and German compact busy scenes
were inspected, without user pixels. Fresh read-only7+2 checks capability hello on the one actual
configured DDEV-bearing distribution and records lifecycleInvoked=false; runtime16 in Ubuntu/Debian,
Arc4/DDEV metadata5/Mac119/product graph/spec140/204 and whitespace pass. Worker lifecycle
qualification uses owned fake CLI/clock/race/transport fixtures, never actual DDEV poweroff.
Only recorded owned Preview437068 was replaced by446868/package
bf3c10f14d724c7b90bcbfe51df429aa with the qualifieda9 worker archive/1203 binary.
windows-poweroff-preview-checks.json proves all nine0x80080 HWNDs and previous IDs/settings/positions/
compact/scopes/preferences/distributions/defaults/startup/original configuration/shortcut/full backup,
singleton0 and old proxies0 preserved. This evidence does not qualify actual off-deck/router/agent
teardown or every configured Docker server.

The original Mac119 source/resources/product graph and shared DDEV kit API remain frozen; changes
are additive worker/native behavior. WIF, SET-04, TRAY-07, native Mac/x64/live remote identities/
phone/display/shell/signing and full migration acceptance remain open.
