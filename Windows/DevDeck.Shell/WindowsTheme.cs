using Microsoft.Win32;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace DevDeck.Shell;

public static class WindowsTheme
{
    private const string PersonalizeKey = @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private static bool isLoaded;
    private static ResourceDictionary? styles;
    private static ResourceDictionary? paletteResources;
    private static readonly List<(string Key, WeakReference<SolidColorBrush> Brush)> liveBrushes = [];

    // The scheme the shell draws in now. Dark until a ThemeMonitor reads Windows.
    public static DeckPalette Current { get; private set; } = DeckPalette.For(ThemeInputs.Default);

    public static void EnsureLoaded()
    {
        if (isLoaded || Application.Current is null)
        {
            return;
        }

        // The styles reach the palette by DynamicResource, so a scheme change replaces these entries.
        // Anything in the application's resources is frozen, which is why views built in code get
        // brushes of their own from Brush.
        paletteResources = [];
        foreach (var key in DeckPalette.Keys)
        {
            paletteResources[key] = new SolidColorBrush(Current[key]);
        }
        Application.Current.Resources.MergedDictionaries.Add(paletteResources);
        styles = new ResourceDictionary
        {
            Source = new Uri("/DevDeck.Shell;component/WindowsStyles.xaml", UriKind.Relative),
        };
        Application.Current.Resources.MergedDictionaries.Add(styles);
        isLoaded = true;
    }

    public static void Apply(DeckPalette palette)
    {
        Current = palette;
        if (!isLoaded || styles is null)
        {
            EnsureLoaded();
            return;
        }
        foreach (var key in DeckPalette.Keys)
        {
            paletteResources![key] = new SolidColorBrush(palette[key]);
        }
        // Brushes handed to views built in code follow in place.
        liveBrushes.RemoveAll(entry => !entry.Brush.TryGetTarget(out _));
        foreach (var (key, reference) in liveBrushes)
        {
            if (reference.TryGetTarget(out var brush))
            {
                brush.Color = palette[key];
            }
        }
    }

    // A window's frame and backdrop in the scheme: dark or light title bar and Acrylic.
    public static void ApplyWindowChrome(nint handle)
    {
        NativeMethods.SetDarkMode(handle, !Current.IsLight);
    }

    public static Style Style(string key)
    {
        EnsureLoaded();
        return (Style)Application.Current.FindResource(key);
    }

    // A palette brush of the view's own that keeps following the scheme; anything else from the
    // resources as it is.
    public static Brush Brush(string key)
    {
        EnsureLoaded();
        if (!DeckPalette.Keys.Contains(key))
        {
            return (Brush)Application.Current.FindResource(key);
        }
        var brush = new SolidColorBrush(Current[key]);
        liveBrushes.Add((key, new WeakReference<SolidColorBrush>(brush)));
        if (liveBrushes.Count % 512 == 0)
        {
            liveBrushes.RemoveAll(entry => !entry.Brush.TryGetTarget(out _));
        }
        return brush;
    }

    public static Brush Tone(string? tone)
    {
        return tone switch
        {
            "good" => Brush("ToneGood"),
            "attention" => Brush("ToneAttention"),
            "alert" => Brush("ToneAlert"),
            "personal" => Brush("TonePersonal"),
            _ => Brush("TextPrimary"),
        };
    }

    public static Brush ToneFill(string? tone)
    {
        return new SolidColorBrush(Current.ToneTint(tone));
    }

    // A Windows 11 primary button: the accent shade the scheme uses, with text that reads on it.
    public static (Brush Fill, Brush Text) AccentButton()
    {
        return (new SolidColorBrush(Current.AccentFill), new SolidColorBrush(Current.AccentText));
    }

    // The card's surface in the current scheme: a tint over Acrylic, or solid without transparency.
    public static Brush CardSurface()
    {
        return new SolidColorBrush(Current.CardTint);
    }

    public static Border CardFrame(FrameworkElement content)
    {
        var frame = new Border
        {
            Background = CardSurface(),
            BorderBrush = Brush("ControlStroke"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(16, 14, 16, 14),
            Child = content,
        };
        RenderOptions.SetClearTypeHint(frame, ClearTypeHint.Enabled);
        return frame;
    }

    public static Border CollapsedCardFrame(FrameworkElement content)
    {
        var frame = CardFrame(content);
        frame.Padding = new Thickness(16, 6, 16, 6);
        frame.Height = 44;
        return frame;
    }

    public static FontFamily Sans => (FontFamily)Application.Current.FindResource("DevDeckSans");
    public static FontFamily Mono => (FontFamily)Application.Current.FindResource("DevDeckMono");
}
