# 0014 - A monorepo is a plain project, and its mark names the framework

## Status

Accepted.

## Context

A Turborepo holding a Next front end and a Nest API, run by bun, was added to the deck. The card
that came out was wrong in three ways at once: the start command said `npm run dev` in a repo
whose `devEngines` refuses anything but bun, there was no health URL because the root manifest
depends on no framework, and the Docker box was off although `bun run dev` starts a Postgres
container before it starts anything else. Three fields to fix by hand, and the last of them only
discoverable by pressing a Start that fails.

The mark was the fourth thing. Every JavaScript project on the deck wears the same green Node
hexagon, so a wall of folded cards says "these are all JavaScript" and nothing else.

The question was whether this needs a card type of its own, the way Arc and DDEV have one.

## Decision

**No new card type.** A plain project is a folder, a command, and a URL that proves it worked,
and a monorepo is all three. Nothing about the card would differ: same states, same lifecycle,
same log tray, same phone popover. What was missing was in the probe and in the mark, and both
are two files rather than a module.

**The probe reads through `workspaces`.** The root manifest of a monorepo deliberately says
nothing about frameworks or ports, so stopping there is stopping one directory short of the
answer. Workspace patterns are expanded, each package's manifest is read, and the frameworks are
looked for in one fixed order: front ends first, Nest last. The first match is where the health
URL comes from, because the health URL is the thing you would open, and in a repo with both a
site and an API that is the site. All of the matches go in the caption, so it reads
`bun · next + nest`.

**A port is read, not guessed, wherever it is written down.** The script line first
(`next dev --port 3000` is not a guess at all), then `.env`, and only then the framework's own
default. A wrong port is a card stuck on "starting…" forever, which reads as a broken app.

**Docker is followed one script deep.** A root `dev` that is `bun run db:up && turbo run dev`
needs a daemon, and neither the command on the card nor the root's dependencies say so. Script
references through a package manager are resolved once, and no further: two levels starts finding
the word `docker` in scripts that have nothing to do with starting anything.

**The mark names the framework, not the runtime.** `next` beats `nest` beats `bun` beats `node`,
with Docker still ahead of all of them, because a compose stack is a compose stack whatever runs
inside it. Next, Nest and Bun join the marks as the vendors' own path data, like the rest.

**Matching is on whole words.** The old detection was a substring scan, which is how `npm run
bundle` would have got the Bun mark. The caption and the command are split into words first.

## Consequences

- The caption is now the escape hatch as well as a description: a card whose mark comes out wrong
  is corrected by writing the framework's name into the caption, which is a field the user
  already owns and can already see.
- The caption a fresh project gets is longer than it was: `pnpm · next` rather than `pnpm`. It is
  the line that says what the repo is, and it was carrying only how it is installed.
- Turborepo has a mark and did not get one. Its red is within a few degrees of Nest's, and two
  near-identical red discs on one deck is worse than one of them being a Next disc. "Monorepo" is
  also not what you need to know at a glance; "Next" is.
- The probe now touches more of the disk when a project is added: every workspace manifest, and
  up to two `.env` files. It is capped at forty packages, and it still runs once, behind a file
  dialog somebody just closed.
