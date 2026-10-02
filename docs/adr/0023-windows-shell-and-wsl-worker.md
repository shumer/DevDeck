# 0023 — A separate Windows shell sharing Swift integrations through WSL

Status: accepted for implementation, 2026-10-01. Release qualification pending.

## Context

The user requested Windows support through WSL2 and Docker Desktop and authorized immediate
implementation after a full migration plan. The desktop prototype passed five manual checks;
Ubuntu DDEV and Debian Fusion projects are accessible, sharing one Docker daemon. Native macOS
behaviour remains a required product constraint.

## Decision

Keep the AppKit/SwiftUI application and its existing macOS package graph, storage and release
assets. Add a separate WPF shell on .NET 10 and one Swift worker per selected WSL distribution.
The worker reuses the headless Swift modules through bounded, versioned JSON lines on stdin/stdout.
Windows owns desktop integration and credentials; WSL owns Linux paths and project execution.
Every project carries its distribution and stable card ID. The first worker exposes read operations
only; lifecycle operations follow cancellation and disposable-stack qualification.

This supersedes ADR 0001's exclusion of Windows, retaining its choice of native macOS UI.
Linux is a worker platform; a standalone Linux desktop application is outside this plan.

## Alternatives

- Replacing both shells with Electron/Tauri would put verified Mac desktop behaviour and
  settings at risk and require a larger rewrite.
- Reimplementing integrations in C# or Python would duplicate state, health and API rules.
  Python remains useful for diagnostic/live-test orchestration, not production integration logic.
- Running Linux commands from Windows paths loses distribution identity and misresolves symlinks,
  user shell profiles and tooling. All project operations execute inside the selected distribution.

## Consequences

Two native shells need independent UI, packaging and regression coverage. Shared code changes
require Mac and Linux gates. A file baseline is an additional safeguard, not proof of runtime
compatibility. Worker deployment must package and qualify its Swift/Linux runtime for supported
distributions; a Docker-built binary alone is not an installer. Shared Docker port/name conflicts
must be checked before actions and must not be solved by stopping unrelated stacks.

See [the migration plan](../windows-migration.md) and [worker protocol](../worker-protocol.md).
