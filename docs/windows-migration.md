# Windows migration plan

Date: 2026-10-01. Authorized: develop the full plan and begin implementation without waiting
for further approval. This authorization supersedes the earlier prototype-only scope.

## Outcome and architecture

Keep the native macOS application, its AppKit/SwiftUI surfaces, stored identifiers, preferences,
Keychain policy and release format. Add a separate Windows 11 application using WPF on .NET 10
LTS and a reusable Swift worker per selected WSL2 distribution. The worker shares Core and
integration services with macOS. Ubuntu DDEV and Debian Fusion must coexist. The Python probes
remain diagnostic tools and are not the production integration implementation.

Windows owns desktop windows, tray/summon, browser profiles, Explorer/Terminal, notifications,
startup, Windows secure token storage and installer/update UX. WSL owns Linux files, commands,
project processes, logs and local health probes. A versioned JSON-lines protocol over child
stdin/stdout supplies typed operations and correlated events. No listening API port is required.
Project identity is stable card ID + distribution + canonical Linux path. Tokens never appear in
arguments, logs, persisted JSON or repository files; macOS keeps Keychain, Windows uses its OS
credential store, workers hold only explicitly supplied credentials in memory.

## macOS protection rules

1. Capture the current Git revision and file hashes for App/UI, macOS tests, build/test scripts,
   release workflow and localization resources before changing shared code.
2. Do not rewrite the macOS shell or move its settings/polling controller in the first stages.
   Add worker orchestration alongside it; extract shared decisions only with characterization tests.
3. Keep the active macOS SwiftPM products, target dependencies and language modes unchanged.
   Add Linux branches to the manifest; KeychainACL remains the same macOS-only implementation.
4. Preserve macOS runtime defaults (/bin/zsh, Keychain-first stores, en* LAN interfaces, existing
   preferences/card/account IDs), using compile-time platform branches for Linux behaviour.
5. Keep the existing macOS tests and release workflow intact. Add independent portability CI,
   including a native macOS build/suite. A Linux pass never substitutes for a macOS pass.
6. Use separate build caches and Windows settings/storage. No automatic import/overwrite of
   com.shumer.devdeck defaults; no token migrations that weaken protection.
7. For each shared change: run portable tests and contract checks locally, then require a green
   native macOS suite/build and interactive regression before calling the migration release-ready.
   macOS execution is not available on this Windows host; record that limitation explicitly.
8. Preserve rollback: small additive stages, independent Windows artifacts, no changes to the
   existing macOS release assets/update selection until independently verified.

## Stages and acceptance criteria

### M0 — Plan, baseline and CI safeguards (1–2 person-days)

- Record user authorization, architecture and full acceptance matrix; supersede ADR 0001's
  exclusion of Windows while preserving its native macOS choice.
- Capture baseline hashes/revision and add a script detecting unintended Mac shell/resource/script changes.
- Add portability CI: Linux Swift build/offline suite, native macOS suite/build, Windows shell
  build/tests on .NET 10. Keep release workflow unchanged.
- Exit: plan and tasks persisted, baseline reproducible, safeguards runnable.

### M1 — Portable shared libraries (3–6 person-days)

- Conditional SwiftPM graph: portable libraries/tests and worker on Linux; existing macOS graph.
- Isolate Security/KeychainACL, Darwin and OSLog; add FoundationNetworking where required.
- Linux shell/PATH selection, process liveness and detached-start command adaptation. Keep Mac defaults.
- Do not advertise WSL VM IPs as phone-reachable LAN addresses. Keep LAN QR capability gated.
- Reuse existing offline integration/policy tests in a separate UI-free runner; keep UI/SVG tests on Mac.
- Exit: all shared modules build with warnings treated as errors; portable suite green; no changes
  to App/UI/resources or active macOS test expectations; native macOS gate still required.

### M2 — Swift worker and protocol (4–7 person-days)

- Protocol hello/version/capabilities, request IDs, bounded payloads, typed errors and cancellation.
- Expose project configuration/status, Docker/DDEV environment, logs, health, start/stop/restart.
- Reuse DDEVKit/ArcKit/ProjectKit; avoid a Python copy of production integration logic.
- Resolve shell PATH per worker; accept Linux project paths only. Own operations by card/project.
- Serialize operations per project; guard polls during actions; stream progress and verify outcomes.
- EOF/error handling, reconnect, stdout reserved for protocol, stderr for redacted diagnostics.
- Exit: protocol tests and disposable live worker tests pass, missing tools/distribution actionable.

### M3 — Windows host and multi-distribution execution (4–7 person-days)

- Separate Windows/ solution and build script; local .NET 10 SDK setup if necessary.
- Discover WSL distributions; configure distribution + Linux path per project; one worker per distro.
- Safe argv launch, request/event correlation, timeouts, disconnect recovery and protocol negotiation.
- Keep project config schema versioned with additive migrations and atomic saves; preserve card IDs.
- Docker may be shared across distros: coordinate actions and preflight host-port/global-name conflicts.
- Exit: Ubuntu DDEV and Debian Fusion status visible together; failures isolated by worker/project.

### M4 — Windows local-project deck (6–10 person-days)

- Cards for DDEV, Arc and generic projects, correct state/health/branch/version/links, logs window.
- Desktop/floating modes, drag/lock/expand, tray and summon fallback, saved layouts.
- Settings with distribution picker, Docker launch/probe, folder reveal, Windows Terminal and browser profiles.
- Validate actual projects without automatically stopping unrelated stacks or rewriting their configs.
- Exit: selected test project start/stop/restart and health/logs work; shared Docker conflicts show
  actionable messages; DDEV HTTPS trust checked separately from daemon readiness.

### M5 — Remote integrations and feature parity (8–14 person-days)

- Windows OS credential store, verification before saving, in-memory worker credential injection.
- GitHub PR/inbox/actions, GitLab instances, multi-account partial failures and profile-aware links.
- Shared cache/retry/attention rules; notifications and tray counters; mark-as-read operation guards.
- Six-language resources with measured layouts, stable keys and matching terminology.
- Exit: offline API fixtures and protocol tests pass; sample UI validated; live API checks use
  explicitly configured accounts and never log tokens.

### M6 — Distribution and updates (4–7 person-days)

- Build/package Windows ARM64 and x64 separately; package Linux worker ABI/runtime dependencies
  for supported Ubuntu/Debian versions. Prefer self-contained/static worker deployment where proven.
- Installer, startup, code signing, worker version compatibility, recoverable user-approved updates.
- Preserve current macOS release workflow and asset names; separate Windows channel/assets.
- Exit: clean-machine install/uninstall/upgrade/rollback works, no toolchain needed for end users,
  no Mac update check selects a Windows asset.

### M7 — Regression and release qualification (5–9 person-days)

- Native Mac: full offline suite, warning-free build, bundle smoke; panels/menu/settings/Keychain,
  profiles, startup, logs, updates, arrangements, multi-monitor and localization checks.
- Windows ARM64 + x64: inactive click, Win+D, tray/summon, virtual desktops, fullscreen, DPI/hot-plug,
  sleep/resume, Explorer restart, WSL shutdown/reconnect, Docker absence/restart, cancellation.
- Projects: start/stop/restart outcomes, orphaned process prevention, stale/partial state,
  DNS/HTTPS/VPN/networking, Fusion port ownership and DDEV router errors.
- Exit: all required gates passed; known limitations documented; migration not called complete
  while macOS validation or required Windows capabilities remain open.

## Order and tracking

Implement M0 → M1 → M2 → M3. Then local deck M4, remote parity M5, packaging M6 and qualification
M7. Advance without asking for routine approvals; log each completed step in .local_docs. Do not
stop unrelated projects or perform destructive configuration/credential migration to unblock a test.
If native Mac validation is unavailable, continue independent Windows/worker work while keeping
that gate open; never claim macOS compatibility from conditional compilation alone.

Estimated total: 35–62 person-days plus 20–30% reserve for worker packaging, desktop integration
and real project compatibility (about 9–16 working weeks for one full-time developer with reserve).
This supersedes the narrower prototype estimate because multi-distribution support and release
qualification are explicit. Estimates are planning ranges, not validated throughput.

## Current known project constraints

Ubuntu-24.04: five DDEV projects were discovered initially. Their Docker state can change while
other work runs; refresh status before acting. Qualification never starts/stops these projects.
Debian: Sport1 and ARC-Semana CLI help works; saved Compose configs/images available as arm64.
Both publish MongoDB 27017 already owned by dorothy-mongodb; do not stop that unrelated service.
Sport1 .env PORT=3000 differs from saved Compose port 80; determine actual generated port at startup.
Debian uses glibc 2.36. The ARM64 Release worker is now built with Swift 6.3.3 Jammy and its Swift
runtime libraries packaged separately; native Windows execution in Ubuntu and Debian passed.
An owned real DDEV fixture passed the Windows start/status/HTTP/log/restart/stop path and was deleted.
Native Linux/Windows x64 and clean-machine qualification remain separate gates.

## Sources for runtime choices

- Swift 6.3.3 Ubuntu 24.04 x86_64/aarch64 toolchains and official container tag:
  https://www.swift.org/install/linux/ubuntu/24_04/
- .NET 10 LTS support policy: https://dotnet.microsoft.com/en-us/platform/support/policy

## Release status

M0/M1 safeguards and M2/M3 foundations are implemented and locally tested. M4/M5 include local and
remote cards, secure credentials, arrangements, browser profiles and initial attention/localization.
M6 includes a per-user development installer/rollback/uninstaller and separate package CI.
Windows assets use `Windows-DevDeck-` to avoid the existing Mac updater's `DevDeck-*.zip` matcher.
Implementation remains in progress. macOS has not been executed on this host. No full Windows release
or complete migration is claimed; detailed checked tasks and evidence are kept separately.
