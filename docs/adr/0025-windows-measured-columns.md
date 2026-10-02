# 25. Windows columns use measured windows and compact controls stay visible

Date: 2026-10-01. Windows development preview; Mac UI, resources and product graph unchanged.

Windows tidy placed every configuration entry in fixed 285-DIP rows, including hidden cards. Small
and collapsed windows consequently had large holes below them; tall windows could overlap or leave
the work area. Saving also rebuilt every widget, discarding the snapshot whose height was measured.
Compact presentation existed behind a title double-click and was difficult to discover.

Use a pure Windows Core layout equivalent of Mac DeckLayout.tidy with actual visible-card dimensions,
the existing deck anchor/order, the anchor monitor's work area and Mac's 12-DIP gap. Stack down and
wrap to the next column when the next card would pass the bottom. Grow toward available horizontal
space; clamp crowded/oversized headers to reachable positions. Hidden/inactive records do not move.
Apply/persist positions on existing windows so snapshots, lists, operations and pollers survive.
Measure physical native window rectangles, convert through DPI, then snap placements to device
pixels before saving. WPF SizeToContent can report a fractional height while the native frame and
position are pixel-rounded; treating the fractional height as an occupied rectangle produces drift.
Settle pending rendering/native resizing before reading bounds. Native fixtures verify independent
physical rectangles with a maximum one-pixel rounding tolerance; Core checks exact 12-DIP arithmetic.

Use visible, accessible collapse/expand chevrons and card context-menu actions, plus contextual
project/remote-card settings. Preserve the existing persisted collapsed flag and compact primary
controls; Inbox mutation prevents hiding Cancel by collapsing the card. Automatic packing stays off,
matching the Mac default. Updating the application does not rearrange or collapse the user's deck.

A smaller fixed row step was rejected because card heights differ by state, language and compactness.
Rebuilding after tidy was rejected because it destroys loaded state and changes presentation height.
Automatic movement after every refresh was rejected because it erases user-placed gaps without opt-in.

Qualify arithmetic with mixed-height/wrapping/edge fixtures and native in-place layout, persistence,
compact interaction and six-language UI checks. External monitor/DPI/shell and native Mac release
qualification remain separate gates; synthetic fixtures do not certify those environments.
