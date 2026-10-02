# 0030 — Shared project detection and separate opening URL on Windows

Plain Windows projects required users to re-enter configuration that the Mac already inferred
from Compose, package manifests, workspaces and Makefiles. The worker also treated the health
endpoint as the opening URL, losing frontend/backend separation and the chosen caption.

Protocol 1 adds the read-only `project.probe` operation and optional suggestion, subtitle and
openURL fields. The worker invokes the existing portable ProjectProbe directly. It reads project
files without shell commands, HTTP calls, Docker probes or runtime writes. An unrecognised folder
returns success with no suggestion; invalid references retain existing validation failures.

Windows offers detection when a new plain project's folder is chosen, and through the explicit
Detect button. A requested suggestion replaces command/stop/mode/Docker fields. It fills caption
and health only when empty, preserving the name, opening URL and stable identity. Results for a
folder/distribution/type that changed during the read are ignored. No startup or polling detection
silently changes existing configurations.

The original LocalProject owns separate health/site semantics. Missing or blank openURL retains
its health fallback. Native template links resolve against the opening URL; the card presents
caption/checkout separately from the start command and retains compact visibility. Framework
glyph selection mirrors the original whole-word vocabulary and precedence; original vendor paths
are reused for Nest/Bun/Docker, with native hammer/box symbols for unbranded kinds.

Project browser Test also follows the original selection order: plain opening address, then
deployed site/tool; Arc's first resolved link; DDEV's visible reported tools, custom tools and
local/deployed site. DDEV requests fresh read-only status to obtain its real URLs. Hidden tools
are respected. Testing the browser requires no project start and never fabricates a local URL.

Reimplementing filesystem detection in C# would duplicate package/workspace/port precedence.
Automatically detecting during every status refresh would overwrite deliberate choices. These
alternatives are rejected in favour of an explicit offer from the existing shared implementation.
Native Mac, x64 and the remaining external migration gates still govern release qualification.
