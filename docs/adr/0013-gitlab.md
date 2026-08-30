# 0013 - GitLab is its own card, not more rows on the GitHub one

## Status

Accepted.

## Context

Work happens on both. Merge requests waiting on you are exactly as much of "what do I owe today"
as pull requests are, and until now the deck could not see them at all.

Two shapes were possible. One card holding both, since the question is the same one, or a card
each. And underneath that, one API decision: GitLab has both a REST v4 and a GraphQL endpoint,
and the card needs the pipeline verdict, the approval count and the unresolved discussion count
per merge request.

## Decision

**A card of its own**, `gitlab.mergeRequests`, drawn from the GitHub card by changing the nouns
and nothing else: same layout, same row order, same three health words, same eye on a row
somebody is waiting on you for. A reader who has learned what a red row means on one card should
not have to learn it twice.

One card holding both was rejected. The row would have to say which host it came from, which is a
column the GitHub card does not need and would have to grow; the counts in the header would stop
meaning anything specific; and the two halves refresh against different rate limits and fail
independently, so one instance being down would blank rows that have nothing to do with it.

**GraphQL, and `currentUser`.** GitLab's `currentUser` carries `authoredMergeRequests` and
`reviewRequestedMergeRequests`, so both halves of the card arrive in one request with no search
string at all. That is better than the GitHub side, where "mine or waiting on me" needs two
searches because the qualifiers do not OR. REST would need one call per scope plus a call per
merge request for the pipeline.

**The host belongs to the account.** GitLab is routinely self-hosted, so one person can have a
token on gitlab.com and another on a customer's instance, and neither can see the other's merge
requests. `GitLabAccount` therefore carries its own host, its own token key and its own browser
profile, and `GitLabWorkspace` merges the instances into one card the way `GitHubWorkspace`
merges organisations. A host typed as `gitlab.acme.io` or with a path on the end is normalised
rather than rejected.

**Opt-in.** Unlike the GitHub store, which always answers with a default account, the GitLab one
answers with nothing until an instance is added, and the card ships disabled. A deck that has
never heard of GitLab should not carry a card asking for a token to an instance nobody uses.
Adding the first instance turns the card on, because doing that by hand afterwards is a step
nobody would guess at.

**`approvalsLeft` and `conflicts` by name**, rather than reading `detailedMergeStatus`. That
field's vocabulary has changed between GitLab versions, and mapping it again on every upgrade is
work the card does not need: it only ever asks three questions.

## Consequences

- Only resolvable discussions count as unresolved. GitLab calls every comment stream a
  discussion, including ones that can never be resolved, and counting those would leave rows
  permanently unresolved.
- A canceled pipeline counts as failed. For a card, "will not merge as it stands" is the same
  answer whether the pipeline failed or somebody stopped it.
- `AccountFailure` moved from GitHubKit to DevDeckCore, since both integrations now report
  partial failures the same way.
- The token needs `read_api` and nothing more.
