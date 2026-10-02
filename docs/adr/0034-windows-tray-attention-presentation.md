# 0034 — Windows tray attention presentation

Date: 2026-10-02
Status: Accepted; qualified and active in the Windows development Preview

Windows displayed up to five attention items per tier with subtitles only in tooltips. This lost
the Mac digest's overflow navigation, visible account/context and age, and its explicit calm state
with a check time. Five waiting items should show three direct rows and a same-tier submenu of two;
the previous menu rendered all five directly.

Keep worker-provided signal identity, priority and actions authoritative. The native merge retains
shared tier/time priority and uses culture-aware numeric title comparison for equivalent signals. A pure
AttentionDigest presentation projects waiting/needs-fixing/stuck into three rows and good-to-know
into two. A single leftover stays directly visible, matching the Mac rule that hiding one item
costs the same menu line. Larger sections use localized overflow submenus containing the same
native rows and original targets. The existing all-attention window remains available.

TrayAttentionRow remains a normal keyboard-operable ToolStripMenuItem. It draws a title, visible
subtitle/account context and an age badge. Subtitle trimming counts text elements, preserving
combining marks and joined emoji; the full subtitle stays in its tooltip and accessible description.
Accessible names contain plain title/context/age; ampersands in visual menu text do not become
mnemonics. Brand marks reuse the existing artwork, other marks use scoped vectors, and menu rebuild
disposes the rows' owned bitmaps. Both Enabled and a non-none action are required for activation.
Main and overflow menus explicitly use bounded custom-row preferred widths; rows fill that client
and painting clamps to it. Native menu columns measure Text separately, so Text uses the visible
Unicode title prefix that fits the painter, retaining the full accessible title and action identity.
This prevents title-only columns from pushing the menu beyond the screen at enlarged fonts.

An empty digest shows the calm row and local HH:mm. The Mac controller derives lastCheckedAt from
its current integration observations. The existing Windows attention protocol does not carry that
aggregate time, so Windows records its receipt of the latest validated worker attention observation.
This is an explicit host-clock adaptation, not a producer checkedAt claim. Event Since/UpdatedAt
and ephemeral settings project.check results never supply the calm clock. Before any observation,
use current time, as the Mac does. Existing runtime/language-reset rules still clear the host clock.

The standalone synthetic browser window gains a Grid root to constrain its margin correctly after
the prior 320-DIP height fix. Fresh bitmap acceptance confirms its profile and right controls fit;
this changes the fixture only.

The production native regression is retained in windows-tray-red-ui.json: the old Take5 menu fails
the five-waiting three-direct/two-overflow expectation. Actual menu layout QA found a 198-pixel client
against a 330-pixel preferred custom row, clipping ages and right subtitles; the package-level red
is retained in windows-tray-layout-red.ps1/json. Final Core112/0, native1103/0, installer8/0 and
warning-free ARM64 qualification pass, including native menu/client/font/Unicode geometry guards.
Fresh read-only seven-local/two-remote/tray10s checks verify three independent transports and
original Arc summaries. Worker317/runtime16/Arc4/metadata5 are explicitly reused with the unchanged
byte-identical b526 archive, not rerun. Mac119/product graph and spec140/204/whitespace pass.
Twenty-four synthetic views qualify Russian main/calm, German overflow/browser and six-language
presentation: inline ages/subtitles and browser profile/right controls are visible without cropping.

Only owned Preview380656 was replaced by408076/package206e7033c2854ea584be774b0e62900f, keeping
the original configuration/shortcut and full backup. windows-tray-preview-checks.json proves all
nine0x80080 windows, existing IDs/settings/positions/compact/scopes/preferences/distributions/
defaults/startup preserved, singleton exit0 and old worker proxies0. No real attention action,
browser/account/token/project lifecycle or network policy was invoked for qualification.

Original Mac and worker sources remain unchanged. Deck global actions, modifier read/dismiss twins
and card-context menus are separate TRAY-06/07 and UI-08 requirements. Native Mac, Windows/Linux
x64, live accounts/browser/phone/display/signing and complete migration gates remain open.
