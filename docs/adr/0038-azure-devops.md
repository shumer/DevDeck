# 0038 - Azure DevOps is the third card of the same shape

## Status

Accepted.

## Context

Work happens on Azure DevOps too. Pull requests waiting on a vote from you are the same "what
do I owe today" as a GitHub review request or a GitLab one, and until now the deck could not
see them. The user's case: the cloud service at `dev.azure.com`, one organization, every pull
request they opened or were asked to review.

Azure DevOps has no GraphQL. Its REST API lists pull requests with their reviewers and votes,
but a pull request's build results and branch policy evaluations are separate calls per pull
request, and the list says who created something and when, not when it was last touched.

## Decision

**A card of its own**, `azure.pullRequests`, drawn from the GitHub card by changing the nouns and
nothing else, for the reasons [adr/0013](0013-gitlab.md) gave for GitLab: same layout, same row
order, same three health words, same eye on a row somebody is waiting on you for. `AzureKit`
mirrors `GitLabKit` file for file.

**The organization belongs to the account.** A personal access token on Azure DevOps is minted
per organization, so `AzureAccount` carries the organization, its own token key (`azure`,
`azure.<id>`) and its own browser profile, and `AzureWorkspace` merges organizations into one
card the way the other workspaces merge accounts. Whatever is pasted into the field, a bare name,
`https://dev.azure.com/acme/...` or `acme.visualstudio.com`, is reduced to the one word the URL
wants. Only the cloud service: an on-premises server has a different host and a different sign-in,
and nobody asked for it.

**Three REST calls per refresh.** `_apis/connectionData` for who the token belongs to, because
the list filters by a person's id and has no "me". Then `_apis/git/pullrequests` at the
organization root, once with `searchCriteria.creatorId` and once with `searchCriteria.reviewerId`,
both `status=active`. The root rather than a project list, so a token with the Code (Read) scope
alone is enough. A review request is a row from the second list where your vote is still zero
and you did not open it; a vote cast, approved or not, takes the row off the card.

**Health from the merge check and the votes, not from builds or policies.** A conflict, a failed
merge or a reviewer waiting for the author blocks a row; a required vote still owed, no approval
yet, a draft or a merge still being computed needs someone; approved and mergeable is ready.
Build results and policy evaluations would be one request per pull request on every refresh,
and the list is what is polled.

**A personal access token as HTTP Basic**, empty user name, the token as the password: the one
form the service documents for a PAT. A token the service does not accept is not refused with a
401 but answered with a sign-in page and a success status, so HTML where JSON was expected is
read as unauthorized rather than as a decoding error.

**Opt-in**, like GitLab: the store answers with nothing until an organization is added, the card
ships disabled, and adding the first organization turns it on.

## Consequences

- The one date a row has is when it was opened. Sorting within a tier is newest first by that
  date, and a row's age in the menu is its age, not the time since it last moved.
- Timestamps come with seven fractional digits, which no ISO 8601 formatter on the platform
  takes as they are; the fraction is cut to three before parsing.
- The web address of a pull request is built by the card
  (`{organization}/{project}/_git/{repository}/pullrequest/{number}`), because the list only
  knows the API address.
- `AttentionService`, `DeckLinkService`, `DeckAlert.Source`, `AttentionMark` and `DeckMark` each
  gained `azure`, and the shared brand marks gained its mark; the golden transcripts carry the
  card from this change on.
- The token needs **Code (Read)** and nothing more.
