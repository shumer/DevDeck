# 0032 — Windows scoped settings checks and browser choices

Date: 2026-10-02
Status: Accepted; qualified and active in the Windows development Preview

The Windows settings window had a searchable sidebar, but keyboard navigation/removal did not
match the Mac flow. Metadata saves disabled the form and replaced other answers with Saved.
The host also lost the original health summary, offered raw browser-profile text and Firefox -P,
and threw when a chosen browser had been uninstalled.

Keep metadata autosave independent of explicit actions. Serialize concurrent flushes through one
async gate, allow editing during a save and scope errors to the current edit revision. Successful
metadata writes stay quiet. Failed metadata retains the editable draft and prevents navigation,
close or shutdown from discarding it; a corrected save clears that guard. One stable new-project
draft ID belongs to the form's whole lifetime.
Ctrl+F focuses search; sidebar arrows navigate and Delete/Backspace use the same confirmation as
form removal. Cancel starts focused and Return/Escape cancel. Token Return invokes explicit API
verification/save; a token is never part of metadata autosave. Project removal changes card
configuration only; account removal detaches references and removes only its credential.

Arc/plain health checks own a row/button. Check on arrival and debounce relevant folder/distro,
command or health-address changes; DDEV has no extra health row. A request's project/reference
identity, generation and form lifetime guard every answer. Cancellation and changed inputs cannot
revive an obsolete result or re-enable an ineligible button. Protocol1 adds optional bounded
checkSummary and checkedAt from the original portable LocalStackStatus/LocalProjectStatus summary,
preserving localized refusal/ownership/readiness detail and old payload compatibility. Native
cards can retain their existing settling state independently of the fresh settings-check summary.
Use the ephemeral `project.check` operation for settings health and fresh DDEV browser-Test URLs.
It reads the same integrations with the same validation but never registers a draft project,
advances settling/attention observations or changes a live card's next result. A separate native
settings-check transport prevents cancellation from aborting local/action or remote requests.
Runtime/language changes reset that transport; application shutdown closes it.

Discover supported installed Edge/Chrome/Firefox/Brave/Vivaldi/Chromium applications through
read-only App Paths/StartMenuInternet registrations and known installation paths. Registry commands
are executable candidates, never inherited arguments; require an existing expected executable.
Read only Chromium Local State profile-name metadata, bounded to 4 MiB and 256 entries. Display friendly
names while persisting directory identity; Default sorts first, then natural directory order.
System/Firefox and browsers with no profiles hide the profile control. Retain saved absent browser
and profile choices until an explicit change. Old Firefox profile values stay stored but are not
passed to Firefox, matching the Mac's external-opening restriction.

One BrowserLaunch.Open path tries the chosen application, falls back to the system default when
it is missing or fails to start, and surfaces a failed default open. URL/profile validation happens
before any launch; arguments retain literal boundaries. Falling back never rewrites preferences,
modifies real browser profiles/defaults or implies that the default browser has the chosen identity.

Offline production regressions cover catalog/profile parsing and read-only metadata, invalid
status boundaries, argument routing, missing/start-failed/default-failed launches and legacy
settings. Portable317/0, Core96/0, native UI1034/0 and installer8/0 pass. Retained production reds
cover browser routing, missing summary fields, quiet-save focus and missing `project.check` support.
Read-only integration covers seven local/two remote cards, dedicated settings transport and fresh
original summaries on two Arc projects. Two-distribution runtime fixtures16/0, Arc runtime/origin4/0
and DDEV metadata5/0 pass. Forty-eight synthetic scenes were generated; the full local/Arc forms
were inspected. The standalone browser fixture clips a lower row and needs a render-height fix;
that image is not accepted visual evidence. Native profile-control checks pass independently.
Owned Preview354968 uses the qualified package and original configuration/shortcut, preserving
nine switcher-excluded widgets, IDs/positions/compact/scopes/preferences/distributions/defaults/
startup, singleton behavior and no remaining old worker proxies.
Real signed-in browser identities, already-running Firefox and account/token actions are live
acceptance gates. Original Mac source/UI/resources/product graph remains frozen; native Mac and
Windows/Linux x64 plus all external release gates still govern migration completion.
