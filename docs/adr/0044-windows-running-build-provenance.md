# 0044 — Windows startup facts for the running application copy

Status: Accepted; scoped development subset qualified and activated.
Date: 2026-10-02.

General displayed the loaded informational version, but did not identify its App module or process
executable. A newer package on disk can differ from the code still running. Show cached startup
facts so those copies can be distinguished without attributing disk metadata to the current
process or changing configuration, update selection or retained forms.

## Decision

Add App-only immutable [RunningBuildInfo](../../Windows/DevDeck.Windows.App/RunningBuildInfo.cs).
Main initializes it once after the fake-worker early return and before creating Application.
Capture typeof(SettingsWindow).Assembly's informational version, assembly version, nonempty
ManifestModule.ModuleVersionId, its module location and Environment.ProcessPath. Startup begins
Unknown; repeated initialization cannot replace or recapture the record. Each settings window
captures its injected provider once or uses cached Startup. Search/list/runtime reconciliation,
page revisit, re-show and localized formatting never poll newer metadata.

General shows read-only wrapping, selectable version/build-ID/process-executable/module fields
with full accessible values, bounded height and ordinary scrolling. Informational version keeps
its exact accepted suffix and existing DevDeck note. Missing informational version may display an
explicitly labelled assembly version; it is never a marketing/build counter or updater input.
Missing facts are independently localized as unavailable. Empty module locations remain missing
data, without disk searches or executable guesses.

MVID is a D-format GUID identifying the loaded App module only. It is not a monotonic build number,
timestamp, signature, authenticated source revision, whole-package/Core/worker identity or release
qualification. Identical module builds may retain it. Hosted execution can report dotnet.exe as
the process executable and a different App DLL as the module; display both exact startup paths.
Renaming/deleting files or replacing a package later does not relabel the startup record.

Reject each malformed/unavailable field independently:2048 UTF16 units for either version,
32768 for either path, no controls or unpaired surrogates; empty/whitespace-only values and
Guid.Empty become unknown. Valid values remain exact without truncation, path canonicalization
or character replacement. Expected reflection/native metadata failures, including access denied,
yield that field's unknown value without retry; unexpected failures are not swallowed. Paths are
plain text, not commands, links or file-opening actions.

Capture performs no sidecar/manifest/VERSION/git/directory/hash/file-existence read. No settings
schema/default, package-trust classifier, token/configuration content or worker request is added.
The new block performs no metadata save, worker acquisition/discovery, credential read, card
rebuild or attention/Seen/queue/check-time reset. Existing settings-window behavior outside the
block remains separate, including cached credential availability at opening.

CheckNow receives only the admitted original informational version with its exact characters and
existing OS runtime. Missing/rejected informational version disables the check and shows an
unavailable note, even if an assembly version is displayed. Arrival performs no automatic network
check. Default live:false stays inert; an explicit owned checker seam exercises the real button
and result body without HTTP/browser launch. Fake calls do not qualify updater installation,
signatures, available-release behavior or live network delivery.

An adjacent label correction uses API endpoint for the captured GitHub Enterprise address instead
of the prior GitLab-oriented generic label. Token dialog context/default Cancel/action/lifetime
semantics stay unchanged; all30 prior token groups remain in the full native qualification.

## Qualification and activation

Two actual old-General baselines failed without timeout after positive version/controls/HWND/
state/pending-read/held-action-gate premises: missing build ID exit1/1.56s and missing executable
location exit1/1.20s. The original cf12611 candidate is retained.

Final corrected477-file source snapshot is
`BEA592AABA7CA659C26FAA00A32F0A43C65B3EBF64990E04664ECEB515AF0112`; package
`9e1090ab67b94081853edfd12e72554e`, App
`EDE7F9BC9CE5033EAF082653C73DDA065865D9C0194D90DCD96DCD93FCC8338B` and manifest
`AB4C276059AEC6532C86F727F27FCF2785DFC74DD02A07F2334691FD4AFF3135` correlate the packaged gates:

- Same-source Tests SDK exit0/19.59s and publisher exit0/19.70s, zero warnings/errors.
- Separate actual Core apphost focused4 exit0/0.30s and full226 exit0/58.30s.
- Provenance component16/0 exit0/11.30s; fullnative1587/0 exit0/208.14s.
- Installer8/0 exit0/24.08s with identical manifest, no wrapper restoration and identical fixture.
- Read-only7local+2remote exit0/11.88s; checkoutCommandsInvoked, inboxReadMutationInvoked and
  powerOffLifecycleInvoked all false.
- Fresh synthetic372 exit0/390.85s, including provenance30/token30/provider30 across six languages,
  unchanged final App/manifest. Eight English/Russian frames were visually inspected, not all372.

The16 groups retain build/location2, default/minimum13/18DIP six-language layout6 and functional8:
version/path bounds, once-only startup, independent fallback, same-version/different-MVID and hosted
paths, provider/file-removal lifetime, actual fake updater dispatch and metadata/draft/focus/state
preservation. Injected access-denied readers are not induced OS permission failures. A newer owned
malformed sidecar and deleted fake module/executable cannot replace the cached injected record;
production has no sidecar reader. Tests use isolated stores and fake availability/credential/
browser/worker bodies. The full Core suite separately writes/replaces/deletes a UUID-owned
synthetic Credential Manager entry with finally cleanup.

The preceding381e03 candidate's successful proofs remain separate. A sample-only startup-fact
omission was caught before any renderer/artwork output. Corrected actual generic/geometry/empty-
sidebar sample factories now export exact fake facts and prove lifetime/state preservation within
the unchanged16 groups. Production startup behavior was unchanged; no actual-path screenshot or
OS fault is inferred. Five provenance sample variants (native/hosted/unknown/long/assembly) across
six languages use synthetic facts only.

The scoped updater exited0/23.93s, replacing only68312 with74628. Its stdout collector subsequently
waited for EOF because the live Preview inherited a redirected pipe;23.93s excludes that collector
stall. The original exit/log are retained. After exact owner/configuration/hash checks, only74628
was stopped and the same artifact/configuration launched without redirected helper handles.
Recovery exited0/1.55s as78356; native verification exit0/21.56s confirms active78356, all nine
0x80080 HWNDs and prior IDs/XY/compact/raw scopes/accounts/preferences/distributions/original
configuration/shortcut/full backup/defaults/startup preserved, absent geometry omitted and
singleton0/old worker proxies0. No product/source/package change addressed this collector defect.

Exact d9fc85 archive/abd86a binary worker379/runtime16/Arc4/metadata5/ownedGit30+promisor60/null-wire6
are reused, not rerun for SET-08. Mac119 frozen files/active graph and spec140/204 source guards
remain distinct from native Mac acceptance. Full receipt provenance and earlier checkpoints are
in [Windows qualification](../windows-qualification.md).

## Boundaries

This adapts Mac bundle/build/location facts to a Windows loaded module and process. It does not
reproduce Mac marketing/build counters, translocation or Applications updater promises, nor
classify Development/installed/signed releases by path substrings. Displayed startup paths need
not still exist and may contain local user names; owned artwork uses fake paths and no account/
configuration contents. At most five lazy channels per distribution remain; SET-08 adds none.

Native Mac/x64/live provider/browser/phone/display/DPI/homes/summon/input/accessibility/shell/
signing/clean-machine/full migration gates remain open. No frozen Mac UI/resource, worker
operation/schema, release or merge qualification is introduced; releaseQualified=false.
