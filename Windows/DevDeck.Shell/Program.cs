using System.Windows;

namespace DevDeck.Shell;

public static class Program
{
    [STAThread]
    public static int Main(string[] arguments)
    {
        if (CredentialCommand.Matches(arguments))
        {
            try
            {
                return CredentialCommand.Run(arguments[1]);
            }
            catch
            {
                return 1;
            }
        }

        NativeMethods.FreeConsole();
        try
        {
            var options = ShellOptions.Parse(arguments);
            var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            var surface = new ShellSurface();
            var engine = new EngineClient(options.EnginePath, options.ConfigurationPath);
            var coordinator = new ShellCoordinator(application.Dispatcher, engine, surface);
            surface.QuitRequested += application.Shutdown;
            application.Startup += async (_, _) =>
            {
                try
                {
                    await coordinator.StartAsync();
                }
                catch
                {
                    application.Shutdown(1);
                }
            };
            application.Exit += (_, _) => coordinator.DisposeAsync().AsTask().GetAwaiter().GetResult();
            return application.Run();
        }
        catch
        {
            return 1;
        }
    }
}

public sealed record ShellOptions(string EnginePath, string? ConfigurationPath)
{
    public static ShellOptions Parse(string[] arguments)
    {
        var enginePath = Path.Combine(AppContext.BaseDirectory, "DevDeckEngineHost.exe");
        string? configurationPath = null;
        for (var index = 0; index < arguments.Length; index += 2)
        {
            if (index + 1 >= arguments.Length)
            {
                throw new ArgumentException();
            }
            switch (arguments[index])
            {
                case "--engine":
                    enginePath = Path.GetFullPath(arguments[index + 1]);
                    break;
                case "--config":
                    configurationPath = Path.GetFullPath(arguments[index + 1]);
                    break;
                default:
                    throw new ArgumentException();
            }
        }
        return new ShellOptions(enginePath, configurationPath);
    }
}
