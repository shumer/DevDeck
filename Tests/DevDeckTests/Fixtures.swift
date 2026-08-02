import Foundation

/// Recorded shape of the `DevDeckPullRequests` GraphQL response.
///
/// Kept as a literal rather than a resource file: the suite is a plain executable, so there
/// is no `Bundle.module` to load resources from.
enum Fixtures {
    /// Four pull requests covering every health state, plus an `Issue` node — search returns
    /// those too, and they must be dropped rather than crash the decoder.
    static let pullRequestSearch = """
    {
      "data": {
        "search": {
          "issueCount": 7,
          "nodes": [
            {
              "id": "PR_failing",
              "number": 412,
              "title": "feat/composer-block",
              "url": "https://github.com/acme/newsroom/pull/412",
              "isDraft": false,
              "updatedAt": "2026-08-01T10:00:00Z",
              "repository": { "nameWithOwner": "acme/newsroom", "owner": { "login": "acme" } },
              "reviewDecision": null,
              "reviewThreads": { "nodes": [{ "isResolved": false }, { "isResolved": false }, { "isResolved": true }] },
              "commits": { "nodes": [{ "commit": { "statusCheckRollup": { "state": "FAILURE" } } }] }
            },
            {
              "id": "PR_changes",
              "number": 88,
              "title": "fix/pb-image-fill",
              "url": "https://github.com/acme/daily/pull/88",
              "isDraft": false,
              "updatedAt": "2026-07-30T09:00:00Z",
              "repository": { "nameWithOwner": "acme/daily", "owner": { "login": "acme" } },
              "reviewDecision": "CHANGES_REQUESTED",
              "reviewThreads": { "nodes": [] },
              "commits": { "nodes": [{ "commit": { "statusCheckRollup": { "state": "SUCCESS" } } }] }
            },
            {
              "id": "PR_ready",
              "number": 5,
              "title": "chore/bundle-bump",
              "url": "https://github.com/shumer/tools/pull/5",
              "isDraft": false,
              "updatedAt": "2026-08-01T08:00:00Z",
              "repository": { "nameWithOwner": "shumer/tools", "owner": { "login": "shumer" } },
              "reviewDecision": "APPROVED",
              "reviewThreads": { "nodes": [{ "isResolved": true }] },
              "commits": { "nodes": [{ "commit": { "statusCheckRollup": { "state": "SUCCESS" } } }] }
            },
            {
              "id": "PR_draft",
              "number": 13,
              "title": "spike/arc-bundles",
              "url": "https://github.com/acme/newsroom/pull/13",
              "isDraft": true,
              "updatedAt": "2026-07-29T12:00:00Z",
              "repository": { "nameWithOwner": "acme/newsroom", "owner": { "login": "acme" } },
              "reviewDecision": null,
              "reviewThreads": { "nodes": [] },
              "commits": { "nodes": [{ "commit": { "statusCheckRollup": null } }] }
            },
            {}
          ]
        }
      }
    }
    """

    static let graphQLErrors = """
    {
      "data": null,
      "errors": [
        { "message": "Although you appear to have the correct authorization credentials, the organization has enabled OIDC access restrictions", "type": "FORBIDDEN" }
      ]
    }
    """
}
