# 0029 — Arc options and typed project links on Windows

The Windows worker previously created Arc projects with an empty organization and fixed commands.
Its host stored only literal link URLs, so hosted tools, custom templates, link kinds and the local
PageBuilder editor disappeared between Mac and Windows.

Protocol 1 gains optional `arc` options and `localEditorURL`. The worker constructs the existing
`ArcProject` with organization, site, local origin, health path and configured start/stop commands.
Absent options retain the Windows no-install Fusion commands and the actual Mac `/release` health
default. Explicit custom commands still pass Docker Compose port-ownership checks; Node/npx and
project-local CLI checks belong to the default launcher. No additional rebuild/teardown buttons ship.

Windows persists template text, enabled state and tool/site kind in its existing link records.
One host resolver applies Arc `{org}`/`{site}` or DDEV `{site}` substitution, validates HTTP links
and gates local destinations on runtime state. Hosted destinations remain usable while stopped or
working. Defaults mirror the frozen Mac model; exact superseded Arc templates are corrected, while
custom edits and disabled addresses survive. Builtin labels stay fixed; custom rows can be added,
renamed, removed or assigned a kind.

An Arc card may have an empty checkout path. It presents hosted links without any worker, Docker
or network status request, disables local controls and can later gain a folder under the same ID.
Workers also accept this status shape and reject folderless lifecycle/log/preflight requests before
commands run. Existing local projects and stored preferences acquire no implicit organization,
template, placement or visibility edits during startup.

Keeping fixed raw URL text would continue losing disabled and typed metadata. Duplicating the Arc
stack service in Windows would diverge from port, origin and health behavior. Hosted-only cards do
not need a WSL process just to resolve links from their own settings. The small native template
resolver therefore owns presentation, while the original Swift model owns local stack execution.

Offline production, native six-language and read-only runtime checks qualify this subset. Native
Mac, Windows x64, browser/network and real Fusion lifecycle gates still govern release qualification.
