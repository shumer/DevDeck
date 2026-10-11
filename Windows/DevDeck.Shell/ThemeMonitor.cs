using Microsoft.Win32;
using System.Windows.Media;
using System.Windows.Threading;
using UISettings = global::Windows.UI.ViewManagement.UISettings;
using UIColorType = global::Windows.UI.ViewManagement.UIColorType;

namespace DevDeck.Shell;

// Follows the Windows scheme: reads it, applies its palette, and applies it again when it changes,
// without a restart.
public sealed class ThemeMonitor : IDisposable
{
    private const string PersonalizeKey = @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private readonly Dispatcher dispatcher;
    private readonly Func<ThemeInputs> read;
    private readonly UISettings? settings;

    public ThemeMonitor(Dispatcher dispatcher, Func<ThemeInputs>? read = null)
    {
        this.dispatcher = dispatcher;
        this.read = read ?? ReadSystem;
        Inputs = this.read();
        WindowsTheme.Apply(DeckPalette.For(Inputs));
        if (read is null)
        {
            // UISettings reports the app mode and the accent; the taskbar accent and transparency
            // only arrive as a setting change.
            settings = new UISettings();
            settings.ColorValuesChanged += OnColorValuesChanged;
            SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        }
    }

    public event Action<DeckPalette>? Changed;

    public ThemeInputs Inputs { get; private set; }

    public void Refresh()
    {
        var next = read();
        if (next == Inputs)
        {
            return;
        }
        Inputs = next;
        var palette = DeckPalette.For(next);
        WindowsTheme.Apply(palette);
        Changed?.Invoke(palette);
    }

    public void Dispose()
    {
        if (settings is not null)
        {
            settings.ColorValuesChanged -= OnColorValuesChanged;
            SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        }
    }

    public static ThemeInputs ReadSystem()
    {
        var settings = new UISettings();
        var background = settings.GetColorValue(UIColorType.Background);
        return new ThemeInputs(
            background.R + background.G + background.B > 3 * 128,
            Registry.GetValue(PersonalizeKey, "EnableTransparency", 1) is not int transparency || transparency != 0,
            Registry.GetValue(PersonalizeKey, "ColorPrevalence", 0) is int prevalence && prevalence != 0,
            Convert(settings.GetColorValue(UIColorType.AccentLight2)),
            Convert(settings.GetColorValue(UIColorType.AccentDark1)),
            Convert(settings.GetColorValue(UIColorType.AccentDark2)),
            Registry.GetValue(PersonalizeKey, "SystemUsesLightTheme", 0) is int system && system != 0);
    }

    private static Color Convert(global::Windows.UI.Color colour)
    {
        return Color.FromArgb(colour.A, colour.R, colour.G, colour.B);
    }

    private void OnColorValuesChanged(UISettings sender, object arguments)
    {
        _ = dispatcher.BeginInvoke(Refresh);
    }

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs arguments)
    {
        _ = dispatcher.BeginInvoke(Refresh);
    }
}
