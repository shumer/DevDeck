# Windows qualification — 2026-10-03

Current scoped completeness checkpoint: Preview118080/package781a6f1f941948a88d79463178da0fb8 is
qualified and active for the log/account/Inbox fixes in
[ADR0045](adr/0045-windows-completeness-logs-accounts-inbox.md). Most suite observations were collected
on2026-10-02 UTC; final activation verification was confirmed on the new local day. This is a
development checkpoint, not full Mac parity or a Windows release. SET-08/ACC-03/provider history
below remains valid historical evidence.

| Completeness evidence | Actual result and limit |
| --- | --- |
| Same-source publisher | exit0/21.19s within300s; frozen481 inputs/package identity |
| Native components |logs3/0 exit0/2.88s and accounts3/0 exit0/8.83s, each within180s; formal premises not counted as passed groups |
| Full native exact package |1593/0, exit0/212.97s within420s; prior two-write replacement assertion retained |
| Installer exact package |8/0, exit0/25.40s within180s; identical manifest/owned fixture, no wrapper restoration |
| Real read-only integration |7local+2remote, exit0/12.62s within180s; checkoutCommandsInvoked/inboxReadMutationInvoked/powerOffLifecycleInvoked=false |
| Synthetic artwork |372 completed six-language scenes, exit0/400.17s within1200s outer/30s per child; eight EN/RU frames visually reviewed, not all372 |
| Explicitly reused Core |focused4/full226 original exit0/0.33s/61.01s within60/420s;70 Core/Test/locale inputs identical, not rerun |
| Explicitly reused worker |focused3/full382 original exit0/5.75s/2.94s within180/240s;208 shared/worker/portable/package inputs identical, release/archive execution reused |
| New worker runtime |ADE5/F683 generic16+Arc4+metadata5=25, exit0/19.98s within420s in Ubuntu24.04/Debian; original settings/backup/runtime retained |
| New owned Git |ordinary30/0 exit0/6.68s and fake-local promisor60/0 exit0/6.62s, each within420s; no user repository/global config/network mutation or general offline guarantee |
| Activation/preservation |78356→118080, updater exit0/120.10s and corrected-datetime verifier exit0/113.49s, each within180s/no timeout. Nine0x80080 HWNDs and all card/ID/XY/compact/raw scope/account/Seen/preferences/distributions/configuration/shortcut/full backup/defaults/startup preserved; absent geometry omitted; exactly two admitted RuntimeDirectory transitions to ADE5, old D9 intact, singleton0/old proxies0 |
| Mac/spec |Fresh source guards exit0:119 frozen files/active Mac graph and140 unique IDs/204 references; no native Mac build/UI claim |

Final481-file source snapshot SHA256
`FB2862E9CF6458662CC17C04922CCC608F530F1328DE0AFCC732F3FE358756DA`, App
`F27D8B58D538CC64CB385984AF7F7E8EB7A25B33E2DD6A7E519CF80402732AB2` and manifest
`A0A538E7A4348AF41DD87E54F5BB56B8ECB6E5DB4112360FF2D9D8E5BA283278` bind the current packaged gates.
Worker archive `ADE5D13DCC1233431F4B075820A2A67F2B585EF56E9A4D41CDF8E3A922FB2236` and binary
`F6839158CB8ADA40B140B5FE09FB2BAC127FF3E075EAEB5765ECF199D4F73386` replace the selected runtime routes;
old D9 files remain. The older null-token wire6 receipt was not requalified for this new archive.

Nine retained behavioral failures have meaningful green counterparts: three log and three account
old-body Windows cases, two worker bulk cases and the normalized replacement→stored-check case.
The first8854 full run exited1/35.84s and caught a replacement regression; the original two-write
assertion was preserved. Normalization-only c11fa4 follow-up exited1/1.93s before the guarded field
sync. These are retained failure history, not nine additional passed component groups. An initial
activation guard rejected a mismatched proof schema before stopping anything; the first verifier
then rejected automatically parsed datetime input. Corrected helpers used the existing distinct
EOF proofs and exact ISO strings. Their failed receipts remain; no product/source change was
needed for these helper defects and the completed verifier confirms the current owner.

The real read-only probe found seven stopped local cards, two Arc editor origins and five DDEV
version lines. Phone NotRunning is honest unavailable state, not phone reachability. PR loaded
five rows without failures; Inbox retained fourteen rows and a typed forbidden account failure.
GitLab was unconfigured. No live notification mutation or complete account-permission acceptance
is inferred. Components use owned fake IO; actual configured integration is read-only. Full Core
separately writes and finally deletes a UUID-owned synthetic native Windows vault entry.

Before these fixes, the140-ID source audit at973b564 classified58 implemented,25 adapted,46 partial,
9 missing,1 internal and1 planned. This historical triage is not a passed-feature tally. Remaining
notification/settings, typed Inbox outcomes, display/summon/app branding/updater implementation,
native Mac/x64/live permissions/browser/phone/physical input/accessibility/Shell/signing/clean-machine
gates keep fullParityConfirmed=false and releaseQualified=false. The private reviewer handoff and
qualification helpers remain uncommitted.

Historical SET-08 checkpoint: Preview78356/package9e1090ab67b94081853edfd12e72554e was qualified and
active for the Windows running-copy provenance adaptation. General shows immutable startup
informational/assembly version, App-module MVID and separate process/module locations. MVID is
neither whole-package identity nor release trust; native Mac and full migration remain unqualified.
The ACC-03/provider/SET-02 records below remain historical valid evidence.

| SET-08 evidence | Actual result and limit |
| --- | --- |
| Same-source SDK | Tests exit0/19.59s and publisher exit0/19.70s, zero warnings/errors; frozen source before/after identity |
| Core helper/full suite | Actual apphost focused4 exit0/0.30s within60s and full226 exit0/58.30s within420s; separate artifact identity, not RID-package hash equality |
| Provenance component |16/0, exit0/11.30s within180s; retained build/location2, six-language layout6 and functional8 groups, including three actual sample factories |
| Full native exact package |1587/0, exit0/208.14s within420s; previous token30/provider26 and strict state-preservation checks retained |
| Installer exact package |8/0, exit0/24.08s within180s; identical manifest/no wrapper restoration and identical owned installer fixture |
| Read-only integration |7local+2remote, exit0/11.88s within180s; checkoutCommandsInvoked, inboxReadMutationInvoked and powerOffLifecycleInvoked all false |
| Synthetic artwork |372 completed fresh scenes, exit0/390.85s within1200s outer/30s per child; provenance30/token30/provider30 across six languages, same final App/manifest. Eight English/Russian frames visually reviewed, not all372 |
| Activation/preservation |68312→74628, then controlled same-artifact recovery74628→78356; native verifier exit0/21.56s. All nine0x80080 HWNDs, IDs/XY/compact/raw scopes/accounts/preferences/distributions/original configuration/shortcut/full backup/defaults/startup preserved; absent geometry omitted, singleton0/old worker proxies0 |
| Worker/runtime |Exact d9fc85 archive/abd86a binary baseline379/runtime16/Arc4/metadata5/ownedGit30+promisor60/null-wire6 reused; not rerun for SET-08 |
| Mac/spec |119 frozen files/active graph and140 features/204 references intact in source guards; no native Mac build/UI claim |

Final477-file source snapshot SHA256
`BEA592AABA7CA659C26FAA00A32F0A43C65B3EBF64990E04664ECEB515AF0112`, App
`EDE7F9BC9CE5033EAF082653C73DDA065865D9C0194D90DCD96DCD93FCC8338B` and manifest
`AB4C276059AEC6532C86F727F27FCF2785DFC74DD02A07F2334691FD4AFF3135` correlate the final packaged gates.
Separate Core apphost artifacts are Tests
`CF9089950F9FC7E229B117174575EC20D864677E6F4020ACBB2DB2C336848D64` and Core
`5879C3D0A0675C932E03AB759E060D2498E3FCDDBD88DAFFAC1E040036BC580F`.

The scoped updater exited0 in23.93s and replaced only68312 with74628. Its stdout collector then
waited for EOF because the running Preview inherited a redirected pipe;23.93s excludes that
collector stall. The original exit/log remain retained. After exact ownership/configuration/hash
checks, only74628 was stopped and the same package/configuration was launched without redirected
helper handles. Recovery exited0 in1.55s as78356; the completed native verifier confirms preservation.
No product/source/package change was made for this collector defect.

Two actual old-General build/location reds exited1 in1.56s/1.20s after positive controls/HWND/state
premises. The earlier381e03 candidate's proofs remain separate: a sample-only startup-fact
omission was caught before any renderer/artwork output. Corrected actual generic/geometry/empty-
sidebar factories export fake facts; production startup capture is unchanged. Their meaningful
lifetime assertions stay inside the unchanged16 groups. No actual-path screenshot or OS fault is
inferred. The final qualification above uses only corrected9e1090.

SET-08 adds no disk/manifest/git lookup, settings schema, vault action, worker operation or Mac UI
change. Fake updater checks prove the actual raw-info/runtime dispatch body without HTTP/browser.
The full Core suite separately uses a UUID-owned synthetic Credential Manager entry with finally
cleanup. Five lazy per-distribution ownership slots remain; no additional channel was introduced.
Mac marketing/build-counter/translocation/update-install behavior, native Mac/x64/live identities/
browser/phone/display/summon/input/accessibility/shell/signing/clean-machine/full migration remain
open; releaseQualified=false. See [ADR0044](adr/0044-windows-running-build-provenance.md).

Historical ACC-03 checkpoint: Preview68312/package04928307578842e6b1c3337fdf206cf0 was qualified and
activated for provider creation pages and separate/empty-input stored-token checks. Only the recorded
provider owner39204 was replaced. Earlier provider/SET-02 checkpoints below remain historical valid
evidence, not the current executable or a completed migration.

| ACC-03 evidence | Actual result and limit |
| --- | --- |
| Core helper/full suite | Actual apphost focused4 exit0/0.37s and full226 exit0/59.84s; separate before/after artifact identity, not RID-package hash equality |
| Token component |30/0, exit0/32.83s;12 six-language presentation/creation groups plus18 functional groups, using owned fake dependencies and one fake child through the actual manager |
| Full native exact package |1571/0, exit0/189.8s, complete report within420s; no assertion/count relaxation |
| Installer exact package |8/0, exit0/24.29s, identical before/after manifest, no wrapper restoration, identical owned installer fixture |
| Read-only integration |7local+2remote, exit0/12.09s, exact inventory/isolated channels/shared cadence; checkoutCommandsInvoked, inboxReadMutationInvoked and powerOffLifecycleInvoked all false |
| Synthetic artwork |342 completed fresh scenes, including30 token scenes in six languages, exit0/338.97s within1200s; final App/manifest unchanged. Six new English/Russian scenes visually reviewed |
| Activation/preservation |39204→68312; all nine0x80080 HWNDs, IDs/XY/compact/raw accounts/scopes/preferences/distributions/original configuration/shortcut/full backup/defaults/startup preserved; absent geometry omitted, singleton0/old worker proxies0 |
| Worker/runtime |Exact d9fc85 archive/abd86a binary baseline379/runtime16/Arc4/metadata5/ownedGit30+promisor60 reused, not newly rerun or rebuilt |
| Mac/spec |Fresh guards:119 frozen files/active graph and140 features/204 references intact; no native Mac build/UI claim |

Final473-file source snapshot SHA256
`A34F5C43F307CA0A8431CC7EE3AB7FEE90B7DF471680C20DC3A5900863D92948`, App
`2126D1557187A8094F25FC31A262839F4BBDCBFF6D91C73702190AB4223A0415` and manifest
`8C3FB513177E66F10339706A53C7B2A0ED3190925D2DA8FBED58371E182A90D6` correlate the frozen candidate.
The native/installer/read-only/render receipts refer to that exact package.

Retained history includes the60.2s old-baseline harness timeout caused by a missing CLI catch route;
it was not a missing-function proof. The corrected baseline captured three actual old-body reds,
and an independent exact-route baseline caught stale worker reuse before GetExactAsync. A preceding
component failed after2.87s because a new-account fixture had not selected its asserted browser/
profile. Explicit selection/changed-ticket premises fixed only the fixture; all30 grouped assertions
and counts remained, and every final gate used the newly frozen package. Older provider failures
below remain separate historical evidence.

Owned token checks use fake credential reads/writes, browser/API bodies and one fake worker child;
they do not access real user accounts, WSL provider HTTP or a real browser. The full Windows Core
suite separately writes/replaces/deletes a UUID-owned synthetic Credential Manager entry with
finally cleanup. Read-only integration invokes no project lifecycle or provider/Inbox mutation.
Five lazy ownership slots per distribution include separate local/remote settingsChecks clients;
the new remote slot's exact-route bookkeeping is proven by the fake child, not live credentials.

Live provider permissions/browser identity, old nonempty replacement maximum-ID namespace and
slash-normalizing metadata limitations remained; SET-08 was separate at this checkpoint. Display/summon/updater/native Mac/x64/phone/physical
input/accessibility/shell/signing/clean-machine/full migration remain open. No merge/release is
qualified; releaseQualified=false. See [ADR0043](adr/0043-windows-account-token-actions.md).

Historical provider applicability checkpoint — 2026-10-02: Preview39204/package
99b3f7da4605432e9bba23fcf965ce5d was qualified and activated for this subset. The prior SET-02 package3779 was
restored as owner6168 after an external reboot, then only that recorded owner was replaced.
Earlier PID627264 and the dated matrix below are historical.

| ACCOUNT evidence | Actual result and limit |
| --- | --- |
| Core provider applicability | Actual apphost focused4/full222 passed; full222 exit0/58.62s, artifact before/after correlation separate from RID package |
| Provider bodies |26 owned fake request/credential/browser/discovery groups included in fullnative; historical standalone26 exit0/41.37s remains distinct |
| Full native exact package |1541/0, observed exit0/170.35s; original assertions/count retained |
| Installer exact package |8/0, exit0/23.64s, identical manifest/no wrapper restoration |
| Read-only integration |7local+2remote, exit0/9.62s; isolated channels/shared cadence/tray/capabilities pass; checkout/Inbox/power-off invocation flags false |
| Exact unchanged worker wire |6 null-token validation/admission checks; no HTTP or live identity |
| Synthetic artwork |Completed312 six-language synthetic views include30 provider scenes; App/manifest match the final package. |
| Preservation |Only restored owner6168 was replaced by39204. All nine0x80080 HWNDs and prior card IDs/XY/compact/raw scopes/accounts/preferences/distributions/original configuration/shortcut/full backup/defaults/startup are preserved; absent size stays omitted, singleton0 and old worker proxies0. |
| Worker/runtime |379/runtime16/Arc4/metadata5/ownedGit30+promisor60 reused from unchanged d9fc85/abd86a, not another ACCOUNT worker run |
| Mac/spec |119 frozen files/active graph and140 features/204 references intact; no native Mac build/UI claim |

App72C9390873D35DBAF59F9301D15D57871263FD898B25B4649E9479C1C5BF6711 and
manifest657C85E6548C75E1F18D9D158738839B0D53F050DA682D597B851CD58CD052BF correlate this package.
Earlier two420-second timeouts/French zero-controls failure and the98.45-second focus-prerequisite
failure remain retained. Partial394/775 progress is historical diagnostic data, superseded only by
the completed exact-package1541 result. Bounded existing owned-window focus preparation changed the
fixture with strict assertions/count intact; it does not classify earlier timeouts or prove a reboot
fix. NativeCheckProgress remains diagnostic, and every new source change requires fresh qualification.

Provider26 uses fake credential/browser bodies without real user account writes. The full Core
Windows suite separately writes/replaces/deletes a UUID-owned synthetic Credential Manager entry
with finally cleanup. Read-only integration does not perform provider/lifecycle/Inbox mutation.
Token creation/stored-empty Verify remained missing at this checkpoint and are qualified in the
subsequent ACC-03 subset above. Live credentials/HTTP/permissions/browser identity remain open,
as do provenance/display/summon/updater/native Mac/x64/phone/shell/signing/clean-machine
and full migration gates. This unsigned development Preview remains `releaseQualified=false`.
See [ADR0042](adr/0042-windows-account-provider-applicability.md).

Historical2026-10-01 checkpoint follows; these older counts/PIDs do not replace the current completeness receipt.

Latest complete-contract/tray checkpoint: Core65/0, native UI437/0, installer8/0 and read-only
seven-local/two-remote integration exit0. The new49 native checks cover branded glyph pixels in
five sizes/two themes, tier priority, transparent DD lettering, hollow-ring/solid-dot distinction,
cached handles, synthetic TaskbarCreated and12 repeated disposal cycles (two retained USER
resources, within the bounded allowance). Synthetic artwork was visually inspected. Actual
Explorer restart/high-contrast/multi-monitor shell delivery remain external gates.

Owned Preview PID258804 now runs fresh package37bf04dc8d764c33b1c4775180bb6428, with nine HWNDs
0x80080. Original config/card IDs/positions/compact flags/preferences/WSL mapping/default settings/
startup preserved; shortcut verified, second-launch exit0 and old worker proxies0. PR4 and Inbox13
with one forbidden account; GitLab remains unconfigured. Frozen Mac119-file/product-graph contract
unchanged. No project lifecycle, real credential/read mutation, banner or actual-deck capture.

The [140-item Mac specification](macos-functional-spec.md) supersedes broad parity claims. Its204
source/resource/document inventory records reviewed scope, not140 passed acceptance scenarios.
Source-present, partial, missing and OS-adapted paths remain explicit; historical rows below are
earlier evidence. Full native Mac/x64/live/API/display/network/signing release gates remain open.

The UI is a self-contained native Windows executable on NTFS. WSL2 runs only its Swift integration
workers. This is an unsigned development build with releaseQualified=false, not a completed migration.

| Check | Evidence | Result |
| --- | --- | --- |
| Original Mac shell/resources/scripts/release and active package graph | scripts/check-macos-contract.py | 119 frozen files and graph unchanged |
| Native Mac suite/build/interactive regression | Mac host unavailable | Required; not executed |
| Shared portable Swift suite | Swift 6.3.3 Jammy ARM64, warnings-as-errors; shared watch/account/sync and bounded log payloads | 286 passed, 0 failed |
| Owned Linux processes | timeout/cancel, TERM-ignoring child, generic PID identity/readiness cleanup | 10 passed, 0 failed |
| Worker lifecycle/progress/EOF | owned fake DDEV CLI fixture | 14 passed, 0 failed |
| Native Windows Core + WSL status/log/preflight | 47 Core, 2 hellos, 12 safe six-language checks, 7 real statuses, 7 log tails, 2 preflights | 77 passed, 0 failed |
| Isolated Windows recovery/diagnostics | two owned fake distro workers; healthy session retained, six-language error guidance, invalid token rejection before vault access | Passed within Core suite; actual WSL/Docker interruption not exercised |
| Terminal starting-directory regression | Core folder/log WT/direct launch fixture; real WT pwd in Ubuntu/Debian projects, Unicode/spaces, literal delimiter fallback and owned log /proc inspection | Core 48/0; live terminal 8/0; no global Terminal settings changed |
| ARM64 Release worker runtime | native Ubuntu-24.04 and Debian glibc 2.36, installed by Windows | Passed |
| Real DDEV lifecycle | separate owned PHP fixture; start/status/HTTP in Windows/logs/restart/stop; isolated XDG globals, no router/agent | Passed; owned stack deleted |
| Native Windows ARM64 WPF app | NTFS launch, seven real cards, desktop-mode API accepted | Exit 0; broader desktop behavior not implied |
| Mac screenshot reference / settings compatibility | independent Windows brand paths, neutral card hierarchy, grouped rows/switches, enabled environment URLs/hidden tools and selected-distro UNC conversion | Core 50 passed, 0 failed; legacy defaults retained |
| Native widget HWND / translated layout regression | tray/modes, six-language forms/search/compact actions with utility menu, metadata/tool/link autosave, language reopening, log singleton/search/follow/visibility/target lifecycle | 154 passed, 0 failed; process exit 0 |
| Running Windows Preview switcher exclusion | read-only native styles before/after; seven widget HWNDs with WS_EX_TOOLWINDOW and no WS_EX_APPWINDOW | Seven excluded; settings and positions preserved |
| Installer | owned install/idempotence/upgrade/startup retarget/rollback/traversal/uninstall fixture | 8 passed, 0 failed; settings preserved |
| Synthetic samples | 54 final screenshot-reference samples: DDEV/Arc/local, running/stopped compact, remote and general/project/account settings in six languages; earlier parity iteration separately qualified 66 views | All generated from fixture data; actual deck never captured |
| QR encoding / LAN target | independent ZXing decoder, short/Unicode/long URLs, physical interface fixtures and loopback rewrite | Passed; actual phone/WSL/firewall reachability remains unqualified |
| Linux/Windows x64 | local ARM64 daemon cannot execute x64; native CI definitions authored | Not executed |
| Publisher signing / verified update install | no publisher identity or qualified artifacts | Open |
| Live remote accounts | API fixtures only, synthetic owned Windows credential | No real account/token tested |

Read-only preflight of Sport1 and ARC-Semana reports portConflict. Another Docker stack owns the
required port; qualification must resolve each project's mapping without stopping that unrelated
service. Existing projects and DDEV global configuration were never mutated by these checks.

Mac source preservation supplements native regression; it cannot replace it. The original Mac release
workflow and updater remain intact. Windows downloads use Windows-DevDeck- to avoid the Mac matcher's
DevDeck-*.zip pattern. Windows Check Now currently opens release notes rather than installing updates.

Shared account/project/review attention, watch/alert policies, tiered tray/list, bounded notification
history and project/account switches are implemented and checked locally. All-account failures keep
previous rows and safe diagnostics; warming processes cannot be started twice. Known worker/host
diagnostics have translated guidance; remaining feature/OS diagnostic details need acceptance alongside
expanded native checks. Release work requires clean-machine install/update,
DDEV HTTPS/DNS/VPN trust, native x64/Mac checks and Windows signing.

Expanded Windows acceptance checks must cover Win+D, Explorer restart, fullscreen/virtual desktops,
mixed DPI/hot-plug, sleep/resume, shortcut conflicts, WSL shutdown/reconnect and Docker/network recovery.
Controlled Docker recovery must also verify episode aggregation and availability across both distro
workers; these checks must not interrupt unrelated running projects on the development host.
The earlier five manual feasibility checks do not qualify all later UI changes.

Exact development package/configuration paths, test logs and machine-specific reports are stored in
.local_docs; use its CODEX.md and TODO.md for current execution state.
Code was committed and pushed only to the work-in-progress `codex/windows-wsl2` branch; no PR,
merge, tag or release was created. Main remains unchanged. Private .local_docs handoff/receipts,
user settings and generated SDK/package artifacts remain excluded. Subsequent fixture/docs changes
are recorded separately; a published source branch is not release qualification. See [migration plan](windows-migration.md) and [Windows host instructions](../Windows/README.md).
