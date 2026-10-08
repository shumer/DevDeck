using System.Runtime.InteropServices;

namespace DevDeck.Shell;

public static class NativeMethods
{
    public const int ExtendedStyleIndex = -20;
    public const nint ToolWindowStyle = 0x00000080;
    public const nint NoActivateStyle = 0x08000000;
    public const int NoSize = 0x0001;
    public const int NoActivate = 0x0010;
    public const int NoOwnerOrder = 0x0200;
    public const int ShowWindow = 0x0040;
    public const int MouseActivate = 0x0021;
    public const nint MouseNoActivate = 3;

    public static nint ApplyCardWindowStyles(nint handle)
    {
        var styles = GetWindowLongPtr(handle, ExtendedStyleIndex);
        var updated = styles | ToolWindowStyle | NoActivateStyle;
        SetWindowLongPtr(handle, ExtendedStyleIndex, updated);
        return updated;
    }

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool FreeConsole();

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    public static extern nint GetWindowLongPtr(nint handle, int index);

    [DllImport("user32.dll")]
    public static extern nint GetForegroundWindow();

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern nint SetWindowLongPtr(nint handle, int index, nint value);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetWindowPos(
        nint handle, nint insertAfter, int x, int y, int width, int height, int flags);
}
