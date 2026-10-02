# 0026 — Source contract before parity claims; preserve tray identity

## Status

Accepted for the authorized Windows migration, 2026-10-01. Native release qualification remains open.

## Context

Successive checks restored individual card controls but missed shipping Mac defaults and complete
flows. Presentation fixtures supplied fields the production worker did not export: Arc links and
xhgui are examples. The Windows tray also used generic Application/Warning system icons, discarding
the app's identity exactly when it asked for attention.

## Decision

Use `docs/macos-functional-spec.md` as the migration acceptance inventory. Each stable feature ID
describes defining Mac source, defaults/persistence, Windows coverage and a concrete complete-flow
scenario. Present code, synthetic qualification, live qualification and OS adaptation are separate.
The companion source/resource/control hash inventory detects changes that need review; it does not
prove the specification is semantically complete. Record source/doc discrepancies instead of
changing frozen Mac source to match Windows or an old README example.

Port DeckIcon's two-card geometry and transparent DD initials into Windows-only artwork. Render
16/20/24/32/48px frames using the system taskbar ink. Waiting uses the one red dot, needs fixing an
ink dot, stuck an ink ring; informational-only signals remain calm. The worker's existing attention
tiers choose the state, preserving the common policy. Cache owned Icon instances, replace them on
theme/DPI changes and dispose after native registration replacement/deletion. Shell recreation
re-registers current identity/state and tolerates repeated TaskbarCreated messages.

## Rejected

Keeping generic system icons loses identity and collapses three distinct attention tiers. Showing a
number instead of the glyph does not identify the app. Copying Mac raster screenshots would bake in
the wrong theme/scaling. Declaring parity from supplied fixture fields misses the worker boundary.
Changing Mac source or defaults during this correction would violate the migration preservation rule.

## Consequences

The 140-item specification exposes more remaining work honestly, including complete Arc/generic
forms, browser discovery/fallback, xhgui export, tray navigation, display parking/summon behavior and
verified updates. Future batches select and close explicit IDs with evidence. Windows remains an
unsigned development preview until native Mac/x64/live shell/API/network/signing gates pass.
