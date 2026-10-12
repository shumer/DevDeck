using System.Text.Json;
using System.Windows;

namespace DevDeck.Shell;

public static class Program
{
    [STAThread]
    public static int Main(string[] arguments)
    {
        try
        {
            var options = ShellOptions.Parse(arguments);
            if (options.Quit)
            {
                var user = System.Security.Principal.WindowsIdentity.GetCurrent().User?.Value;
                var timer = System.Diagnostics.Stopwatch.StartNew();
                var liveClosed = SingleInstance.RequestQuit(
                    SingleInstance.Name(false, user), TimeSpan.FromSeconds(10));
                var remaining = TimeSpan.FromSeconds(10) - timer.Elapsed;
                var replayClosed = SingleInstance.RequestQuit(
                    SingleInstance.Name(true, user), remaining);
                return liveClosed && replayClosed ? 0 : 1;
            }
            if (options.EnableLoginItem)
            {
                NativeMethods.AttachToParentConsole();
                return WindowsLoginItem.Current().SetEnabled(true) ? 0 : 1;
            }
            if (options.DeveloperRequest is not null)
            {
                NativeMethods.AttachToParentConsole();
                return DeveloperCommands.RunAsync(options.EnginePath, options.DeveloperRequest)
                    .GetAwaiter()
                    .GetResult();
            }

            using var instance = SingleInstance.For(options.ReplayPath is not null);
            if (!instance.IsFirst)
            {
                // A second launch opens the running deck's settings, as it does on the Mac: a
                // person who started the app again wants a window, and this is the one it has.
                instance.SignalFirst();
                return 0;
            }

            var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            var surface = new ShellSurface();
            using var trace = options.TracePath is { } tracePath ? new ProtocolTrace(tracePath) : null;
            var coordinator = new ShellCoordinator(application.Dispatcher, options.EnginePath, surface, trace);
            instance.OnSignal(() => application.Dispatcher.BeginInvoke(() =>
                surface.OpenSettings(JsonDocument.Parse("""{"kind":"openSettings","page":"general"}""").RootElement)));
            instance.OnQuit(() => application.Dispatcher.BeginInvoke(() =>
                _ = coordinator.RequestShutdownAsync()));
            application.Startup += async (_, _) =>
            {
                if (options.ReplayPath is { } replay)
                {
                    await coordinator.StartReplayAsync(replay);
                }
                else
                {
                    await coordinator.StartLiveAsync();
                }
            };
            return application.Run();
        }
        catch (Exception exception) when (
            exception is ArgumentException or IOException or UnauthorizedAccessException or System.Text.Json.JsonException)
        {
            return 1;
        }
    }
}

public sealed record ShellOptions(
    string EnginePath,
    string? ReplayPath,
    DeveloperRequest? DeveloperRequest,
    bool EnableLoginItem,
    string? TracePath = null,
    bool Quit = false)
{
    public static ShellOptions Parse(string[] arguments)
    {
        var executableDirectory = Path.GetDirectoryName(Environment.ProcessPath)
            ?? AppContext.BaseDirectory;
        var enginePath = Path.Combine(executableDirectory, "DevDeckEngineHost.exe");
        string? replayPath = null;
        DeveloperRequest? developerRequest = null;
        var enableLoginItem = false;
        string? tracePath = null;
        var quit = false;
        for (var index = 0; index < arguments.Length; index++)
        {
            switch (arguments[index])
            {
                case "--quit":
                    quit = true;
                    break;
                case "--engine":
                    enginePath = Path.GetFullPath(Value(arguments, ref index));
                    break;
                case "--replay":
                    replayPath = Path.GetFullPath(Value(arguments, ref index));
                    break;
                case "--add-project":
                    developerRequest = new DeveloperRequest(
                        DeveloperRequestKind.AddProject,
                        Path.GetFullPath(Value(arguments, ref index)));
                    break;
                case "--remove-project":
                    developerRequest = new DeveloperRequest(
                        DeveloperRequestKind.RemoveProject,
                        Value(arguments, ref index));
                    break;
                case "--trace":
                    tracePath = Path.GetFullPath(Value(arguments, ref index));
                    break;
                case "--enable-login-item":
                    enableLoginItem = true;
                    break;
                default:
                    throw new ArgumentException();
            }
        }

        if ((replayPath is not null && developerRequest is not null) ||
            (enableLoginItem && (replayPath is not null || developerRequest is not null)) ||
            (quit && (enableLoginItem || developerRequest is not null)))
        {
            throw new ArgumentException();
        }

        return new ShellOptions(enginePath, replayPath, developerRequest, enableLoginItem, tracePath, quit);
    }

    private static string Value(string[] arguments, ref int index)
    {
        index++;
        if (index >= arguments.Length || arguments[index].Length == 0)
        {
            throw new ArgumentException();
        }

        return arguments[index];
    }
}

public enum DeveloperRequestKind
{
    AddProject,
    RemoveProject,
}

public sealed record DeveloperRequest(DeveloperRequestKind Kind, string Value);
