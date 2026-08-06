# GitHub integration

## Why GraphQL

The pull request card needs four things per PR: the review decision, the rolled-up check
state, the number of unresolved threads, and the basics. Over REST that is a search call plus
two or three calls per pull request. Over GraphQL it is one request, which matters because
the budget is 5000 points/hour and the panel polls every two minutes.

## The query

`PullRequestsService.query`, operation `DevDeckPullRequests`. **Two searches in one request**:
GitHub's search syntax cannot express "mine or waiting on me" — `author:@me` and
`review-requested:@me` do not OR — while GraphQL is happy to run both and hand back both, which
costs one round trip rather than two.

```graphql
query DevDeckPullRequests($q: String!, $r: String!, $limit: Int!) {
  mine:      search(query: $q, type: ISSUE, first: $limit) { ...pullRequests }
  reviewing: search(query: $r, type: ISSUE, first: $limit) { ...pullRequests }
}

fragment pullRequests on SearchResultItemConnection {
    issueCount
    nodes {
      ... on PullRequest {
        id number title url isDraft updatedAt
        repository { nameWithOwner owner { login } }
        reviewDecision
        reviewThreads(first: 100) { nodes { isResolved } }
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      }
    }
  }
}
```

Search string, built by `PullRequestsService.searchQuery(settings:)`:

```
is:open is:pr author:@me archived:false sort:updated [draft:false] [org:…]
```

Notes that are easy to get wrong:

- `search` returns `Issue` nodes too. Those decode with every field nil and are dropped in
  `summary(from:)` — do not assume every node is a pull request.
- `issueCount` is the server-side total. The card shows it, not `nodes.count`, so the number
  stays right when the fetch limit truncates the list.
- `statusCheckRollup` is nil when nothing has reported on the head commit; that is "no
  checks", not "failing".
- `ERROR` and `FAILURE` both mean the PR will not merge as it stands, so they collapse into
  `CheckState.failure`.

## Health

`PullRequestSummary.health` is the only thing the card colours a row by:

| Condition | Health |
|---|---|
| checks failed, or changes requested | `blocked` (red) |
| approved, not pending, no unresolved threads | `ready` (green) |
| anything else | `attention` (amber) |

Rows are sorted worst-first, then most recently updated: the reason to look at the card is to
find the pull request that is stuck, and that one is rarely the newest.

## Rate limits and conditional requests

- REST and GraphQL have **separate** budgets, both 5000/hour for a user token.
- `APITransport` parses `x-ratelimit-limit/remaining/used/reset` from every response.
- A `403` with `x-ratelimit-remaining: 0` is a rate limit, not a permission problem — GitHub
  uses the same status for both, and the counter is the only way to tell them apart.
- `X-Poll-Interval` (sent on the notifications endpoint) always wins over the configured
  interval when it asks for more.
- GET requests carry `If-None-Match`; a `304` costs nothing against the budget and is served
  from `HTTPCache`. GraphQL is a POST and deliberately carries no cache key.

## Tokens

Fine-grained personal access token. Permissions per card:

| Card | Permission |
|---|---|
| pull requests | repository: **pull requests** (read), **contents** (read), **metadata** (read) |
| inbox | account: **notifications** (read) — this one is a *user* permission, not a repository one |
| actions | repository: **actions** (read) |

The inbox permission is the one that catches people out: it lives under the account section
rather than the repository section, and without it `/notifications` answers
`403 Resource not accessible by personal access token` — surfaced on the card as
"Forbidden — Resource not accessible by personal access token". A classic token needs the
`notifications` scope instead.

Two further failure modes look like "everything is fine but empty":

1. A fine-grained token must be **approved by each organisation** before it can see anything
   owned by it. Until then search returns zero results with no error.
2. Under SAML SSO a classic token must be **authorised for the organisation**, otherwise the
   API answers `403` with a message about SAML enforcement — surfaced as
   `APIError.forbidden(message)`.

`scripts/smoke-test.sh` prints organisation and repository counts, which distinguishes an
empty result from a token that cannot see the work.

## Several accounts

`GitHubWorkspace` runs every card's fetch once per enabled account, concurrently, and merges
the results. Practical consequences:

- Rate limits are **per token**, so a second account adds budget rather than consuming it.
- Cache keys carry the account id (`github.notifications.<account>`); sharing one would mean
  two tokens revalidating against each other's `ETag`.
- Pull requests visible to two accounts are deduplicated by node id, and the total is reduced
  by exactly what was dropped.
- A failing account becomes an `AccountFailure` on the snapshot, not a thrown error. The card
  only fails when every account does.

## Errors

GraphQL answers `200` with an `errors` array. `GitHubClient` turns that into
`APIError.graphQL([messages])` rather than letting a half-empty payload reach the UI.
`APIError.displayMessage` is what the card shows.

## Inbox — `GET /notifications`

The closest thing GitHub has to a todo list. `NotificationsService` asks for `all=false`
(unread only) with the cache key `github.notifications`.

- The response carries an `ETag`, so a quiet inbox costs a 304 and nothing against the budget.
- `X-Poll-Interval` tells us how often the endpoint may be polled. It is read from the
  response, put on the snapshot and fed into `RefreshPolicy.nextDelay(serverHint:)`, which
  never polls faster than asked.
- `reason` is a growing set. Anything unrecognised becomes `.other` and still shows up — a
  notification nobody can explain is still a notification.
- Rows are sorted unread first, then by `NotificationReason.priority` (security > review
  requested > mention > assigned > CI > the rest), then newest first. `actionableCount` is
  the subset that is genuinely waiting on the user, and that is what the pill counts.
- **Subject URLs are API URLs.** There is no HTML URL in the payload, so
  `InboxItem.webURL(fromSubject:)` rewrites `api.github.com/repos/o/r/pulls/1` into
  `github.com/o/r/pull/1`. The `pulls` → `pull` step is the one that is easy to miss; without
  it every link 404s in a way that looks like a permissions problem. An unfamiliar host is
  passed through untouched rather than mangled.

## Actions — `GET /repos/{owner}/{repo}/actions/runs`

One request per repository, each with its own cache key (`github.actions.owner/name`), fired
concurrently.

- The repository list comes from `actionsRepositories`, or falls back to the repositories of
  the open pull requests (up to five) so the card works with no configuration.
- `created=>=YYYY-MM-DD` bounds the window; the date is UTC, computed by
  `ActionsService.windowStart(from:days:)`.
- A repository answering 404 or 403 is **skipped**, not fatal: one archived or newly private
  repository must not blank a card covering four others. The error only surfaces when every
  repository fails.
- `timed_out`, `action_required` and `startup_failure` all collapse into `.failure` — for the
  person reading the card they mean the same thing.
- `cancelled` and `skipped` are excluded from the success rate; counting them would drag the
  number down for no reason. With nothing decisive in the window the rate is `nil`, drawn as
  `–` rather than a red zero.
- `run_started_at` is absent on older runs, so `created_at` is the fallback anchor for the
  duration.


## Review requests

`review-requested:@me` returns the pull requests where you are still on the hook — GitHub drops
one from that search the moment you submit a review, which is exactly when it should leave the
card. The rows are marked `isReviewRequest`, which changes three things and nothing else: the
health is always `attention` (whatever the checks say, the thing outstanding is you), the code
is `RV`, and the row sorts just under the blocked ones.

A pull request that answers both searches — possible across forks or with some team rules —
is kept once, as yours.

`GitHubSettings.includesReviewRequests` turns it off. The query is then replaced with one that
matches nothing rather than left empty, because GitHub rejects an empty search string.
