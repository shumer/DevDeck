using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace DevDeck.Windows.App;

internal static class WidgetWindow
{
    private const int ExtendedStyle = -20;
    private const long ToolWindow = 0x00000080;
    private const long AppWindow = 0x00040000;

    internal static void ExcludeFromSwitcher(nint handle)
    {
        // ShowInTaskbar alone does not exclude WPF's transparent, unowned windows from Alt+Tab.
        var before = GetWindowLongPtr(handle, ExtendedStyle).ToInt64();
        var after = (before | ToolWindow) & ~AppWindow;
        if (before == after) return;
        Marshal.SetLastPInvokeError(0);
        if (SetWindowLongPtr(handle, ExtendedStyle, (nint)after) == 0 && Marshal.GetLastPInvokeError() != 0)
            throw new Win32Exception(Marshal.GetLastPInvokeError());
        if (!SetWindowPos(handle, 0, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020))
            throw new Win32Exception(Marshal.GetLastPInvokeError());
    }

    internal static bool IsExcluded(Window window)
    {
        var style = ReadStyle(window);
        return (style & ToolWindow) != 0 && (style & AppWindow) == 0;
    }

    internal static long ReadStyle(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        return handle == 0 ? 0 : GetWindowLongPtr(handle, ExtendedStyle).ToInt64();
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern nint GetWindowLongPtr(nint window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern nint SetWindowLongPtr(nint window, int index, nint value);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(nint window, nint after, int x, int y, int cx, int cy, uint flags);
}
