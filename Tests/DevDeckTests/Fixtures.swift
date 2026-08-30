import Foundation

/// Recorded shape of the `DevDeckPullRequests` GraphQL response.
///
/// Kept as a literal rather than a resource file: the suite is a plain executable, so there
/// is no `Bundle.module` to load resources from.
enum Fixtures {
    /// Four pull requests covering every health state, plus an `Issue` node - search returns
    /// those too, and they must be dropped rather than crash the decoder.
    static let pullRequestSearch = """
    {
      "data": {
        "mine": {
          "issueCount": 7,
          "nodes": [
            {
              "id": "PR_failing",
              "number": 412,
              "title": "feat/composer-block",
              "url": "https://github.com/editoria/ledwall/pull/412",
              "isDraft": false,
              "updatedAt": "2026-08-01T10:00:00Z",
              "repository": { "nameWithOwner": "editoria/ledwall", "owner": { "login": "editoria" } },
              "reviewDecision": null,
              "reviewThreads": { "nodes": [{ "isResolved": false }, { "isResolved": false }, { "isResolved": true }] },
              "commits": { "nodes": [{ "commit": { "statusCheckRollup": { "state": "FAILURE" } } }] }
            },
            {
              "id": "PR_changes",
              "number": 88,
              "title": "fix/pb-image-fill",
              "url": "https://github.com/editoria/ilgiornale/pull/88",
              "isDraft": false,
              "updatedAt": "2026-07-30T09:00:00Z",
              "repository": { "nameWithOwner": "editoria/ilgiornale", "owner": { "login": "editoria" } },
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
              "url": "https://github.com/editoria/ledwall/pull/13",
              "isDraft": true,
              "updatedAt": "2026-07-29T12:00:00Z",
              "repository": { "nameWithOwner": "editoria/ledwall", "owner": { "login": "editoria" } },
              "reviewDecision": null,
              "reviewThreads": { "nodes": [] },
              "commits": { "nodes": [{ "commit": { "statusCheckRollup": null } }] }
            },
            {}
          ]
        },
        "reviewing": {
          "issueCount": 1,
          "nodes": [
            {
              "id": "PR_review",
              "number": 902,
              "title": "IW-164 - Approvers resource for the proofing API",
              "url": "https://github.com/editoria/ledwall/pull/902",
              "isDraft": false,
              "updatedAt": "2026-07-28T07:00:00Z",
              "repository": { "nameWithOwner": "editoria/ledwall", "owner": { "login": "editoria" } },
              "reviewDecision": "APPROVED",
              "reviewThreads": { "nodes": [] },
              "commits": { "nodes": [{ "commit": { "statusCheckRollup": { "state": "SUCCESS" } } }] }
            }
          ]
        }
      }
    }
    """

    /// The same pull request answering both searches, which a fork or a team rule can produce.
    static let pullRequestOverlap = """
    {
      "data": {
        "mine": {
          "issueCount": 1,
          "nodes": [
            {
              "id": "PR_same",
              "number": 5,
              "title": "chore/bundle-bump",
              "url": "https://github.com/shumer/tools/pull/5",
              "isDraft": false,
              "updatedAt": "2026-08-01T08:00:00Z",
              "repository": { "nameWithOwner": "shumer/tools", "owner": { "login": "shumer" } },
              "reviewDecision": "APPROVED",
              "reviewThreads": { "nodes": [] },
              "commits": { "nodes": [{ "commit": { "statusCheckRollup": { "state": "SUCCESS" } } }] }
            }
          ]
        },
        "reviewing": {
          "issueCount": 1,
          "nodes": [
            {
              "id": "PR_same",
              "number": 5,
              "title": "chore/bundle-bump",
              "url": "https://github.com/shumer/tools/pull/5",
              "isDraft": false,
              "updatedAt": "2026-08-01T08:00:00Z",
              "repository": { "nameWithOwner": "shumer/tools", "owner": { "login": "shumer" } },
              "reviewDecision": "APPROVED",
              "reviewThreads": { "nodes": [] },
              "commits": { "nodes": [{ "commit": { "statusCheckRollup": { "state": "SUCCESS" } } }] }
            }
          ]
        }
      }
    }
    """

    /// `GET /notifications`, covering the reasons the card sorts by and a subject with no URL.
    static let notifications = """
    [
      {
        "id": "1",
        "unread": true,
        "reason": "review_requested",
        "updated_at": "2026-08-01T10:00:00Z",
        "subject": { "title": "Add the ledwall feed loop", "url": "https://api.github.com/repos/editoria/ledwall/pulls/412", "type": "PullRequest" },
        "repository": { "full_name": "editoria/ledwall" }
      },
      {
        "id": "2",
        "unread": true,
        "reason": "ci_activity",
        "updated_at": "2026-08-01T11:00:00Z",
        "subject": { "title": "main failed", "url": null, "type": "CheckSuite" },
        "repository": { "full_name": "editoria/ilgiornale" }
      },
      {
        "id": "3",
        "unread": true,
        "reason": "mention",
        "updated_at": "2026-08-01T09:00:00Z",
        "subject": { "title": "Schema question", "url": "https://api.github.com/repos/editoria/ledwall/issues/77", "type": "Issue" },
        "repository": { "full_name": "editoria/ledwall" }
      },
      {
        "id": "4",
        "unread": false,
        "reason": "brand_new_reason",
        "updated_at": "2026-08-01T12:00:00Z",
        "subject": { "title": "Something new", "url": "https://api.github.com/repos/shumer/tools/issues/3", "type": "Issue" },
        "repository": { "full_name": "shumer/tools" }
      }
    ]
    """

    /// `GET /repos/{owner}/{repo}/actions/runs` for the first repository.
    static let workflowRunsPrimary = """
    {
      "total_count": 4,
      "workflow_runs": [
        {
          "id": 1,
          "name": "ci",
          "head_branch": "main",
          "status": "completed",
          "conclusion": "success",
          "created_at": "2026-08-01T10:00:00Z",
          "run_started_at": "2026-08-01T10:00:00Z",
          "updated_at": "2026-08-01T10:06:00Z",
          "html_url": "https://github.com/editoria/ledwall/actions/runs/1"
        },
        {
          "id": 2,
          "name": "ci",
          "head_branch": "main",
          "status": "completed",
          "conclusion": "timed_out",
          "created_at": "2026-08-01T09:00:00Z",
          "run_started_at": "2026-08-01T09:00:00Z",
          "updated_at": "2026-08-01T09:10:00Z",
          "html_url": "https://github.com/editoria/ledwall/actions/runs/2"
        },
        {
          "id": 3,
          "name": "nightly",
          "head_branch": "main",
          "status": "completed",
          "conclusion": "cancelled",
          "created_at": "2026-08-01T08:00:00Z",
          "run_started_at": "2026-08-01T08:00:00Z",
          "updated_at": "2026-08-01T08:01:00Z",
          "html_url": "https://github.com/editoria/ledwall/actions/runs/3"
        },
        {
          "id": 4,
          "name": "deploy",
          "head_branch": "main",
          "status": "in_progress",
          "conclusion": null,
          "created_at": "2026-08-01T12:00:00Z",
          "updated_at": "2026-08-01T12:02:00Z",
          "html_url": "https://github.com/editoria/ledwall/actions/runs/4"
        }
      ]
    }
    """

    /// A second repository, so the multi-repository behaviour is covered.
    static let workflowRunsSecondary = """
    {
      "total_count": 1,
      "workflow_runs": [
        {
          "id": 9,
          "name": "ci",
          "head_branch": "main",
          "status": "completed",
          "conclusion": "success",
          "created_at": "2026-08-01T07:00:00Z",
          "run_started_at": "2026-08-01T07:00:00Z",
          "updated_at": "2026-08-01T07:04:00Z",
          "html_url": "https://github.com/shumer/tools/actions/runs/9"
        }
      ]
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
