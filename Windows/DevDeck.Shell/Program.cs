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
            if (options.DeveloperRequest is not null)
            {
                return DeveloperCommands.RunAsync(options.EnginePath, options.DeveloperRequest)
                    .GetAwaiter()
                    .GetResult();
            }

            _ = NativeMethods.FreeConsole();
            var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            var surface = new ShellSurface();
            var coordinator = new ShellCoordinator(application.Dispatcher, options.EnginePath, surface);
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
            application.Exit += (_, _) => coordinator.DisposeAsync().AsTask().GetAwaiter().GetResult();
            return application.Run();
        }
        catch (Exception exception) when (
            exception is ArgumentException or IOException or UnauthorizedAccessException or System.Text.Json.JsonException)
        {
            return 1;
        }
    }
}

public sealed record ShellOptions(string EnginePath, string? ReplayPath, DeveloperRequest? DeveloperRequest)
{
    public static ShellOptions Parse(string[] arguments)
    {
        var executableDirectory = Path.GetDirectoryName(Environment.ProcessPath)
            ?? AppContext.BaseDirectory;
        var enginePath = Path.Combine(executableDirectory, "DevDeckEngineHost.exe");
        string? replayPath = null;
        DeveloperRequest? developerRequest = null;
        for (var index = 0; index < arguments.Length; index++)
        {
            switch (arguments[index])
            {
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
                default:
                    throw new ArgumentException();
            }
        }

        if (replayPath is not null && developerRequest is not null)
        {
            throw new ArgumentException();
        }

        return new ShellOptions(enginePath, replayPath, developerRequest);
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
