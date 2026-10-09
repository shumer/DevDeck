using System.Runtime.InteropServices;

namespace DevDeck.Shell;

public static class DisplayProvider
{
    private const int PrimaryDisplay = 1;

    public static List<DisplayModel> Current()
    {
        var displays = new List<DisplayModel>();
        _ = EnumDisplayMonitors(0, 0, (monitor, _, _, _) =>
        {
            var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
            if (GetMonitorInfo(monitor, ref info))
            {
                displays.Add(
                    new DisplayModel(
                        info.Device,
                        [
                            NativeMethods.FromDevicePixels(info.Work.Left),
                            NativeMethods.FromDevicePixels(info.Work.Top),
                            NativeMethods.FromDevicePixels(info.Work.Right - info.Work.Left),
                            NativeMethods.FromDevicePixels(info.Work.Bottom - info.Work.Top),
                        ],
                        (info.Flags & PrimaryDisplay) != 0));
            }
            return true;
        }, 0);
        return displays;
    }

    private delegate bool MonitorCallback(nint monitor, nint deviceContext, nint rectangle, nint data);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rectangle
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfo
    {
        public int Size;
        public Rectangle Monitor;
        public Rectangle Work;
        public int Flags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string Device;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayMonitors(
        nint deviceContext, nint clip, MonitorCallback callback, nint data);

    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);
}
