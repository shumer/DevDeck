using System.Runtime.InteropServices;

namespace DevDeck.Shell;

public sealed record PhysicalDisplay(string Id, double[] Frame, bool IsPrimary, double Scale);

public static class DisplayProvider
{
    private const int PrimaryDisplay = 1;
    private const uint DeviceInterfaceName = 1;

    public static List<DisplayModel> Current()
    {
        return InPrimaryDisplayDips(PhysicalDisplays(), NativeMethods.PrimaryDesktopScale());
    }

    public static List<DisplayModel> InPrimaryDisplayDips(
        IReadOnlyList<PhysicalDisplay> displays,
        double primaryScale)
    {
        if (primaryScale <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(primaryScale));
        }

        return displays.Select(display => new DisplayModel(
            display.Id,
            display.Frame.Select(value => value / primaryScale).ToArray(),
            display.IsPrimary)).ToList();
    }

    public static string StableId(string interfacePath, string deviceId, string deviceKey)
    {
        foreach (var value in new[] { interfacePath, deviceId, deviceKey })
        {
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }
        throw new InvalidOperationException("Windows did not provide a stable monitor identity.");
    }

    public static double LocalDipsInPrimaryDisplayDips(
        double value,
        double localScale,
        double primaryScale)
    {
        if (localScale <= 0 || primaryScale <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(localScale));
        }
        return value * localScale / primaryScale;
    }

    private static List<PhysicalDisplay> PhysicalDisplays()
    {
        var displays = new List<PhysicalDisplay>();
        _ = EnumDisplayMonitors(0, 0, (monitor, _, _, _) =>
        {
            var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
            if (!GetMonitorInfo(monitor, ref info))
            {
                return true;
            }

            var device = new DisplayDevice { Size = Marshal.SizeOf<DisplayDevice>() };
            if (!EnumDisplayDevices(info.Device, 0, ref device, DeviceInterfaceName))
            {
                return true;
            }

            displays.Add(new PhysicalDisplay(
                StableId(device.DeviceId, device.DeviceKey, device.DeviceString),
                [
                    info.Work.Left,
                    info.Work.Top,
                    info.Work.Right - info.Work.Left,
                    info.Work.Bottom - info.Work.Top,
                ],
                (info.Flags & PrimaryDisplay) != 0,
                MonitorScale(monitor)));
            return true;
        }, 0);
        return displays;
    }

    private static double MonitorScale(nint monitor)
    {
        return GetDpiForMonitor(monitor, 0, out var horizontal, out _) == 0
            ? horizontal / 96.0
            : NativeMethods.PrimaryDesktopScale();
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

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DisplayDevice
    {
        public int Size;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;

        public int StateFlags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceId;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayMonitors(
        nint deviceContext, nint clip, MonitorCallback callback, nint data);

    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);

    [DllImport("user32.dll", EntryPoint = "EnumDisplayDevicesW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayDevices(
        string device, uint index, ref DisplayDevice display, uint flags);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(
        nint monitor, int type, out uint horizontal, out uint vertical);
}
