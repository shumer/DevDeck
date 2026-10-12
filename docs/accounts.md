# Accounts and tokens

How tokens get in, how several accounts share one deck, which identity a link opens as, and how
the Keychain protects what it holds.

## First run

```bash
scripts/smoke-test.sh        # optional: real GitHub, GitLab and Azure DevOps calls, prints counts, never a token
```

Tokens are typed into Settings, one per account, because a fine-grained token is approved per
organisation and no single one covers every employer. The app writes each into the Keychain
itself, protected the way the running copy's signature allows: open for an ad-hoc build,
trusting only `/Applications/DevDeck.app` once a signed copy has bound them.

The account id is not shown in Settings. `default` is the account the app starts with and keeps
the un-suffixed Keychain key; accounts added later are `account`, `account-2` and so on, and
`defaults read com.shumer.devdeck` lists them. The token is checked against the API before it is stored, so
a rejected one never lands in the Keychain to fail invisibly later.

While no GitHub account has a token, the app opens its settings window at launch; paste one
there instead. The first GitHub account, the first GitLab instance and the first Azure DevOps
organization also read `DEVDECK_GITHUB_TOKEN` or `GITHUB_TOKEN`, `DEVDECK_GITLAB_TOKEN` or
`GITLAB_TOKEN`, and `DEVDECK_AZURE_DEVOPS_TOKEN` or `AZURE_DEVOPS_EXT_PAT`, from the environment
when the Keychain has nothing for them.

Settings live in the `com.shumer.devdeck` preferences domain. To start over:
`defaults delete com.shumer.devdeck` (tokens survive that - they are in the Keychain).

## Several accounts

One token rarely covers everything: a fine-grained token is approved per organisation, and
some organisations sit behind SAML SSO. **Accounts** in the Settings sidebar holds the list
(**+**, then **GitHub Account**): each account has its own name, its own token in the Keychain
and, under **Advanced**, the organisations it is limited to.

All accounts feed the same cards. Pull requests visible to two accounts are shown once. When
one account fails, the others still render and the card footer says which one is missing;
a card only fails outright when every account fails. With more than one account switched on,
every row carries a chip saying which one it came from.

## Links open as the right identity

github.com allows one signed-in identity per browser profile, so "open in the default browser"
is wrong half the time when work and personal accounts are both on the deck. Each account has
an **Open links in** setting: a browser, and for Chrome, Edge, Brave, Vivaldi and Chromium a
profile as well, listed by the names you gave them. Clicking a row then lands in the profile
that is signed in as that account.

The pickers apply the moment you change them - there is a **Test** button beside them that
opens one page so you can see where it lands. Only the token needs an explicit **Save Token**
(or Return), because it is checked against the API before being stored.

Safari has profiles but no way to choose one from outside the app, and Firefox's `-P` depends
on what is already running; both are offered without a profile picker rather than with one
that would not work.

## Seeing everything

Cards show three rows and a **show N more** line. Clicking it grows the panel to show up to
twelve, pushing the panels below it down; clicking again collapses. It is deliberately not
remembered - expanding is a "let me look at this now" gesture, and a deck that comes back tall
the next morning is a surprise.

## The token

A fine-grained personal access token with read access to **pull requests**, **contents** and
**metadata** covers the pull requests card. The inbox card also needs the account-level
**notifications** permission, read and write so it can mark things read, and the Actions card
needs **actions** (read). Three things
catch people out:

- the **notifications** permission sits under the account section rather than the repository
  section, and without it the inbox card shows
  `Forbidden - Resource not accessible by personal access token`;

- a fine-grained token must be **approved by each organisation** before it can see anything
  there, and until then the API answers with an empty result rather than an error;
- under SAML SSO, a classic token must be **authorised for each organisation** as well.

`scripts/smoke-test.sh` checks the `default` account's token and prints how many repositories
and organisations its open pull requests span; zero organisations where you know there are pull
requests is the fastest way to tell "no open pull requests" from "cannot see the organisation".
It also checks every enabled GitLab instance and Azure DevOps organization, with the token each
one has in the Keychain.

## The Keychain and the password prompt

Tokens live in the login Keychain and nowhere else. How each item is protected follows from how
the app is signed, and the code finds that out for itself at launch:

- **Signed with an identity that survives a rebuild**, a Developer ID or a certificate you made
  in Keychain Access, the Keychain does what it does by default: the item is bound to this
  application, and any other process gets a password prompt. Updates do not prompt, because the
  identity is the same.
- **Ad-hoc signed**, a build made on a machine with no certificate, the items are written with
  an access list that names no application. A Keychain item is normally bound to
  the exact binary that wrote it, and an ad-hoc signature is different for every build, so the
  alternative is one password prompt per token per update. The trade is worth stating plainly:
  any process running as you can then read those tokens without a prompt.

Releases are signed with a Developer ID, and `./build.sh` uses the one in your Keychain when there
is one, so on the author's machine and on every machine that installed a release the tokens are
bound. The first launch after the signature changes rewrites the stored items once, one prompt
each, and remembers the mode. It never goes the other way by itself: a copy without an identity,
`swift run` or a build with `CODESIGN_IDENTITY=-`, leaves bound tokens bound and asks for the
password on each read rather than opening them to every process, and a token it saves is bound
to that copy rather than open, so the signed app asks for it once. Without a Developer ID, a
certificate made in Keychain Access (Certificate Assistant, Create a Certificate, type Code
Signing) and `CODESIGN_IDENTITY="its name" ./build.sh` binds your own tokens the same way. See
[adr/0017-signature-decides.md](adr/0017-signature-decides.md).
