using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace DevDeck.Windows.App;

internal static class WindowVisibility
{
    internal static bool CanRead(Window window)
    {
        if (!window.IsVisible || window.WindowState == WindowState.Minimized) return false;
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == 0 || !GetWindowRect(handle, out var bounds)) return false;
        // Sample the window, not the screen pixels; a fully covered log needs no polling.
        foreach (var x in new[] { bounds.Left + 24, (bounds.Left + bounds.Right) / 2, bounds.Right - 24 })
            foreach (var y in new[] { bounds.Top + 48, (bounds.Top + bounds.Bottom) / 2, bounds.Bottom - 24 })
                if (GetAncestor(WindowFromPoint(new Point { X = x, Y = y }), 2) == handle) return true;
        return false;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint handle, out Rect rect);
    [DllImport("user32.dll")] private static extern nint WindowFromPoint(Point point);
    [DllImport("user32.dll")] private static extern nint GetAncestor(nint handle, uint flags);
}
