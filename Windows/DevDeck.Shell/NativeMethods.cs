using System.Runtime.InteropServices;

namespace DevDeck.Shell;

public static class NativeMethods
{
    public const int ExtendedStyleIndex = -20;
    public const nint ToolWindowStyle = 0x00000080;
    public const nint NoActivateStyle = 0x08000000;
    public const int NoActivate = 0x0010;
    public const int NoOwnerOrder = 0x0200;
    public const int ShowWindow = 0x0040;
    public const int MouseActivate = 0x0021;
    public const nint MouseNoActivate = 3;
    public const int ExitSizeMove = 0x0232;
    public const int DisplayChange = 0x007E;
    public const int WindowCornerPreference = 33;
    public const int RoundedWindowCorners = 2;
    private const int NonClientLeftButtonDown = 0x00A1;
    private const nint Caption = 2;
    private static readonly nint WindowBottom = 1;
    private static readonly nint WindowTopmost = -1;

    public static nint ApplyCardWindowStyles(nint handle)
    {
        var styles = GetWindowLongPtr(handle, ExtendedStyleIndex);
        var updated = styles | ToolWindowStyle | NoActivateStyle;
        SetWindowLongPtr(handle, ExtendedStyleIndex, updated);
        var cornerPreference = RoundedWindowCorners;
        _ = DwmSetWindowAttribute(
            handle, WindowCornerPreference, ref cornerPreference, Marshal.SizeOf<int>());
        return updated;
    }

    public static int GetWindowCornerPreference(nint handle)
    {
        _ = DwmGetWindowAttribute(
            handle, WindowCornerPreference, out var cornerPreference, Marshal.SizeOf<int>());
        return cornerPreference;
    }

    public static void SetWindowFrame(nint handle, int x, int y, int width, int height)
    {
        var scale = DesktopScale();
        _ = SetWindowPos(
            handle,
            0,
            ToDevicePixels(x, scale),
            ToDevicePixels(y, scale),
            ToDevicePixels(width, scale),
            ToDevicePixels(height, scale),
            NoActivate | NoOwnerOrder | ShowWindow);
    }

    public static double[] GetWindowFrame(nint handle)
    {
        if (handle == 0 || !GetWindowRect(handle, out var rectangle))
        {
            return [];
        }

        var scale = DesktopScale();
        return
        [
            FromDevicePixels(rectangle.Left, scale),
            FromDevicePixels(rectangle.Top, scale),
            FromDevicePixels(rectangle.Right - rectangle.Left, scale),
            FromDevicePixels(rectangle.Bottom - rectangle.Top, scale),
        ];
    }

    public static double FromDevicePixels(int value)
    {
        return FromDevicePixels(value, DesktopScale());
    }

    public static void SetWindowLayer(nint handle, string displayMode)
    {
        var layer = displayMode == "floating" ? WindowTopmost : WindowBottom;
        _ = SetWindowPos(handle, layer, 0, 0, 0, 0, 0x0001 | 0x0002 | NoActivate | NoOwnerOrder);
    }

    public static void BeginWindowDrag(nint handle)
    {
        _ = ReleaseCapture();
        _ = SendMessage(handle, NonClientLeftButtonDown, Caption, 0);
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(
        nint handle, int attribute, ref int value, int valueSize);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(
        nint handle, int attribute, out int value, int valueSize);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool FreeConsole();

    [DllImport("user32.dll")]
    private static extern uint GetDpiForSystem();

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    public static extern nint GetWindowLongPtr(nint handle, int index);

    [DllImport("user32.dll")]
    public static extern nint GetForegroundWindow();

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern nint SetWindowLongPtr(nint handle, int index, nint value);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        nint handle, nint insertAfter, int x, int y, int width, int height, int flags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(nint handle, out Rectangle rectangle);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll", EntryPoint = "SendMessageW")]
    private static extern nint SendMessage(nint handle, int message, nint word, nint parameter);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rectangle
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    private static double DesktopScale()
    {
        return GetDpiForSystem() / 96.0;
    }

    private static int ToDevicePixels(int value, double scale)
    {
        return (int)Math.Round(value * scale);
    }

    private static double FromDevicePixels(int value, double scale)
    {
        return value / scale;
    }
}
