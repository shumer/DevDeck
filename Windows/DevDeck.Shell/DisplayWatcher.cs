using Microsoft.Win32;
using System.Windows.Interop;
using System.Windows.Threading;

namespace DevDeck.Shell;

public sealed class DisplayChangePublisher
{
    private readonly Func<IReadOnlyList<DisplayModel>> current;

    public DisplayChangePublisher(Func<IReadOnlyList<DisplayModel>> current)
    {
        this.current = current;
    }

    public event Action<IReadOnlyList<DisplayModel>>? Changed;

    public void Publish()
    {
        Changed?.Invoke(current());
    }
}

public sealed class DisplayWatcher : IDisposable
{
    private readonly HwndSource source;
    private readonly Dispatcher dispatcher;
    private readonly DisplayChangePublisher publisher;
    private bool pending;

    public DisplayWatcher(Dispatcher dispatcher, Func<IReadOnlyList<DisplayModel>> current)
    {
        this.dispatcher = dispatcher;
        publisher = new DisplayChangePublisher(current);
        publisher.Changed += displays => Changed?.Invoke(displays);
        var parameters = new HwndSourceParameters("DevDeck.DisplayWatcher")
        {
            ParentWindow = 0,
            Width = 0,
            Height = 0,
            WindowStyle = unchecked((int)0x80000000),
        };
        source = new HwndSource(parameters);
        source.AddHook(WindowProcedure);
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
    }

    public event Action<IReadOnlyList<DisplayModel>>? Changed;

    public void Refresh()
    {
        if (pending)
        {
            return;
        }
        pending = true;
        dispatcher.BeginInvoke(() =>
        {
            pending = false;
            publisher.Publish();
        });
    }

    public void Dispose()
    {
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        source.Dispose();
    }

    private nint WindowProcedure(nint window, int message, nint word, nint parameter, ref bool handled)
    {
        if (message == NativeMethods.DisplayChange ||
            message == NativeMethods.SettingChange && word == NativeMethods.SetWorkArea)
        {
            Refresh();
        }
        return 0;
    }

    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs eventArguments)
    {
        if (eventArguments.Mode == PowerModes.Resume)
        {
            Refresh();
        }
    }
}
