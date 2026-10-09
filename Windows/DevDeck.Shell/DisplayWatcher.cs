using System.Windows.Interop;
using System.Windows.Threading;

namespace DevDeck.Shell;

public sealed class DisplayWatcher : IDisposable
{
    private readonly HwndSource source;
    private readonly Dispatcher dispatcher;
    private bool pending;

    public DisplayWatcher(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        var parameters = new HwndSourceParameters("DevDeck.DisplayWatcher")
        {
            ParentWindow = -3,
            Width = 0,
            Height = 0,
        };
        source = new HwndSource(parameters);
        source.AddHook(WindowProcedure);
    }

    public event Action? Changed;

    public void Dispose()
    {
        source.Dispose();
    }

    private nint WindowProcedure(nint window, int message, nint word, nint parameter, ref bool handled)
    {
        if (message == NativeMethods.DisplayChange && !pending)
        {
            pending = true;
            dispatcher.BeginInvoke(() =>
            {
                pending = false;
                Changed?.Invoke();
            });
        }

        return 0;
    }
}
