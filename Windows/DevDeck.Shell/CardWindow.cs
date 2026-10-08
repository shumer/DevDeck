using System.Windows;
using System.Windows.Interop;

namespace DevDeck.Shell;

public sealed class CardWindow : Window
{
    private readonly string cardId;
    private readonly Action<CardMeasurement> measured;
    private readonly Action<CardInteraction> interact;
    private nint handle;
    private (int Width, int Height) lastMeasurement;

    public CardWindow(
        CardModel card, Action<CardMeasurement> measured, Action<CardInteraction> interact)
    {
        cardId = card.Id;
        this.measured = measured;
        this.interact = interact;
        AllowsTransparency = false;
        Background = new System.Windows.Media.SolidColorBrush(
            (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString("#FF1C1C1F"));
        ShowActivated = false;
        ShowInTaskbar = false;
        SizeToContent = SizeToContent.Height;
        Width = 352;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        SourceInitialized += OnSourceInitialized;
        SizeChanged += (_, _) => ReportMeasurement();
        Update(card);
    }

    public nint Handle => handle;

    public void Update(CardModel card)
    {
        Content = CardRenderer.Create(card, interact);
        Dispatcher.BeginInvoke(ReportMeasurement, System.Windows.Threading.DispatcherPriority.Loaded);
    }

    public void ApplyPosition(double x, double y)
    {
        if (handle == 0)
        {
            return;
        }
        NativeMethods.SetWindowPos(
            handle, 0, (int)Math.Round(x), (int)Math.Round(y), 0, 0,
            NativeMethods.NoSize | NativeMethods.NoActivate | NativeMethods.NoOwnerOrder | NativeMethods.ShowWindow);
    }

    private void OnSourceInitialized(object? sender, EventArgs eventArguments)
    {
        handle = new WindowInteropHelper(this).Handle;
        NativeMethods.ApplyCardWindowStyles(handle);
        HwndSource.FromHwnd(handle)?.AddHook(WindowProcedure);
    }

    private nint WindowProcedure(nint window, int message, nint word, nint parameter, ref bool handled)
    {
        if (message == NativeMethods.MouseActivate)
        {
            handled = true;
            return NativeMethods.MouseNoActivate;
        }
        return 0;
    }

    private void ReportMeasurement()
    {
        if (handle == 0 || ActualWidth <= 0 || ActualHeight <= 0)
        {
            return;
        }
        var source = PresentationSource.FromVisual(this);
        var scale = source?.CompositionTarget?.TransformToDevice ?? System.Windows.Media.Matrix.Identity;
        var width = (int)Math.Ceiling(ActualWidth * scale.M11);
        var height = (int)Math.Ceiling(ActualHeight * scale.M22);
        if (lastMeasurement == (width, height))
        {
            return;
        }
        lastMeasurement = (width, height);
        measured(new CardMeasurement(cardId, width, height));
    }
}
