# 0037. Interactive terminal choice and Arc launch readiness

Status: accepted for implementation.

Opening a project terminal uses Windows Terminal's default profile today. PowerShell can select
an npm .ps1 shim that its execution policy refuses, while the same project's background runner
uses cmd.exe. Choosing a different interactive profile must not change the project's execution
location or background command semantics.

The Windows host discovers installed terminal applications and profile GUIDs. The runtime owns
the translated settings group, row order, profile visibility, saved selection and default.
The shell renders the group and launches the terminal carried by the effect. WSL folders keep
their distribution and Linux path. No PowerShell execution policy is changed. Terminal state
is stored separately from the common preferences wire model so older settings forms continue
to save that model without losing the new choice.

Arc readiness belongs to the runtime and ArcKit. The Windows host enables the check; the Mac
keeps its previous behavior. A missing folder or recognized command prerequisite disables
Start and Restart in the model. An actual Start or Restart repeats the check and asks Docker
through that project's runner before executing any lifecycle command. A healthy stack keeps
Stop. Local and global CLI probes only resolve package and binary files, never download them.

Custom commands cannot be rewritten as Fusion commands or executed as part of checking them.
Known Node starts validate Node and the script. Other custom shell code keeps its existing
behavior with a note that it is checked at run time. Fully validating arbitrary shell syntax
would require executing it or rejecting working commands, so neither is done.

The existing default terminal was retained instead of silently forcing Command Prompt.
Moving background launches to the selected interactive shell was rejected because it would
change quoting, process lifetime and WSL ownership. Putting readiness in C# was rejected because
it would let a shell decide whether an action exists and leave other callers unprotected.
