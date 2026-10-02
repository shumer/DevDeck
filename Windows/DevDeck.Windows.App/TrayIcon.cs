using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using Forms = System.Windows.Forms;

namespace DevDeck.Windows.App;

/// Uses the documented notification-area API so quiet shared alerts keep their no-sound flag.
internal sealed class TrayIcon : IDisposable
{
    private const int Callback = 0x8000 + 42;
    private readonly HwndSource window = new(new HwndSourceParameters("DevDeck notification area") { WindowStyle = 0, ExtendedWindowStyle = 0x80 });
    private readonly uint taskbarCreated = RegisterWindowMessage("TaskbarCreated");
    private string text = "DevDeck";
    private Dictionary<DeckTrayState, Icon> icons = [];
    private Color ink;
    private int pixels;
    internal DeckTrayState ArtworkState { get; private set; }
    internal Icon Icon => icons[ArtworkState];
    internal uint TaskbarCreatedMessage => taskbarCreated;
    private bool disposed;
    internal bool Added { get; private set; }
    internal nint Handle => window.Handle;
    internal static int NativeDataSize => Marshal.SizeOf<Data>();
    internal Forms.ContextMenuStrip? ContextMenuStrip { get; set; }
    internal event Action? DoubleClick;
    internal event Action? BalloonClicked;
    internal event Action? BalloonClosed;
    internal string Text { get => text; set { text = value; Modify(4); } }
    internal TrayIcon() { RefreshAppearance(); window.AddHook(Hook); Add(); }
    internal void SetAttention(IEnumerable<string> tiers)
    {
        if (disposed) return;
        var state = DeckTrayArtwork.FromTiers(tiers);
        if (state == ArtworkState) return;
        ArtworkState = state; Modify(2);
    }
    private void RefreshAppearance()
    {
        using var theme = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        var light = theme?.GetValue("SystemUsesLightTheme") is int value && value != 0;
        var tint = Forms.SystemInformation.HighContrast ? SystemColors.WindowText : DeckTrayArtwork.Ink(light);
        var edge = Math.Clamp(GetSystemMetricsForDpi(49, GetDpiForWindow(window.Handle)), 16, 128);
        ApplyAppearance(tint, edge);
    }
    internal void ApplyAppearance(Color tint, int edge)
    {
        if (disposed || (ink == tint && pixels == edge && icons.Count > 0)) return;
        var fresh = new Dictionary<DeckTrayState, Icon>();
        try { foreach (var state in Enum.GetValues<DeckTrayState>()) fresh.Add(state, DeckTrayArtwork.Create(state, tint, edge)); }
        catch { foreach (var item in fresh.Values) item.Dispose(); throw; }
        var old = icons; icons = fresh; ink = tint; pixels = edge;
        if (Added) Modify(2);
        foreach (var item in old.Values) item.Dispose();
    }
    private Data State(uint flags) => new() { Size = (uint)Marshal.SizeOf<Data>(), Window = window.Handle, ID = 1, Flags = flags | 0x80,
        CallbackMessage = Callback, Icon = Icon.Handle, Tip = Limit(text, 127), Info = "", InfoTitle = "" };
    private void Add() {
        var data = State(1 | 2 | 4 | 0x80);
        // A repeated shell-created message must not report an existing registration as lost.
        Added = Shell_NotifyIcon(0, ref data) || Shell_NotifyIcon(1, ref data);
        if (Added) { data.TimeoutOrVersion = 4; _ = Shell_NotifyIcon(4, ref data); }
    }
    private void Modify(uint flags) { if (disposed) return; var data = State(flags); _ = Shell_NotifyIcon(1, ref data); }
    internal bool ShowBalloon(string title, string body, bool quiet)
    {
        if (disposed) return false;
        var data = State(0x10); data.InfoTitle = Limit(title, 63); data.Info = Limit(body, 255);
        data.InfoFlags = 1 | 0x80 | (quiet ? 0x10u : 0u);
        return Shell_NotifyIcon(1, ref data);
    }
    internal void HideBalloon() => Modify(0x10);
    private nint Hook(nint hwnd, int message, nint wparam, nint lparam, ref bool handled)
    {
        if (message == taskbarCreated && !disposed) { RefreshAppearance(); Add(); }
        if (message is 0x1A or 0x31A or 0x2E0 && !disposed) RefreshAppearance();
        if (message != Callback) return 0;
        handled = true;
        switch ((int)lparam & 0xFFFF)
        {
            case 0x203: DoubleClick?.Invoke(); break; // WM_LBUTTONDBLCLK
            case 0x205: // WM_RBUTTONUP
            case 0x7B: // WM_CONTEXTMENU
            case 0x401: // NIN_KEYSELECT
                _ = SetForegroundWindow(hwnd);
                var coordinates = (long)wparam;
                ContextMenuStrip?.Show(new System.Drawing.Point((short)(coordinates & 0xFFFF), (short)((coordinates >> 16) & 0xFFFF))); break;
            case 0x403: // NIN_BALLOONHIDE
            case 0x404: // NIN_BALLOONTIMEOUT
                BalloonClosed?.Invoke(); break;
            case 0x405: // NIN_BALLOONUSERCLICK
                BalloonClicked?.Invoke(); break;
        }
        return 0;
    }
    internal static string Limit(string value, int maximum)
    {
        if (value.Length <= maximum) return value;
        var length = char.IsHighSurrogate(value[maximum - 1]) ? maximum - 1 : maximum;
        return value[..length];
    }
    public void Dispose()
    {
        if (disposed) return;
        var data = State(0); _ = Shell_NotifyIcon(2, ref data); disposed = true;
        ContextMenuStrip?.Dispose(); window.Dispose();
        foreach (var item in icons.Values) item.Dispose(); icons.Clear(); Added = false;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Data
    {
        internal uint Size;
        internal nint Window;
        internal uint ID, Flags, CallbackMessage;
        internal nint Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] internal string Tip;
        internal uint State, StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] internal string Info;
        internal uint TimeoutOrVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] internal string InfoTitle;
        internal uint InfoFlags;
        internal Guid Guid;
        internal nint BalloonIcon;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Shell_NotifyIcon(uint message, ref Data data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetForegroundWindow(nint hwnd);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(nint hwnd);
    [DllImport("user32.dll")] private static extern int GetSystemMetricsForDpi(int index, uint dpi);
}
