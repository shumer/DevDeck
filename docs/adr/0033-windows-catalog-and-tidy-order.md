# 0033 — Windows catalog and tidy order

Date: 2026-10-02
Status: Accepted; qualified and active in the Windows development Preview

The Mac catalog groups projects as Arc, DDEV and plain, comparing titles as a person reads them:
case-insensitively, with site2 before site10. Windows grouped the tray by kind but retained the
order projects were added within each group; Tidy also consumed stored configuration order.
The same set of projects could therefore appear in a different sequence from the Mac deck.

Use one pure CardOrdering projection for tray presentation and explicit Tidy. Project kinds rank
Arc, DDEV and plain, then titles use the current culture's IgnoreCase and NumericOrdering rules.
An ordinal permanent-ID tie-break makes equivalent titles deterministic. Remote built-in roles
retain RemoteCardCatalog descriptor order: Pull requests, Inbox, Actions and GitLab merge requests.
The first saved card of each kind keeps its resolved role, including a legacy ID. A later canonical
ID is an independent extra card; extras follow natural title/permanent-ID order after those roles.

Never rewrite persisted card arrays to obtain presentation order. Their stable IDs, legacy role
resolution, visibility flags, account scopes, compact state and placements remain authoritative.
Hidden cards remain available as unchecked menu entries and are excluded from Tidy without moving
their stored positions. Renaming changes the next menu/explicit-Tidy order without changing identity.
Settings sidebar sorting/live-state behavior is a separate SET-04 requirement, outside this batch.

Tidy orders the existing visible windows through this same catalog projection, then applies the
already qualified measured-height, 12-DIP gap, work-area wrapping and anchor policy. It moves those
HWNDs without rebuilding views or resetting snapshots, expanded lists, busy progress or polling.
Startup/package activation does not rearrange cards; only the user's explicit Tidy action does.

Reordering saved arrays was rejected because it changes legacy built-in resolution and user data
to solve a presentation problem. A manual number parser was rejected in favor of the platform's
culture-aware comparator. Rebuilding views while arranging was rejected because it discards live
state. Reusing this kind-grouped order for the flat settings sidebar would conflate separate Mac flows.

Source fixtures cover shuffled kinds, site2/site10, equivalent-title ties, Swedish/Cyrillic/numeric
titles, first-kind legacy roles, independent later canonical IDs and unchanged serialized settings.
Seven native cases pass for menu visibility/rename behavior and explicit ordered Tidy with
existing HWNDs, snapshots, busy/compact state, measured gaps, wrap, anchor and saved-array preservation.
The production native regression failed with the old tray ordering; Core104/0, native1041/0 and
installer8/0 now pass in a warning-free ARM64 package. Read-only seven-local/two-remote/tray10s
integration confirms three independent transports; generic runtime16/0, Arc runtime/origin4/0 and
DDEV metadata5/0 pass. The shared worker archive is byte-identical to the qualified317 baseline;
the worker suite was retained, not rerun. Mac119 files/product graph and spec140 IDs/204 files pass.

Only owned Preview354968 was replaced by380656/packagebdacff6431564858b4216b14ea7806d2, with the
same original configuration/shortcut and full backup. Nine0x80080 windows, existing IDs/settings/
positions/compact/scopes/preferences/distributions/defaults/startup remain preserved; singleton exit0
and old worker proxies0 pass. No user's explicit Tidy or project lifecycle was invoked during qualification.
Forty-eight six-language synthetic scenes were generated; local/Arc/account forms were inspected.
The standalone browser's320-DIP height now shows its profile, but its margin root still crops the
right edge. That fixture needs correction in the next tray batch and is not complete browser-bitmap
visual acceptance; functional full-settings/profile checks pass independently.
Original Mac source/resources/product graph and worker behavior stay unchanged. Native Mac,
Windows/Linux x64, real browser/account/phone/display/signing and complete migration gates remain open.
