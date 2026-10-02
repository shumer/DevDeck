# 0043 — Windows token creation pages and current stored-token checks

Status: Accepted; token-action subset qualified and active in the scoped Windows Preview.
Date: 2026-10-02.

Windows account settings verified a nonempty replacement before writing it, but lacked provider
creation links and a separate check of the saved token. Empty replacement input rejected the
action. Add those explicit controls while preserving the replacement draft, account identity,
ordinary autosave errors and retained card state.

## Decision

Keep the retained provider-specific form. Cached Credential Manager availability is a presence
fact, distinct from API acceptance. Show Create token and a separate Verify saved token button.
Stored Verify needs a committed account and known presence; a disabled account remains checkable.
Empty-input Verify/Return for an existing account uses the stored path. Explicit stored Verify uses
the saved value even with a half-entered replacement and never fills or clears the password field.
Nonempty Verify and save retains verification→credential write→configuration commit→current
credential callback→ordinary form callback→old-target cleanup ordering.

Creation captures the current provider, exact edited API endpoint and selected browser/profile.
An unnamed new account or unrelated incomplete scope draft may open a valid creation page without
persisting/validating the whole account, reading a credential, acquiring a worker or mutating a
provider API. Only lexical api.github.com or api.github.com:443, ignoring case and with an absent
or exactly-slash path, maps automatically to GitHub's fixed personal-token page. Other safe GitHub
API endpoints require a complete HTTPS token-page address in an owned Enterprise dialog. It
starts blank, shows the captured API endpoint and defaults Return/Escape to Cancel. Explicit Open
uses the entered address once; it is never saved or guessed from /api/v3. GitLab appends its fixed
token-page suffix to the complete current instance prefix, retaining path case/escaping/port and
name=DevDeck/scopes=read_api fields. Selected-browser opening is a Windows adaptation to Mac's
default-browser action, not proof of signed-in browser identity.

Pure AccountTokenActions admits at most2048 UTF-8 bytes before and after URI escaping, HTTPS and
positive ports, without supplied user-info/query/fragment, raw controls, malformed UTF16/percent
escapes, raw backslashes or encoded controls. Leading/trailing whitespace is rejected; normal
internal path escaping is retained. GitLab's appended query is fixed and validated. This boundary
does not rewrite saved endpoints, change CredentialTarget, grant scopes automatically or loosen
account/worker validation.

Stored Verify captures committed ID/provider/exact endpoint/CredentialTarget, owned raw scopes,
the full configured WorkerSettings record, form-owner epoch and replacement revision. Validate
before/after worker acquisition, immediately before/after the one credential read and before
publication. Endpoint edits require replacement verification first; a saved trailing slash stays
exact. Label/browser drafts do not invent a credential identity. Removed/replaced accounts,
changed distribution/runtime/language, edited passwords and closing/replaced forms cannot receive
late status/cache updates. Application checks precede typed CallAsync; they are not an OS/vault/
configuration transaction or wire-time compare-and-swap after the transport gate.

Acquire only a configured remote settingsChecks client with WorkerManager.GetExactAsync. Under
the existing manager gate, remember its actual creation route, reuse only an equal full record
and replace only the requested key otherwise. Legacy GetAsync reuse stays intact. There are now
at most five lazy ownership slots per distribution: ordinary local/shared remote/checkout plus
settingsChecks local and settingsChecks remote; no requirement to run all five processes.
The captured exact-client closure submits unchanged remote.verify once with bounded namespace
verify. GitHub keeps copied raw active arrays; GitLab projects inactive arrays empty only on the
wire, preserving at-rest order/duplicates/nulls and preferences. No Ensure/install/discovery,
environment fallback, card-session adoption, lost-reply retry or attention refresh belongs to it.

A scoped autosave lease stops debounce/new or queued flushes before waiting for an already
admitted save. Release the save gate before RPC. Dirty revisions, failed-save state and metadata
errors survive; only genuinely dirty metadata resumes ordinary debounce later, so unchanged
failed drafts are not silently retried. Token progress/results have their own row. Null/empty
reads and current rejections remain localized failures without writes or a false validity claim.
Success publishes known presence to only the exact current target, without another vault lookup
or form rebuild. The temporary token reference is cleared in finally; this is not a memory-zeroing
guarantee.

SettingsWindow owns a dedicated token epoch. Selection/close entry invalidates old actions before
Flush or native Closing's Dispatcher.Yield, including refused transitions restoring the same
invalid draft. Sidebar/search/runtime reloads and new-account commit retain the form and epoch.
Currentness also checks registered owner, actual page/form and lifetime. Exact committed-target
cache callbacks reject siblings and queued old-owner publications.

## Qualification and activation

Corrected old-production baselines captured missing creation, empty-existing and separate-stored
actions. An actual default-manager red captured stale route reuse before GetExactAsync. An earlier
60.2s CLI-catch timeout and a2.87s new-account browser-premise fixture failure remain retained;
they are not product qualification. Explicit selected-browser/changed-ticket premises repaired
only that fixture, retaining counts/assertions and requiring a fresh frozen package.

Final package04928307578842e6b1c3337fdf206cf0 passed actual Core focused4/0 in0.37s/full226/0 in59.84s,
token component30/0 in32.83s, fullnative1571/0 in189.8s, installer8/0 in24.29s with identical
manifest/no wrapper restoration and read-only7local+2remote in12.09s with mutation flags false.
Completed342 fresh six-language synthetic scenes include30 token scenes; six new English/Russian
scenes were visually reviewed. Generated scenes are not all inspected bitmaps.

Source snapshot473 SHA256 A34F5C43F307CA0A8431CC7EE3AB7FEE90B7DF471680C20DC3A5900863D92948,
App2126D1557187A8094F25FC31A262839F4BBDCBFF6D91C73702190AB4223A0415 and
manifest8C3FB513177E66F10339706A53C7B2A0ED3190925D2DA8FBED58371E182A90D6 correlate the final candidate.
Actual Core apphost identity is tracked separately, without claiming equality to RID-package DLLs.

The30 groups are12 six-language presentation/creation groups plus18 functional groups exercising
Enterprise/current tickets, cache/reader/rejection, acquisition/read/RPC/password guards, dirty/
failed/admitted autosave, real manager bookkeeping, queued owned Return, replacement ordering,
retained-parent close/selection ABA/new commit and positive hidden owners/global gate/attention/
Seen/queues/check-time preservation. They use owned stores, fake readers/openers/verifiers and
one owned fake stdin/stdout child through the actual manager, not real accounts, WSL, HTTP or
browsers. The full Windows Core suite separately writes/replaces/deletes a UUID-owned synthetic
Credential Manager entry with finally cleanup.

Only recorded39204 was replaced by current68312. All nine0x80080 HWNDs and prior IDs/XY/compact/raw
accounts/scopes/preferences/distributions/original configuration/shortcut/full backup/defaults/
startup are preserved; absent geometry stays omitted, singleton0/old worker proxies0. Mac119 frozen
files/active graph and spec140/204 guards pass without native Mac execution. Exact d9fc85 archive/
abd86a binary worker379/runtime16/Arc4/metadata5/ownedGit30+promisor60 evidence is reused, not rerun.

## Boundaries

Opening a page does not create/revoke/rotate a token through an API or prove broader permissions.
Live provider/browser identity remains external. Existing nonempty replacement still uses
verify.+ID, which exceeds the128-byte wire namespace when the account ID already uses that limit;
stored checks use fixed verify.
Existing Draft() trims an endpoint's trailing slash, so a legacy slash-bound account's unrelated
metadata save can require replacement first. Those old replacement/metadata limitations remain.
SET-08, deck-wide Actions watchlist, display/summon/updater, physical input/accessibility/native
Mac/x64/phone/shell/signing/clean-machine and full migration stay open; releaseQualified=false.
No worker operation/schema/default migration or frozen Mac resource/UI changes were introduced.

See [qualification](../windows-qualification.md) and the retained historical
[provider applicability decision](0042-windows-account-provider-applicability.md).
