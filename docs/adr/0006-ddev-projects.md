# 0006 - DDEV cards ask DDEV, and share one call

Status: accepted, 2026-08-02

## Context

DDEV projects want the same card as Arc ones: links, whether it is up, the branch, and start
and stop. The difference is that DDEV describes itself. `ddev list -j` returns every project
on the machine with its state, root, type and URLs, and `.ddev/config.yaml` sits in the
checkout with the PHP and database versions.

The obvious shape - a service per project, mirroring `LocalStackService` - would spend one
process per card per poll to learn things one command already answered for all of them.

## Decision

1. **One `DDEVEnvironment`, not a service per project.** A single `ddev list -j` per refresh
   feeds every card, so a deck of six costs what a deck of one costs.
2. **Versions come from the file, not from `ddev describe`.** `list` does not carry them and
   `describe` is a process per project; `.ddev/config.yaml` is a read. Just enough YAML is
   parsed for four keys rather than taking on a parser dependency - indentation is what tells
   the project's `type` from the database's.
3. **The framework version is read from `composer.lock`, not from DDEV's `type:`.** That
   setting configures DDEV and nobody revisits it after a major upgrade: both projects on this
   machine said `drupal9` while running Drupal 11.4.4 and 10.6.11. The lock file is what the
   code is installed from, so it cannot be stale in the same way. It is megabytes of JSON and
   the card polls every ten seconds, so the answer is cached until the file's modification
   date changes.
4. **`paused` is a state of its own**, alongside running and stopped. DDEV pauses containers
   without removing them, and flattening that into "stopped" would misdescribe what Start does.
5. **Adding a project offers the list DDEV already has**, rather than asking for a folder.
6. **Cards are composed from shared pieces** - `CardChip`, `CardActionButton`, `CardSeparator`,
   `CardStateRow`, `CardBranchRow` in `DevDeckUI` - which the Arc card was moved onto in the
   same change. Two cards of the same shape maintained separately drift, and this project has
   already watched that happen to its link templates.

## Consequences

- A project ddev cannot see reports `unknown to ddev` rather than pretending to be stopped,
  and "ddev did not answer at all" is a distinct case from "ddev has no such project".
- Projects are matched by name first and by folder second, so renaming a project in
  `.ddev/config.yaml` does not orphan its card.
- Mutagen status is surfaced only when it is not `ok`: a stalled sync means edits never reach
  the container, and nothing else on the deck would explain it.
- The DDEV settings row is much shorter than the Arc one, because there is far less to ask.
- Nothing destructive is offered - no `ddev delete`, no snapshot restore. Start, stop, restart
  and a global power off are the whole surface.
