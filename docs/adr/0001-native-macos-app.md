# 0001 - Native macOS app, not cross-platform

Status: accepted, 2026-08-02

## Context

The deck could be a cross-platform shell (Tauri or Electron) with a web UI, or a native
macOS app. The team is entirely on macOS.

Roughly half the work in a tool like this is the integration layer - auth, polling, caching,
models, rate limits - which is portable in either direction. The other half is the shell:
windows, tray, placement, secret storage, packaging. That half is where the choice bites.

## Decision

Native macOS: AppKit windows hosting SwiftUI content, one SwiftPM package.

## Consequences

- Panels can sit *behind* application windows at window level `-1`, which is the widget feel
  the deck exists for. A cross-platform shell gives an always-on-top window instead, which is
  a different thing.
- Frosted glass, the menu-bar item, `SMAppService` login items, the Keychain and
  notifications are all one API call each rather than a plugin apiece.
- If Windows or Linux is ever needed, this is a rewrite, not a port. Accepted: the team is on
  macOS and there is no plan to change that.
- The existing `IRTrafficWidget` in this organisation is built the same way, so the two
  projects share conventions and one mental model.
