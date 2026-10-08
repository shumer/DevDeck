using System.Text.Json;
using System.Windows;
using DevDeck.Shell;

namespace DevDeck.Shell.Tests;

public static class Program
{
    private static int passed;
    private static int failed;

    [STAThread]
    public static int Main()
    {
        Run("protocol preserves engine order and text", ProtocolPreservesEngineModel);
        Run("transport failure uses engine models", TransportFailureUsesEngineModels);
        Run("credential target is account scoped", CredentialTargetIsScoped);
        Run("window is nonactivating and absent from task switchers", WindowIsNonactivating);
        Console.WriteLine();
        Console.WriteLine($"{passed} passed, {failed} failed");
        return failed == 0 ? 0 : 1;
    }

    private static void ProtocolPreservesEngineModel()
    {
        const string json = """
            {"protocolVersion":2,"revision":7,"event":"card.updated","card":{"id":"github.pullRequests","kind":"list","mark":"github","title":"Pull requests","timeText":"12:00:00","hero":{"number":"2","unit":"open","badge":{"text":"blocked","tone":"bad"}},"rows":[{"tone":"bad","chips":[],"title":"First","trailing":"CF","action":"pull.first"},{"tone":"good","chips":[],"title":"Second","trailing":"AP","action":"pull.second"}],"footer":{"text":"2 repos"}}}
            """;
        var message = JsonSerializer.Deserialize<EngineEvent>(json) ?? throw new Exception();
        Equal("First", message.Card?.Rows[0].Title);
        Equal("Second", message.Card?.Rows[1].Title);
        Equal("blocked", message.Card?.Hero.Badge?.Text);
        Equal("bad", message.Card?.Hero.Badge?.Tone);
    }

    private static void TransportFailureUsesEngineModels()
    {
        var fallback = new CardModel
        {
            Id = "project.demo",
            Kind = "project",
            Title = "Project",
            Hero = new CardHero { State = "Engine stopped", Tone = "bad" },
        };
        var state = new ProtocolState();
        var accepted = state.Accept(
            new EngineEvent
            {
                ProtocolVersion = 2,
                Revision = 1,
                Event = "shell.ready",
                Shell = new ShellPresentation { FailureCards = [fallback] },
            });
        True(accepted);
        True(ReferenceEquals(fallback, state.FailureCards[0]));
        True(!state.Accept(new EngineEvent { ProtocolVersion = 2, Revision = 1 }));
    }

    private static void CredentialTargetIsScoped()
    {
        Equal("DevDeck/github", CredentialTarget.ForAccount("github"));
        Throws<ArgumentException>(() => CredentialTarget.ForAccount("../github"));
    }

    private static void WindowIsNonactivating()
    {
        _ = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var before = NativeMethods.GetForegroundWindow();
        var card = new CardModel
        {
            Id = "project.demo",
            Kind = "project",
            Mark = "project",
            Title = "Project",
            Hero = new CardHero { State = "stopped", Tone = "quiet" },
        };
        var window = new CardWindow(card, _ => { }, _ => { });
        window.Show();
        window.Dispatcher.Invoke(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
        var styles = NativeMethods.GetWindowLongPtr(window.Handle, NativeMethods.ExtendedStyleIndex);
        True((styles & NativeMethods.ToolWindowStyle) != 0);
        True((styles & NativeMethods.NoActivateStyle) != 0);
        True(!window.ShowActivated);
        True(!window.ShowInTaskbar);
        if (before != 0)
        {
            Equal(before, NativeMethods.GetForegroundWindow());
        }
        window.Close();
        Application.Current.Shutdown();
    }

    private static void Run(string name, Action test)
    {
        try
        {
            test();
            passed++;
            Console.WriteLine($"  ok   {name}");
        }
        catch (Exception exception)
        {
            failed++;
            Console.WriteLine($"  fail {name}: {exception.GetType().Name}");
        }
    }

    private static void True(bool value)
    {
        if (!value)
        {
            throw new Exception();
        }
    }

    private static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new Exception();
        }
    }

    private static void Throws<T>(Action action) where T : Exception
    {
        try
        {
            action();
        }
        catch (T)
        {
            return;
        }
        throw new Exception();
    }
}
