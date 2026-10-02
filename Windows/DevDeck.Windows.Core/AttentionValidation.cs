namespace DevDeck.Windows.Core;

internal static class AttentionValidation
{
    internal static void Validate(AttentionSnapshot snapshot, string distribution, string operation, ProjectReference? project, RemoteRequest? remote, RemoteSnapshot? remoteSnapshot = null)
    {
        var local = operation is "project.status" or "project.start" or "project.stop" or "project.restart" or "attention.dismiss"
            or "ddev.poweroff.finalize" or "ddev.poweroff.abort";
        var expected = local ? "local:" + distribution : remote?.CardID;
        if ((!local && operation != "remote.snapshot") || snapshot.Scope != expected || snapshot.Items is null || snapshot.Alerts is null
            || snapshot.Items.Length > 1024 || snapshot.Alerts.Length > 1024
            || snapshot.DockerState is not (null or "running" or "notRunning" or "notInstalled" or "starting" or "unknown")) Invalid();
        if (!local && (snapshot.DockerState is not null || snapshot.ContainerStartAllowed is not null)
            || snapshot.DockerState is { } docker && snapshot.ContainerStartAllowed != (docker is "running" or "unknown")) Invalid();
        foreach (var item in snapshot.Items!)
        {
            if (item is null || !ValidText(item.Id, 1024) || !ValidText(item.Key, 2048) || !ValidText(item.Title, 2048)
                || item.Subtitle is null || item.Subtitle.Length > 4096 || item.Tier is not ("waiting" or "needsFixing" or "stuck" or "goodToKnow")
                || item.Mark is not ("github" or "gitlab" or "arc" or "ddev" or "project" or "docker" or "token" or "network" or "rateLimit" or "update" or "unpushed" or "noRemote")
                || item.Since is { } since && (!double.IsFinite(since) || since < 0 || since > 253402300799)) Invalid();
            Action(item!.Action, local, remote);
            if (item.Dismissible && item.Action.Kind != "showCard") Invalid();
            if (item.InboxRead is not null && (local || operation != "remote.snapshot")) Invalid();
            InboxReadValidation.ValidateItem(item, remote, remoteSnapshot);
        }
        foreach (var alert in snapshot.Alerts!)
        {
            if (alert is null || !ValidText(alert.Id, 1024) || !ValidText(alert.Title, 2048) || alert.Subtitle is null || alert.Body is null || alert.Subject is null
                || alert.Body.Length > 4096 || alert.Subtitle.Length > 4096 || alert.Subject.Length > 1024
                || alert.Source is not ("github" or "gitlab" or "arc" or "ddev" or "project" or "docker" or "devdeck")
                || alert.Kind is not ("reviewRequest" or "blocked" or "failedRun" or "wentDown" or "startFailed" or "cantCheck")) Invalid();
            Action(alert!.Target, local, remote);
        }
    }

    private static bool ValidText(string? value, int limit) => !string.IsNullOrWhiteSpace(value) && value.Length <= limit && !value.Any(char.IsControl);
    private static void Action(AttentionAction? action, bool local, RemoteRequest? remote)
    {
        if (action is null || action.Checkout is not null || action.Kind is not ("open" or "accountSettings" or "showCard" or "startDocker" or "openTerminal" or "update" or "menu" or "none")) Invalid();
        if (action!.Kind is "open" or "accountSettings")
        {
            if (local || action.Service is not ("github" or "gitlab") || action.Service != (remote?.Kind == "mergeRequests" ? "gitlab" : "github")
                || action.AccountID is null || remote?.Accounts.Any(account => account.Id == action.AccountID) != true) Invalid();
        }
        if (action.Kind == "open" && (!Uri.TryCreate(action.Url, UriKind.Absolute, out var url) || url.Scheme is not ("http" or "https") || url.UserInfo.Length != 0)) Invalid();
        if (action.Kind == "showCard" && (!local || !ValidText(action.CardID, 128))) Invalid();
        if (action.Kind == "openTerminal" && (!local || action.Path is null || !LinuxPath.IsAbsolute(action.Path))) Invalid();
        if (action.Kind == "startDocker" && !local) Invalid();
    }
    [System.Diagnostics.CodeAnalysis.DoesNotReturn]
    private static void Invalid() => throw new WorkerException("protocolMismatch", "Worker attention contains an invalid scope, item or action.");
}
