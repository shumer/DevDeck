# 0042 — Windows account provider applicability and retained scopes

Status: Accepted; provider applicability qualified and active in the scoped Windows Preview.
Date: 2026-10-02.

Windows account settings previously offered GitHub organization/repository filters and failed-run
preferences for GitLab. It also sent unused legacy GitLab arrays to a worker that validates request
fields before provider dispatch, so settings-valid inactive data could reject a request. Unrelated
metadata saves reparsed arrays from text. Match provider behavior while retaining saved identities,
inactive data, explicit edits and the existing strict worker contract.

## Decision

Keep one retained account form. GitLab shows its instance Address before the token, original
provider help and browser/profile. GitHub organization/repository fields and failed-run switch are
hidden for GitLab. Both providers retain review/blocked preferences; Notifications renders GitLab
failed-run as a noninteractive, accessible not-applicable dash. The notification master disables
applicable switches without erasing saved preferences.

An unsaved new account may change provider in place, retaining each provider's endpoint draft and
transient GitHub scopes/run choice when switching back. It does not recreate controls or discard
the name-field focus/selection covered by owned tests. Existing accounts cannot change provider.
The first successful new-account commit locks provider while keeping the same permanent account ID.
New GitLab accounts commit
empty scope arrays and failed-run false; transient GitHub fields do not become stored GitLab fields.

`RemoteAccountApplicability.Credential` validates the native account and creates a new request
credential. GitLab sends empty Organizations/Repositories; saved inactive arrays remain exactly
stored, including order, duplicates, null elements and settings-valid raw or over-limit values.
Unedited GitHub arrays are copied exactly. Invalid active GitHub data therefore still fails closed
through the unchanged decoder/worker validator, rather than being dropped into a broader empty
scope. Null whole arrays, unknown providers and invalid native HTTPS endpoints remain invalid.
No startup repair, trimming, deduplication, truncation or worker-schema change is introduced.

Only explicit GitHub scope edits use the existing comma-separated TrimEntries/RemoveEmptyEntries
parsing. Captured field revisions are acknowledged after their save; a later edit while that save
waits remains dirty for the next commit. Unrelated metadata/token/notification changes retain
inactive GitLab arrays and its saved failed-run bit. Snapshot, verification and native credential
construction use the same projection; the separate opt-in test harness is not a live API proof.

The worker still accepts at most32 accounts and64 organizations/repositories per outgoing account,
valid slugs, bounded IDs/labels, HTTPS endpoints and tokens up to2560 UTF-8 bytes. Projecting unused
GitLab fields does not loosen validation for fields actually sent, token/endpoint admission or the
1MiB protocol frame. No GitLab group/project filter is invented.

Explicit nonempty token save/replace and Return keep verification→credential write→configuration
commit→current credential callback→ordinary form callback→old-target cleanup ordering. Rejected or
cancelled verification keeps the draft and performs no credential write. An old-target cleanup
failure after a current commit remains a later failure, not an invented rollback. Tokens have no
persisted settings representation. Browser Test already reads the current `Draft()` at click;
actual fake-button checks confirm current endpoint/browser/profile and invalid-endpoint prevention.
This batch does not claim a newly fixed captured-original-browser defect or a real browser identity.

## Qualification and activation

Four actual old-production provider reds retained wrong fields/Address placement, GitLab run toggle,
unused69 organization/4 repository forwarding and inactive-array reparsing. A first namespace-only
fixture compile error and historical full-native timeouts/geometry/focus failures remain retained.
Bounded owned-window focus preparation changed only the fixture, preserving all assertions/counts.

Actual Core focused4/full222 pass; final package99b3f7da4605432e9bba23fcf965ce5d runs fullnative1541/0,
observed exit0/170.35s, installer8/0 exit0/23.64s with unchanged manifest/no wrapper restoration,
and read-only7local+2remote exit0/9.62s. Provider26 comprises18 six-language form/notification/draft
groups and8 actual request/save/revision/credential/browser/new-account groups, using fake dependency
bodies. Historical standalone26/0 in41.37s is distinct from final full1541. Completed312 six-language synthetic views include30 provider scenes; App/manifest match the final package.

App72C9390873D35DBAF59F9301D15D57871263FD898B25B4649E9479C1C5BF6711 and
manifest657C85E6548C75E1F18D9D158738839B0D53F050DA682D597B851CD58CD052BF bind final package checks.
The actual Core apphost has its own before/after identity; no equality with RID-package hashes is
claimed. Six unchanged-worker null-token wire checks prove request admission only, not HTTP.
Worker379/runtime16/Arc4/metadata5/ordinaryGit30/promisor60 evidence is explicitly reused from
unchanged d9fc85/abd86a; this UI batch does not invent another worker qualification.

Only restored owner6168 was replaced by39204. All nine0x80080 HWNDs and prior card IDs/XY/compact/raw scopes/accounts/preferences/distributions/original configuration/shortcut/full backup/defaults/startup are preserved; absent size stays omitted, singleton0 and old worker proxies0. Mac119/active product graph and spec140/204 remain intact.
Read-only Mac/spec guards and documentation whitespace checks pass. Native provider bodies use fake
verification/writer/browser/discovery and
never mutate real user credentials. Full Core on Windows separately creates/replaces/deletes only
one UUID-owned synthetic Credential Manager entry with finally cleanup. Read-only integration has
capability flags true and lifecycle/provider/read mutation flags false. No real desktop was captured.

## Remaining boundaries

ACC-03 stays Partial: provider token-creation links and stored-token Verify with an empty new-token
field are missing. Current browser Test proof is offline; live provider/HTTP/permissions/browser
identity remain external. SET-11 fresh/missing120 versus omitted legacy60 is deliberate; repositories
remain per-account, without Mac's deck-wide Actions-off disabled watchlist. Review/blocked shortcuts
in the Windows account form are an explicit adaptation, not complete layout identity with Mac.

SET-08 provenance, display homes/settled heights/packing/parking/PMv2, full summon/updater and native
Mac/x64/phone/physical input/accessibility/display/shell/signing/clean-machine qualification remain
open. This unsigned development Preview remains `releaseQualified=false`; full migration is not
complete. Mac resources, preference/vault identities, provider query and worker validation are kept.
