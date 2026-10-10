using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace DevDeck.Shell;

public static class ToastShortcutRegistration
{
    public const string AppId = "DevDeck.Shell";
    private const uint AssociationChanged = 0x08000000;
    private const uint ItemIdList = 0x0000;
    private static readonly PropertyKey AppUserModelId = new(
        new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
        5);

    public static void Ensure()
    {
        var executable = Environment.ProcessPath
            ?? throw new InvalidOperationException("The shell executable path is unavailable.");
        var shortcutPath = ShortcutPath(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData));
        var directory = Path.GetDirectoryName(shortcutPath)
            ?? throw new InvalidOperationException("The Start Menu path is unavailable.");
        Directory.CreateDirectory(directory);

        var result = SetCurrentProcessExplicitAppUserModelID(AppId);
        if (result != 0)
        {
            Marshal.ThrowExceptionForHR(result);
        }

        object instance = new ShellLink();
        try
        {
            var shortcut = (IShellLinkW)instance;
            shortcut.SetPath(executable);
            shortcut.SetWorkingDirectory(Path.GetDirectoryName(executable) ?? AppContext.BaseDirectory);
            shortcut.SetDescription("DevDeck");
            shortcut.SetIconLocation(executable, 0);

            var store = (IPropertyStore)instance;
            using var value = PropertyVariant.FromString(AppId);
            var key = AppUserModelId;
            store.SetValue(ref key, value);
            store.Commit();
            ((IPersistFile)instance).Save(shortcutPath, true);
        }
        finally
        {
            _ = Marshal.FinalReleaseComObject(instance);
        }
        SHChangeNotify(AssociationChanged, ItemIdList, 0, 0);
    }

    public static string ShortcutPath(string applicationData)
    {
        return Path.Combine(
            applicationData,
            "Microsoft",
            "Windows",
            "Start Menu",
            "Programs",
            "DevDeck.lnk");
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    [DllImport("shell32.dll")]
    private static extern void SHChangeNotify(uint eventId, uint flags, nint firstItem, nint secondItem);

    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    private sealed class ShellLink;

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    private interface IShellLinkW
    {
        void GetPath(nint file, int maximum, nint data, uint flags);
        void GetIdList(out nint itemIdList);
        void SetIdList(nint itemIdList);
        void GetDescription(nint name, int maximum);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
        void GetWorkingDirectory(nint directory, int maximum);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string directory);
        void GetArguments(nint arguments, int maximum);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string arguments);
        void GetHotKey(out short hotKey);
        void SetHotKey(short hotKey);
        void GetShowCommand(out int showCommand);
        void SetShowCommand(int showCommand);
        void GetIconLocation(nint iconPath, int maximum, out int iconIndex);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string iconPath, int iconIndex);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(nint window, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string path);
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    private interface IPropertyStore
    {
        void GetCount(out uint count);
        void GetAt(uint index, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropertyVariant value);
        void SetValue(ref PropertyKey key, [In] PropertyVariant value);
        void Commit();
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct PropertyKey(Guid formatId, uint propertyId)
    {
        public Guid FormatId = formatId;
        public uint PropertyId = propertyId;
    }

    [StructLayout(LayoutKind.Explicit)]
    private sealed class PropertyVariant : IDisposable
    {
        [FieldOffset(0)]
        private ushort valueType;

        [FieldOffset(8)]
        private nint pointerValue;

        public static PropertyVariant FromString(string value)
        {
            return new PropertyVariant
            {
                valueType = 31,
                pointerValue = Marshal.StringToCoTaskMemUni(value),
            };
        }

        public void Dispose()
        {
            if (pointerValue != 0)
            {
                Marshal.FreeCoTaskMem(pointerValue);
                pointerValue = 0;
            }
        }
    }
}
