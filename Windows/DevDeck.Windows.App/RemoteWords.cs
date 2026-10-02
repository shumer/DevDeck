using System;
using System.Collections.Generic;
using System.Linq;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal static class RemoteWords
{
    internal static string Pill(RemoteSnapshot value) => value.Kind switch {
        "inbox" => value.ActionableCount > 0 ? Text.L("card.inbox.forYou", value.ActionableCount) : Text.L(value.Total == 0 ? "card.pill.clear" : "card.inbox.nothingForYou"),
        "actions" => value.RepositoryCount == 0 ? Quiet(value) : value.SuccessRate is null ? Text.L("card.actions.noRuns") : Text.L(value.Blocked > 0 || value.SuccessRate < .8 ? "card.actions.attention" : "card.actions.healthy"),
        _ => value.Blocked > 0 ? Text.L("card.pill.blocked", value.Blocked) : value.ReviewCount > 0 ? Text.L("card.pill.toReview", value.ReviewCount) : Text.L(value.Total == 0 ? "card.pill.clear" : "card.pill.onTrack") };
    internal static string Collapsed(RemoteSnapshot value) => value.Kind switch {
        "inbox" => value.ActionableCount > 0 ? Text.L("card.inbox.forYouUnread", value.ActionableCount, value.Total) : value.Total == 0 ? Text.L("card.pill.clear") : Text.L("card.inbox.unread", value.Total),
        "actions" => value.RepositoryCount == 0 ? Quiet(value) : value.Blocked > 0 ? Text.L("card.actions.failing",value.Blocked) : value.SuccessRate is { } rate ? Text.L("card.actions.green", Math.Round(rate * 100)) : Text.L("card.actions.noRuns"),
        _ => value.Blocked > 0 ? Text.L("card.pill.blockedOpen", value.Blocked,value.Total) : value.ReviewCount > 0 ? Text.L("card.pill.toReviewOpen",value.ReviewCount,value.Total) : value.Total == 0 ? Text.L("card.pill.clear") : Text.L("card.pill.open",value.Total) };
    internal static string Quiet(RemoteSnapshot value) => Text.L(value.FollowsPullRequests ? "card.actions.noOpenPRs" : "card.actions.noRepos");
    internal static string Summary(RemoteSnapshot value)
    {
        if (value.Kind is "pullRequests" or "mergeRequests") return Text.L("card.footer.pair", Text.LN(value.Kind == "pullRequests" ? "card.repos" : "card.projects", value.RepositoryCount), Text.LN(value.Kind == "pullRequests" ? "card.orgs" : "card.groups",value.NamespaceCount));
        if (value.Kind == "inbox") return value.Total == 0 ? Text.L("card.inbox.empty") : Text.LN("card.repos",value.RepositoryCount);
        var parts = new List<string>();
        if (value.RunningCount > 0) parts.Add(Text.L("card.actions.running",value.RunningCount));
        if (value.Blocked > 0) parts.Add(Text.L("card.actions.failed",value.Blocked));
        if (parts.Count == 0) parts.Add(Text.LN(value.FollowsPullRequests ? "card.actions.repos.fromPulls" : "card.actions.repos.fromList",value.RepositoryCount));
        if (value.AverageDurationSeconds is { } seconds) {
            var total = (int)Math.Round(seconds);
            parts.Add(Text.L("card.actions.avg", total < 60 ? Text.L("card.duration.seconds",total) : Text.L("card.duration.minutes",total / 60,total % 60)));
        }
        return string.Join(" · ",parts);
    }
    internal static string Age(double? updatedAt) {
        if (updatedAt is null) return "";
        var minutes = Math.Max(0, (DateTimeOffset.UtcNow.ToUnixTimeSeconds() - updatedAt.Value) / 60);
        return minutes < 1.5 ? Text.L("attention.age.now") : minutes < 60 ? Text.L("attention.age.minutes", (int)minutes) : minutes < 1440 ? Text.L("attention.age.hours", (int)(minutes / 60)) : Text.L("attention.age.days", (int)(minutes / 1440));
    }
}
