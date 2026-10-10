using System.Text.Json;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace DevDeck.Shell;

[Flags]
public enum SummonModifiers : uint
{
    None = 0,
    Alt = 0x0001,
    Control = 0x0002,
    Shift = 0x0004,
    Windows = 0x0008,
}

public sealed record SummonShortcut(SummonModifiers Modifiers, uint VirtualKey, string KeyName)
{
    public const string DefaultText = "Ctrl+Shift+Space";

    public static SummonShortcut Parse(string? value)
    {
        var text = value ?? DefaultText;
        var parts = text.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0)
        {
            throw new FormatException("The summon shortcut is empty.");
        }

        var modifiers = SummonModifiers.None;
        uint? virtualKey = null;
        string? keyName = null;
        foreach (var part in parts)
        {
            if (Modifier(part) is { } modifier)
            {
                if ((modifiers & modifier) != 0)
                {
                    throw new FormatException("The summon shortcut repeats a modifier.");
                }
                modifiers |= modifier;
                continue;
            }

            if (virtualKey is not null || !TryKey(part, out var parsedKey, out var parsedName))
            {
                throw new FormatException("The summon shortcut has an unknown key.");
            }
            virtualKey = parsedKey;
            keyName = parsedName;
        }

        if (virtualKey is null || modifiers == SummonModifiers.None)
        {
            throw new FormatException("The summon shortcut needs a modifier and one key.");
        }
        return new SummonShortcut(modifiers, virtualKey.Value, keyName!);
    }

    public override string ToString()
    {
        var parts = new List<string>();
        Add(SummonModifiers.Control, "Ctrl");
        Add(SummonModifiers.Alt, "Alt");
        Add(SummonModifiers.Shift, "Shift");
        Add(SummonModifiers.Windows, "Win");
        parts.Add(KeyName);
        return string.Join('+', parts);

        void Add(SummonModifiers modifier, string name)
        {
            if ((Modifiers & modifier) != 0)
            {
                parts.Add(name);
            }
        }
    }

    private static SummonModifiers? Modifier(string value)
    {
        return value.ToUpperInvariant() switch
        {
            "CTRL" or "CONTROL" => SummonModifiers.Control,
            "ALT" => SummonModifiers.Alt,
            "SHIFT" => SummonModifiers.Shift,
            "WIN" or "WINDOWS" => SummonModifiers.Windows,
            _ => null,
        };
    }

    private static bool TryKey(string value, out uint virtualKey, out string name)
    {
        var upper = value.ToUpperInvariant();
        if (upper.Length == 1 && upper[0] is >= 'A' and <= 'Z' or >= '0' and <= '9')
        {
            virtualKey = upper[0];
            name = upper;
            return true;
        }
        if (upper.Length is 2 or 3 && upper[0] == 'F' &&
            int.TryParse(upper.AsSpan(1), out var function) && function is >= 1 and <= 24)
        {
            virtualKey = (uint)(0x70 + function - 1);
            name = $"F{function}";
            return true;
        }

        var key = upper switch
        {
            "BACKSPACE" => (0x08u, "Backspace"),
            "TAB" => (0x09u, "Tab"),
            "ENTER" => (0x0Du, "Enter"),
            "SPACE" => (0x20u, "Space"),
            "PAGEUP" => (0x21u, "PageUp"),
            "PAGEDOWN" => (0x22u, "PageDown"),
            "END" => (0x23u, "End"),
            "HOME" => (0x24u, "Home"),
            "LEFT" => (0x25u, "Left"),
            "UP" => (0x26u, "Up"),
            "RIGHT" => (0x27u, "Right"),
            "DOWN" => (0x28u, "Down"),
            "INSERT" => (0x2Du, "Insert"),
            "DELETE" => (0x2Eu, "Delete"),
            _ => (0u, ""),
        };
        virtualKey = key.Item1;
        name = key.Item2;
        return virtualKey != 0;
    }
}

public sealed record SummonPreferences(bool Enabled, bool Dims, string? ShortcutText)
{
    public static bool TryParse(JsonElement answer, out SummonPreferences preferences)
    {
        preferences = new SummonPreferences(false, false, null);
        if (!JsonModel.Object(answer, "preferences", out var tagged) ||
            !JsonModel.Object(tagged, "_0", out var model))
        {
            return false;
        }

        preferences = new SummonPreferences(
            DeckEvent.RequiredBool(model, "summonEnabled"),
            DeckEvent.RequiredBool(model, "summonDims"),
            DeckEvent.OptionalString(model, "summonShortcutWindows"));
        return true;
    }
}

public sealed record SummonPresentation(bool IsRaised, bool Dims);

public sealed class SummonState
{
    // This mirrors DeckRuntime.summonLatchThreshold until the protocol carries the value.
    public const double LatchThresholdSeconds = 0.25;
    private double? pressedAt;
    private bool isLatched;
    private bool dims;

    public bool IsEnabled { get; private set; }
    public bool IsRaised { get; private set; }

    public event Action<SummonPresentation>? Changed;

    public void ApplyPreferences(SummonPreferences preferences)
    {
        var dimsChanged = dims != preferences.Dims;
        IsEnabled = preferences.Enabled;
        dims = preferences.Dims;
        if (!IsEnabled)
        {
            Dismiss();
        }
        else if (IsRaised && dimsChanged)
        {
            Changed?.Invoke(new SummonPresentation(true, dims));
        }
    }

    public void Press(double now)
    {
        if (!IsEnabled || pressedAt is not null)
        {
            return;
        }
        if (isLatched)
        {
            Dismiss();
            return;
        }

        pressedAt = now;
        SetRaised(true);
    }

    public void Release(double now)
    {
        if (pressedAt is not { } start)
        {
            return;
        }
        pressedAt = null;
        if (now - start < LatchThresholdSeconds)
        {
            isLatched = true;
            return;
        }
        SetRaised(false);
    }

    public void Present()
    {
        if (!IsEnabled || IsRaised)
        {
            return;
        }
        pressedAt = null;
        isLatched = true;
        SetRaised(true);
    }

    public void Dismiss()
    {
        pressedAt = null;
        isLatched = false;
        SetRaised(false);
    }

    private void SetRaised(bool value)
    {
        if (IsRaised == value)
        {
            return;
        }
        IsRaised = value;
        Changed?.Invoke(new SummonPresentation(value, dims));
    }
}

public sealed class SummonController : IDisposable
{
    private readonly SummonState state = new();
    private readonly SummonHotKeyWindow hotKey;
    private SummonShortcut? shortcut;

    public SummonController(Dispatcher dispatcher, Action<SummonPresentation> changed)
    {
        hotKey = new SummonHotKeyWindow(
            dispatcher,
            state.Press,
            state.Release,
            state.Dismiss);
        state.Changed += presentation =>
        {
            hotKey.SetEscapeEnabled(presentation.IsRaised);
            changed(presentation);
        };
    }

    public void ApplyPreferences(SummonPreferences preferences)
    {
        SummonShortcut? parsed = null;
        if (preferences.Enabled)
        {
            try
            {
                parsed = SummonShortcut.Parse(preferences.ShortcutText);
            }
            catch (FormatException exception)
            {
                Console.Error.WriteLine($"Summon shortcut could not be registered: {exception.Message}");
            }
        }

        if (shortcut != parsed)
        {
            state.Dismiss();
        }
        shortcut = parsed;
        state.ApplyPreferences(preferences);
        hotKey.Configure(shortcut);
    }

    public void Present()
    {
        state.Present();
    }

    public void Dismiss()
    {
        state.Dismiss();
    }

    public void Dispose()
    {
        state.Dismiss();
        hotKey.Dispose();
    }
}

internal sealed class SummonHotKeyWindow : IDisposable
{
    private const int SummonId = 1;
    private const int EscapeId = 2;
    private const uint NoRepeat = 0x4000;
    private const uint EscapeKey = 0x1B;
    private const int ReleasePollMilliseconds = 15;
    private readonly HwndSource source;
    private readonly Dispatcher dispatcher;
    private readonly System.Threading.Timer releaseTimer;
    private readonly Action<double> pressed;
    private readonly Action<double> released;
    private readonly Action dismissed;
    private SummonShortcut? shortcut;
    private int isPressed;
    private bool summonRegistered;
    private bool escapeRegistered;

    public SummonHotKeyWindow(
        Dispatcher dispatcher,
        Action<double> pressed,
        Action<double> released,
        Action dismissed)
    {
        this.dispatcher = dispatcher;
        this.pressed = pressed;
        this.released = released;
        this.dismissed = dismissed;
        var parameters = new HwndSourceParameters("DevDeck.Summon")
        {
            ParentWindow = 0,
            Width = 0,
            Height = 0,
            WindowStyle = unchecked((int)0x80000000),
        };
        source = new HwndSource(parameters);
        source.AddHook(WindowProcedure);
        releaseTimer = new System.Threading.Timer(OnReleaseTimer);
    }

    public void Configure(SummonShortcut? value)
    {
        if (shortcut == value)
        {
            return;
        }
        StopReleaseTimer();
        if (summonRegistered)
        {
            _ = NativeMethods.UnregisterGlobalHotKey(source.Handle, SummonId);
            summonRegistered = false;
        }

        shortcut = value;
        if (shortcut is null)
        {
            return;
        }
        summonRegistered = NativeMethods.RegisterGlobalHotKey(
            source.Handle,
            SummonId,
            (uint)shortcut.Modifiers | NoRepeat,
            shortcut.VirtualKey,
            out var error);
        if (!summonRegistered)
        {
            Console.Error.WriteLine(
                $"Summon shortcut {shortcut} could not be registered: Windows error {error}.");
        }
    }

    public void SetEscapeEnabled(bool enabled)
    {
        if (enabled == escapeRegistered)
        {
            return;
        }
        if (enabled)
        {
            escapeRegistered = NativeMethods.RegisterGlobalHotKey(
                source.Handle,
                EscapeId,
                NoRepeat,
                EscapeKey,
                out var error);
            if (!escapeRegistered)
            {
                Console.Error.WriteLine(
                    $"Escape could not dismiss Summon: Windows error {error}.");
            }
        }
        else
        {
            _ = NativeMethods.UnregisterGlobalHotKey(source.Handle, EscapeId);
            escapeRegistered = false;
        }
    }

    public void Dispose()
    {
        StopReleaseTimer();
        SetEscapeEnabled(false);
        if (summonRegistered)
        {
            _ = NativeMethods.UnregisterGlobalHotKey(source.Handle, SummonId);
        }
        releaseTimer.Dispose();
        source.Dispose();
    }

    private nint WindowProcedure(nint window, int message, nint word, nint parameter, ref bool handled)
    {
        if (message != NativeMethods.HotKey)
        {
            return 0;
        }

        handled = true;
        if (word == SummonId && shortcut is not null &&
            Interlocked.CompareExchange(ref isPressed, 1, 0) == 0)
        {
            var pressedAt = Now();
            _ = releaseTimer.Change(ReleasePollMilliseconds, ReleasePollMilliseconds);
            pressed(pressedAt);
        }
        else if (word == EscapeId)
        {
            dismissed();
        }
        return 0;
    }

    private void OnReleaseTimer(object? state)
    {
        if (shortcut is not null && NativeMethods.IsKeyDown(shortcut.VirtualKey))
        {
            return;
        }
        var releasedAt = Now();
        _ = releaseTimer.Change(Timeout.Infinite, Timeout.Infinite);
        dispatcher.BeginInvoke(
            () => CompleteRelease(releasedAt),
            DispatcherPriority.Send);
    }

    private void StopReleaseTimer()
    {
        _ = releaseTimer.Change(Timeout.Infinite, Timeout.Infinite);
        Interlocked.Exchange(ref isPressed, 0);
    }

    private void CompleteRelease(double releasedAt)
    {
        if (Interlocked.Exchange(ref isPressed, 0) == 0)
        {
            return;
        }
        released(releasedAt);
    }

    private static double Now()
    {
        return System.Diagnostics.Stopwatch.GetTimestamp() /
            (double)System.Diagnostics.Stopwatch.Frequency;
    }
}

internal sealed class SummonVeilWindow : Window
{
    private const double VeilOpacity = 0.30;
    private readonly double[] frame;
    private nint handle;

    public SummonVeilWindow(DisplayModel display, Action dismiss)
    {
        frame = display.Frame;
        AllowsTransparency = true;
        Background = Brushes.Black;
        Opacity = VeilOpacity;
        ShowActivated = false;
        ShowInTaskbar = false;
        SizeToContent = SizeToContent.Manual;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        Focusable = false;
        SourceInitialized += OnSourceInitialized;
        PreviewMouseDown += (_, eventArguments) =>
        {
            eventArguments.Handled = true;
            dismiss();
        };
    }

    public void ShowVeil()
    {
        Show();
        PositionVeil();
        Dispatcher.BeginInvoke(PositionVeil, DispatcherPriority.ContextIdle);
    }

    private void OnSourceInitialized(object? sender, EventArgs eventArguments)
    {
        handle = new WindowInteropHelper(this).Handle;
        NativeMethods.ApplyNonActivatingToolWindow(handle);
    }

    private void PositionVeil()
    {
        if (handle == 0 || frame.Length != 4)
        {
            return;
        }

        NativeMethods.SetWindowFrame(handle, frame[0], frame[1], frame[2], frame[3]);
        NativeMethods.SetWindowTopmost(handle);
    }
}
