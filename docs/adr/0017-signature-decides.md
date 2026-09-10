# 0017 - The signature decides how tokens are kept, and releases are signed in CI

## Status

Accepted. Waiting on the Developer ID certificate for the second half to take effect.

## Context

The app is ad-hoc signed, so every build is a different application to macOS. The Keychain
binds an item to the application that wrote it, which meant one password prompt per token per
update; the fix in 0.7 was to write the items with an access list naming no application at
all. That ended the prompts and opened the tokens to any process running as the user. The
README said so, and then the build started going to colleagues, who have the same hole.

The updater added in 0.11 has the same gap from the other side: without an identity there is
nothing to verify a downloaded build against beyond HTTPS to GitHub and the plist inside it.

Both are the same missing thing, a code identity that survives a rebuild, and an Apple
Developer Program membership has been bought for it. The certificate is not here yet.

## Decision

**The code decides by the signature it finds itself under**, rather than by a build flag.
`CodeIdentity.current()` asks the running process: unsigned, ad-hoc, or signed with an
identity, a Developer ID's team or a hand-made certificate's subject. Everything follows from
that answer:

- `KeychainTokenStore` writes the open access list only for a build that has no identity.
  Signed, it lets the Keychain do what it does by default, bind the item to this application.
- The first launch after the signature changes rewrites every stored token once, one prompt
  each, and the mode is remembered. A move from ad-hoc to signed, or between two
  identities, is noticed the same way; nothing has to be told.
- The updater refuses a download whose identity is not its own, once it has one. Ad-hoc, it
  accepts what the plist says, which is the trust a download by hand had.

**Releases are signed and notarised on the runner**, never on the machine the code is written
on. The workflow imports the certificate into a keychain of its own, signs through the same
`build.sh` everyone uses, with hardened runtime, submits to Apple, staples the ticket and only
then packages. Every step is behind the secrets: a repository without them builds exactly the
release it built before, ad-hoc, with the longer install notes. `notarytool` lives in Xcode,
which the runner has and the development machine does not, and that is the right way round.

**`build.sh` signs with whatever `CODESIGN_IDENTITY` names**, or ad-hoc when it names nothing.
The same script serves a Developer ID on the runner and a certificate made by hand in Keychain
Access here, which is how a developer's own tokens get bound to the app without waiting for
Apple.

## Consequences

- Once the certificate is in the repository's secrets, the next release opens without the
  right-click dance, binds tokens to the app on every machine, and the updater's check becomes a
  real one. The release notes say which of the two builds they describe.
- Five secrets: the certificate as base64 `.p12`, its password, and the App Store Connect API
  key's id, issuer id and `.p8` as base64. No team id is typed anywhere; the identity is found
  in the imported certificate.
- The one-time rewrite prompts once per token, on the first launch of the first signed build.
  That is the last round of prompts, the same promise 0.7 made and this time kept for the
  right reason.
- Hardened runtime is on for any signed build. Nothing in the app needs an exception: it
  loads no unsigned code and asks no entitlement.
- A hand-made certificate binds tokens on one machine and does nothing for Gatekeeper; that is
  the Developer ID's job, and both go through the same code.
