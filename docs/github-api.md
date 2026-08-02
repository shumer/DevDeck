# GitHub integration

## Why GraphQL

The pull request card needs four things per PR: the review decision, the rolled-up check
state, the number of unresolved threads, and the basics. Over REST that is a search call plus
two or three calls per pull request. Over GraphQL it is one request, which matters because
the budget is 5000 points/hour and the panel polls every two minutes.

## The query

`PullRequestsService.query`, operation `DevDeckPullRequests`:

```graphql
query DevDeckPullRequests($q: String!, $limit: Int!) {
  search(query: $q, type: ISSUE, first: $limit) {
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

Fine-grained personal access token, read access to **pull requests**, **contents**,
**metadata**. Two failure modes that look like "everything is fine but empty":

1. A fine-grained token must be **approved by each organisation** before it can see anything
   owned by it. Until then search returns zero results with no error.
2. Under SAML SSO a classic token must be **authorised for the organisation**, otherwise the
   API answers `403` with a message about SAML enforcement — surfaced as
   `APIError.forbidden(message)`.

`scripts/smoke-test.sh` prints organisation and repository counts, which distinguishes an
empty result from a token that cannot see the work.

## Errors

GraphQL answers `200` with an `errors` array. `GitHubClient` turns that into
`APIError.graphQL([messages])` rather than letting a half-empty payload reach the UI.
`APIError.displayMessage` is what the card shows.

## Next endpoints

The inbox card will use REST `GET /notifications` — the closest thing GitHub has to a todo
list (`review_requested`, `mention`, `ci_activity`, `state_change`). It supports
`Last-Modified` / `If-Modified-Since` and sends `X-Poll-Interval`, both already handled by
`APITransport`.
