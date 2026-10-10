using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace DevDeck.Shell;

public sealed class CardWindow : Window
{
    private const double PanelWidth = 352;
    private readonly string cardId;
    private readonly Action<CardMeasurement> measured;
    private readonly Action<CardMove> moved;
    private readonly Action<DeckCommand> command;
    private readonly Action displayChanged;
    private readonly MenuPresenter contextMenu;
    private readonly CardMoveTracker moveTracker = new();
    private nint handle;
    private bool isLocked;
    private (double Width, double Height) lastMeasurement;

    public CardWindow(
        string cardId,
        Action<CardMeasurement> measured,
        Action<CardMove> moved,
        Action<DeckCommand> command,
        Action displayChanged)
    {
        this.cardId = cardId;
        this.measured = measured;
        this.moved = moved;
        this.command = command;
        this.displayChanged = displayChanged;
        contextMenu = new MenuPresenter(command);
        AllowsTransparency = false;
        Background = Brushes.Transparent;
        ShowActivated = false;
        ShowInTaskbar = false;
        SizeToContent = SizeToContent.Manual;
        Width = PanelWidth;
        Height = 44;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        SourceInitialized += OnSourceInitialized;
        MouseLeftButtonDown += OnMouseLeftButtonDown;
        ContextMenu = contextMenu.View;
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

    public void UpdateMenu(JsonElement menu)
    {
        contextMenu.Update(menu);
    }

    public void ApplyFrame(double[] frame)
    {
        if (handle == 0 || frame.Length != 4)
        {
            return;
        }

        moveTracker.BeginProgrammaticMove();
        NativeMethods.SetWindowFrame(handle, frame[0], frame[1], frame[2], frame[3]);
        Dispatcher.BeginInvoke(
            moveTracker.EndProgrammaticMove,
            System.Windows.Threading.DispatcherPriority.ContextIdle);
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

        if (message == NativeMethods.EnterSizeMove)
        {
            moveTracker.BeginDrag();
        }
        else if (message == NativeMethods.ExitSizeMove && moveTracker.EndDrag())
        {
            if (moveTracker.TakeDelayedDpiChange())
            {
                displayChanged();
                Dispatcher.BeginInvoke(
                    () => ReportDragMove(window),
                    System.Windows.Threading.DispatcherPriority.Background);
            }
            else
            {
                ReportDragMove(window);
            }
        }
        else if (message == NativeMethods.WindowPositionChanged && moveTracker.PositionChanged())
        {
            Dispatcher.BeginInvoke(
                ReportSystemMove,
                System.Windows.Threading.DispatcherPriority.Background);
        }
        else if (message == NativeMethods.DpiChanged)
        {
            if (moveTracker.DpiChanged())
            {
                displayChanged();
                Dispatcher.BeginInvoke(
                    ReportMeasurement,
                    System.Windows.Threading.DispatcherPriority.Loaded);
            }
        }

        return 0;
    }

    private void ReportMeasurement()
    {
        if (handle == 0 || Content is not FrameworkElement content)
        {
            return;
        }

        var localScale = VisualTreeHelper.GetDpi(content);
        var primaryScale = NativeMethods.PrimaryDesktopScale();
        content.Measure(new Size(PanelWidth, double.PositiveInfinity));
        var width = Math.Round(
            DisplayProvider.LocalDipsInPrimaryDisplayDips(
                PanelWidth,
                localScale.DpiScaleX,
                primaryScale),
            3);
        var height = Math.Round(
            DisplayProvider.LocalDipsInPrimaryDisplayDips(
                content.DesiredSize.Height,
                localScale.DpiScaleY,
                primaryScale),
            3);
        if (lastMeasurement == (width, height))
        {
            return;
        }

        lastMeasurement = (width, height);
        measured(new CardMeasurement(cardId, [width, height]));
    }

    private void ReportSystemMove()
    {
        if (moveTracker.FlushSystemMove())
        {
            moved(new CardMove(cardId, NativeMethods.GetWindowFrame(handle)));
        }
    }

    private void ReportDragMove(nint window)
    {
        moved(new CardMove(cardId, NativeMethods.GetWindowFrame(window)));
        ReportMeasurement();
    }
}
