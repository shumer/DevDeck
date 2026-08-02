# 0004 — Several GitHub accounts, merged into one card

Status: accepted, 2026-08-02

## Context

One token does not cover the work. A fine-grained personal access token has to be approved by
each organisation separately, organisations behind SAML SSO need their own authorisation, and
personal repositories sit under an identity that has nothing to do with the work ones. In
practice covering four organisations means holding three or four tokens.

The alternative — one card per account — was rejected quickly: the question a card answers is
"what do I have open", not "what do I have open in this organisation". Splitting it by token
makes the reader do the merging.

## Decision

- `GitHubAccount` is an identity: slug id, label, base URL, organisations, enabled flag. The
  id is never shown and never changes, because the Keychain entry is filed under it.
- The first account keeps the original un-suffixed Keychain key, so a token stored before
  accounts existed keeps working with no migration step.
- `GitHubWorkspace` fans each card's fetch out over every enabled account concurrently and
  merges the snapshots.
- **A card fails only when every account fails.** Partial failures ride along on the snapshot
  as `[AccountFailure]` and are drawn in the card footer.
- Every model carries `accountID`, so cross-account logic can group by owner.
- Cache keys are namespaced per account.

## Consequences

- Pull requests visible to two accounts are deduplicated by id, and the total count is trimmed
  by exactly what was dropped so the number always matches the list under it.
- The Actions card needs repositories grouped per account rather than one flat list; the
  controller derives that from `accountID` on the pull requests.
- Adding an account is a settings-window action with no restart: the workspace is rebuilt each
  refresh from the stored list.
- The smoke tool only checks the first account — a command-line process does not share the
  app's preferences domain.
- Rate limits are per token, so more accounts means more budget, not less.
