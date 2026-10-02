using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace DevDeck.Windows.App;

internal static class DesktopRecovery
{
    internal static Size Size(Window card)
    {
        var handle = new WindowInteropHelper(card).Handle;
        if (handle == 0 || !GetWindowRect(handle,out var rectangle)) return new(card.ActualWidth,card.ActualHeight);
        var dpi = System.Windows.Media.VisualTreeHelper.GetDpi(card);
        return new((rectangle.Right - rectangle.Left) / dpi.DpiScaleX,(rectangle.Bottom - rectangle.Top) / dpi.DpiScaleY);
    }
    internal static Rect WorkArea(Window anchor)
    {
        var handle = new WindowInteropHelper(anchor).Handle;
        if (handle == 0) return SystemParameters.WorkArea;
        var rectangle = System.Windows.Forms.Screen.FromHandle(handle).WorkingArea;
        var transform = PresentationSource.FromVisual(anchor)?.CompositionTarget?.TransformFromDevice ?? System.Windows.Media.Matrix.Identity;
        return new Rect(transform.Transform(new Point(rectangle.Left,rectangle.Top)),transform.Transform(new Point(rectangle.Right,rectangle.Bottom)));
    }
    // HWND coordinates are physical pixels; the fallback WorkArea is WPF DIPs.
    internal static void EnsureReachable(Window card)
    {
        var handle = new WindowInteropHelper(card).Handle;
        if (handle == 0 || !GetWindowRect(handle, out var rectangle)) return;
        rectangle.Bottom = Math.Min(rectangle.Bottom, rectangle.Top + 48);
        if (MonitorFromRect(ref rectangle, 0) != 0) return;
        var work = SystemParameters.WorkArea;
        card.Left = work.Left + 24; card.Top = work.Top + 40;
        // Preserve the saved arrangement for when the display returns.
    }
    [StructLayout(LayoutKind.Sequential)] private struct Rectangle { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetWindowRect(nint window, out Rectangle rectangle);
    [DllImport("user32.dll")] private static extern nint MonitorFromRect(ref Rectangle rectangle, uint flags);
}
