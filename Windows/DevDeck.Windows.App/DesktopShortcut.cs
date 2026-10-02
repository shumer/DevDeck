using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace DevDeck.Windows.App;

internal sealed class DesktopShortcut : IDisposable
{
    private readonly HwndSource source;
    private readonly Action summon;
    private const int Identifier = 0xDD01;
    internal bool Registered { get; }
    internal DesktopShortcut(Action summon)
    {
        this.summon = summon;
        source = new HwndSource(new HwndSourceParameters("DevDeck shortcut") { ParentWindow = (nint)(-3) });
        source.AddHook(Message);
        Registered = RegisterHotKey(source.Handle, Identifier, 0x0001 | 0x0002 | 0x4000, 0x20);
    }
    private nint Message(nint hwnd, int message, nint wparam, nint lparam, ref bool handled)
    {
        if (message == 0x0312 && wparam == Identifier) { handled = true; summon(); }
        return 0;
    }
    public void Dispose() { if (Registered) UnregisterHotKey(source.Handle, Identifier); source.Dispose(); }
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(nint hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(nint hwnd, int id);
}
