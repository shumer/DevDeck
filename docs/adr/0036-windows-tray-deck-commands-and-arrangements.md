# 0036 — Windows tray deck commands and arrangements

Date: 2026-10-02
Status: Accepted; qualified and active in Windows Preview437068

The Windows main tray lacked the original pull-request dashboard, all-active refresh and saved
arrangement navigation. Settings arrangement and Deck mode actions used generic SaveSettingsAsync,
waiting for unrelated lifecycle work and resetting attention/check-time/notification baselines.

Open the original fixed public `https://github.com/pulls` dashboard with the first enabled GitHub
account's browser/profile in saved order, or system when none exists. Card visibility/scopes, API
endpoint and token availability do not choose this target. Use the central browser launch/fallback
policy and inject a recorder for native tests; never launch a browser or read a token for qualification.

Main-tray refresh uses existing RefreshAllAsync: active eligible local cards share one cycle and
remote cards use independent reads. Hidden cards, hosted-only locals and busy cards skip new work;
repeated refresh coalesces already pending reads. Lifecycle operations and mutation/read cancellation
tokens remain untouched, and failure in one distribution does not discard another result.

Capture every configured permanent ID, chosen Enabled and compact preferences and saved XY for an
arrangement. Matching requires the same full ID set and all those values, independent of persisted
array order or last chosen name; menu rebuild computes fresh ticks. More than one arrangement can
match the same layout. A drag, visibility/preference change or configured-ID change removes a match.
Names are trimmed and validated; Windows retains its existing case-insensitive identity. Overwrite
keeps original spelling and array position. Only an explicit new save bounds the list to the newest
eight; startup/load and overwriting a longer legacy list never truncate it.

SaveArrangement and ForgetArrangement persist only arrangement metadata without acquiring the
lifecycle gate or resetting attention, check time, Seen, queued sources, workers or native owners.
Missing Forget and stale removed Apply names are no-ops. Apply visits still-configured saved IDs:
qualified exact-ID visibility first, chosen compact next, saved XY last. Unknown/deleted IDs are
skipped; new/unrelated cards and all runtime/account/preferences metadata remain untouched. Retained
HWNDs/snapshots/jobs/reads survive. Visibility retains the established scoped pruning and quiet reveal.
If a mutating remote card refuses a requested collapse, its current preference and work remain;
position still applies. The match remains false when incomplete, and an idle retry can finish it.
An already-matching compact preference remains honest while busy.

The tray name dialog shares exact existing rounded settings TextBox/Button styles with a fallback
that constructs no SettingsWindow. Explicit owner/Application styles override it. Localized detail,
accessible names, wrapped content and input focus remain; valid Save/Return returns a trimmed name,
Cancel/Escape returns null, and blank/control names or names over128 characters after trimming cannot save. There is no
generic success dialog. Explicit named Forget appears in a Remove submenu and the Deck page; this
adapts Mac's Option-only reachability. Attention-menu modifier twins remain a separate requirement.

Settings Deck Save/Forget/Apply call the same precise controller methods. ReconcileArrangements only
updates the list/current selection on the Deck page, preserving the name input, focus, cursor,
navigation and every other form/token/error draft. Selection-dependent Apply/Forget eligibility is
rechecked after action completion. Existing Floating/Locked controls use precise setters, persist
before assigning settings, and ReconcileDeckModes only updates open Deck switches; neither path
waits for lifecycle work or resets baselines.

The production red windows-commands-red-ui.json records the missing actual dashboard menu action.
Core132/0 passes warning-free Release. Unchanged worker328/b5c1 archive/suite qualification is
explicitly reused, not rerun. Native source includes six presence, ten action, fourteen arrangement
and sixty-six dialog/Deck checks, for1261 total. Actual menu/button/keyboard paths use owned settings,
fake browser/name readers and pending injected transports; nonempty attention/queued/pending sources
and native HWNDs verify retained state. Final polished native1261/0 and installer8/0 pass against the
warning-free ARM64 package. Fresh read-only7+2, runtime16/0, Arc4/0, DDEV metadata5/0 and84 synthetic
views pass; Mac119/product graph/spec140/204 and whitespace remain clean. Only owned Preview413076
was replaced by437068/package db0486ac622a43e083fbda7abbd848fb.
windows-commands-preview-checks.json proves all nine0x80080 windows and previous IDs/settings/
positions/compact/scopes/preferences/distributions/defaults/startup/original configuration/shortcut/
full backup preserved, singleton0 and old proxies0.

Frozen Mac119 files/resources/product graph and shared worker remain unchanged for this batch.
No real project lifecycle/credential/browser/notification/global network-policy action or desktop
capture is used for synthetic qualification. Whole TRAY-06 remains partial for all-DDEV poweroff;
WIF, SET-04, TRAY-07, native Mac/x64/live identities/phone/display/shell/signing and full migration
gates remain open.
