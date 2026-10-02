namespace DevDeck.Windows.Core;

/// Keeps actionable UI wording separate from fixed English transport/platform diagnostics.
public sealed class HostFailure(string code, string message) : IOException(message)
{
    public string Code { get; } = code;
}

public static class FailureText
{
    public static string For(Exception error, Localization locale)
    {
        var code = error switch { WorkerException worker => worker.Code, HostFailure host => host.Code, _ => null };
        var key = code switch {
            "credentialsRejected" => "error.unauthorized", "forbidden" => "error.forbidden", "unreachable" => "error.offline",
            "rateLimited" => "error.rateLimited", "disconnected" => "windows.workerDisconnected",
            "launchFailed" or "wslUnavailable" => "windows.wslUnavailable",
            "invalidResponse" or "protocolMismatch" or "frameTooLarge" or "invalidRequest" or "invalidRequestID" or "unsupportedVersion" => "windows.workerInvalid",
            "timedOut" => "windows.workerTimedOut", "commandFailed" => "windows.commandFailed", "outcomeNotConfirmed" => "windows.outcomeNotConfirmed",
            "cancelled" => "windows.cancelled", "unsupportedOperation" => "windows.workerUpdateRequired",
            "ddevUnavailable" => "windows.ddevUnavailable", "dockerUnavailable" => "windows.dockerUnavailable", "linuxNodeUnavailable" => "windows.linuxNodeUnavailable",
            "fusionUnavailable" => "windows.fusionUnavailable", "composeUnavailable" => "windows.composeUnavailable",
            "preflightUnavailable" => "windows.preflightUnavailable", "portConflict" => "windows.portConflict",
            "missingFolder" => "windows.folderUnavailable", "invalidProject" or "missingProject" or "wrongDistribution" => "windows.projectSettingsInvalid",
            "remoteUnavailable" => "windows.remoteUnavailable", "remoteActionFailed" => "windows.remoteActionFailed",
            "invalidRemote" or "missingRemote" => "windows.remoteSettingsInvalid",
            "workerArchitectureUnsupported" => "windows.workerArchitectureUnsupported",
            "workerSetupFailed" or "workerHomeInvalid" or "workerSetupInvalid" => "windows.workerSetupFailed",
            "credentialReadFailed" or "credentialTooLarge" => "windows.credentialReadFailed",
            "credentialWriteFailed" => "windows.credentialWriteFailed", "credentialDeleteFailed" => "windows.credentialDeleteFailed",
            "tokenInvalid" => "windows.tokenInvalid", "browserUnavailable" => "windows.browserUnavailable",
            "logFileUnavailable" => "windows.logFileUnavailable",
            _ when error is WorkerException => "windows.workerRejected", _ => null
        };
        return key is null ? error.Message : locale.Get(key);
    }
}
