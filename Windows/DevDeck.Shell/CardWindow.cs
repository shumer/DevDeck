using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace DevDeck.Shell;

public sealed class CardWindow : Window
{
    private readonly string cardId;
    private readonly Action<CardMeasurement> measured;
    private readonly Action<CardMove> moved;
    private readonly Action<DeckCommand> command;
    private nint handle;
    private bool isLocked;
    private (int Width, int Height) lastMeasurement;

    public CardWindow(
        string cardId,
        Action<CardMeasurement> measured,
        Action<CardMove> moved,
        Action<DeckCommand> command)
    {
        this.cardId = cardId;
        this.measured = measured;
        this.moved = moved;
        this.command = command;
        AllowsTransparency = false;
        Background = Brushes.Transparent;
        ShowActivated = false;
        ShowInTaskbar = false;
        SizeToContent = SizeToContent.Manual;
        Width = 352;
        Height = 44;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        SourceInitialized += OnSourceInitialized;
        MouseLeftButtonDown += OnMouseLeftButtonDown;
    }

    public nint Handle => handle;

    public void Update(JsonElement model)
    {
        Content = CardRenderer.Create(model, command);
        Dispatcher.BeginInvoke(ReportMeasurement, System.Windows.Threading.DispatcherPriority.Loaded);
    }

    public void ShowStopped(JsonElement stopped, JsonElement? status)
    {
        Content = CardRenderer.CreateStopped(stopped, status);
    }

    public void ApplyFrame(double[] frame)
    {
        if (handle == 0 || frame.Length != 4)
        {
            return;
        }

        NativeMethods.SetWindowFrame(
            handle,
            (int)Math.Round(frame[0]),
            (int)Math.Round(frame[1]),
            (int)Math.Round(frame[2]),
            (int)Math.Round(frame[3]));
    }

    public double[] CurrentFrame()
    {
        return NativeMethods.GetWindowFrame(handle);
    }

    public void SetLocked(bool locked)
    {
        isLocked = locked;
    }

    public void SetDisplayMode(string displayMode)
    {
        if (handle != 0)
        {
            NativeMethods.SetWindowLayer(handle, displayMode);
        }
    }

    private void OnSourceInitialized(object? sender, EventArgs eventArguments)
    {
        handle = new WindowInteropHelper(this).Handle;
        if (HwndSource.FromHwnd(handle)?.CompositionTarget is { } target)
        {
            target.BackgroundColor = Colors.Transparent;
        }
        NativeMethods.ApplyCardWindowStyles(handle);
        HwndSource.FromHwnd(handle)?.AddHook(WindowProcedure);
    }

    private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs eventArguments)
    {
        if (!isLocked && handle != 0)
        {
            NativeMethods.BeginWindowDrag(handle);
        }
    }

    private nint WindowProcedure(nint window, int message, nint word, nint parameter, ref bool handled)
    {
        if (message == NativeMethods.MouseActivate)
        {
            handled = true;
            return NativeMethods.MouseNoActivate;
        }

        if (message == NativeMethods.ExitSizeMove)
        {
            moved(new CardMove(cardId, NativeMethods.GetWindowFrame(window)));
        }

        return 0;
    }

    private void ReportMeasurement()
    {
        if (handle == 0 || Content is not FrameworkElement content)
        {
            return;
        }

        var frame = NativeMethods.GetWindowFrame(handle);
        var availableWidth = frame[2];
        content.Measure(new Size(availableWidth, double.PositiveInfinity));
        var width = (int)Math.Ceiling(frame[2]);
        var height = (int)Math.Ceiling(content.DesiredSize.Height);
        if (lastMeasurement == (width, height))
        {
            return;
        }

        lastMeasurement = (width, height);
        measured(new CardMeasurement(cardId, [width, height]));
    }
}
