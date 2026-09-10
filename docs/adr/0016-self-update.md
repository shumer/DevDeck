# 0016 - The app updates itself from GitHub releases, by asking, not by doing

## Status

Accepted.

## Context

Colleagues install DevDeck from a zip on a GitHub release, and every release since 0.8.1 has
carried a paragraph on how to get past Gatekeeper. Each update means the same paragraph again,
and in practice means people stay on whatever they installed first.

The build is ad-hoc signed and there is no Developer ID yet (see the roadmap), so anything an
updater does has to work without a code identity to check against.

## Decision

**Sparkle was not used.** It is the standard for this and it is available as a Swift package,
but it wants its framework and two XPC services embedded in the bundle by hand, since there is
no Xcode here to do it, and it is particular about the host's signature. Everything it adds
beyond that, delta updates, an appcast, an EdDSA key, is nothing this app needs: the release
workflow already produces one zip with a predictable name.

**The updater is the app's own, in two parts.** `UpdateCheck` in Core decides: which release
counts (newer than the running version, not a draft, not a prerelease, with a build attached),
whether what was unpacked is this app at the promised version, and what the relaunch runs.
`Updater` in the app does: the download, `ditto`, the swap and the quit. The decisions are
under tests; the doing is not, and it is kept short for that reason.

**Nothing happens without a click.** The check runs by itself, once after launch and every
six hours; the download and the install wait for a person. A silent replace under a running
`fusion start` leaves a stack half up with nothing on screen to say so, which is why the menu
item is also disabled while any card is mid-command.

**The old copy goes to the Trash, not away**, and only after the new one has been unpacked
and checked. An update that turns out wrong is one drag away from being undone, and a
download that turns out to be something else never touches the running copy.

**One banner per version**, through the same notifications the review requests use, and only
if they are on. The menu carries the state otherwise: available, downloading with a
percentage, installing, failed with the reason in the tooltip.

**Unauthenticated.** The repository is public, and a token would tie the check to whichever
account happens to be first. Sixty requests an hour is plenty for one every six.

## Consequences

- What the app downloads itself carries no quarantine, so after the first install the
  right-click-to-open dance is over for whoever runs this. That is the largest single win and
  it cost nothing.
- Without a code identity there is nothing to verify the archive against beyond HTTPS to
  GitHub and the plist inside it. That is exactly the trust the manual download had, so
  nothing got worse; when a Developer ID arrives, the updater should compare the new bundle's
  signature with its own, and that becomes a real check.
- The open Keychain access list, which is a problem in its own right, is what makes an update
  passwordless: a new ad-hoc build would otherwise cost one prompt per token.
- Under `swift run` there is no bundle and no version, and the updater stays idle. The
  settings page says so rather than offering a check that cannot mean anything.
- A deck built from a commit past the last tag runs a version the tag also names, and is not
  offered itself: "newer", not "different".
