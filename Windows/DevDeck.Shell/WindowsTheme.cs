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
    private static ResourceDictionary? windowResources;
    private static readonly ResourceDictionary cardResources = [];
    private static readonly List<(string Key, bool ForCard, WeakReference<SolidColorBrush> Brush)> liveBrushes = [];

    // Cards are drawn in the taskbar's material; windows, menus and dialogs follow the app mode, as
    // any Windows application does. Both are dark until a ThemeMonitor reads Windows.
    public static DeckPalette CardPalette { get; private set; } = DeckPalette.ForCards(ThemeInputs.Default);

    public static DeckPalette WindowPalette { get; private set; } = DeckPalette.ForWindows(ThemeInputs.Default);

    public static void EnsureLoaded()
    {
        if (isLoaded || Application.Current is null)
        {
            return;
        }

        // The styles reach the palette by DynamicResource, so a scheme change replaces these entries.
        // Anything in the application's resources is frozen, which is why views built in code get
        // brushes of their own from Brush and CardBrush. Inside a card, its own dictionary answers
        // first.
        windowResources = [];
        Fill(windowResources, WindowPalette);
        Fill(cardResources, CardPalette);
        Application.Current.Resources.MergedDictionaries.Add(windowResources);
        styles = new ResourceDictionary
        {
            Source = new Uri("/DevDeck.Shell;component/WindowsStyles.xaml", UriKind.Relative),
        };
        Application.Current.Resources.MergedDictionaries.Add(styles);
        isLoaded = true;
    }

    public static void Apply(DeckPalette cards, DeckPalette windows)
    {
        CardPalette = cards;
        WindowPalette = windows;
        if (!isLoaded || windowResources is null)
        {
            EnsureLoaded();
            return;
        }
        Fill(windowResources, windows);
        Fill(cardResources, cards);
        // Brushes handed to views built in code follow in place.
        liveBrushes.RemoveAll(entry => !entry.Brush.TryGetTarget(out _));
        foreach (var (key, forCard, reference) in liveBrushes)
        {
            if (reference.TryGetTarget(out var brush))
            {
                brush.Color = (forCard ? cards : windows)[key];
            }
        }
    }

    // A window's frame in the app mode: a dark or light title bar.
    public static void ApplyWindowChrome(nint handle)
    {
        NativeMethods.SetDarkMode(handle, !WindowPalette.IsLight);
    }

    public static Style Style(string key)
    {
        EnsureLoaded();
        return (Style)Application.Current.FindResource(key);
    }

    // A palette brush of the view's own that keeps following the app mode; anything else from the
    // resources as it is.
    public static Brush Brush(string key)
    {
        return Live(key, false);
    }

    // The same for a view on a card, which follows the taskbar's material.
    public static Brush CardBrush(string key)
    {
        return Live(key, true);
    }

    public static Brush Tone(string? tone)
    {
        return Brush(ToneKey(tone));
    }

    public static Brush CardTone(string? tone)
    {
        return CardBrush(ToneKey(tone));
    }

    public static Brush ToneFill(string? tone)
    {
        return new SolidColorBrush(WindowPalette.ToneTint(tone));
    }

    public static Brush CardToneFill(string? tone)
    {
        return new SolidColorBrush(CardPalette.ToneTint(tone));
    }

    // A Windows 11 primary button in a window: the accent shade the app mode uses, with text that
    // reads on it.
    public static (Brush Fill, Brush Text) AccentButton()
    {
        return (new SolidColorBrush(WindowPalette.AccentFill), new SolidColorBrush(WindowPalette.AccentText));
    }

    private static string ToneKey(string? tone)
    {
        return tone switch
        {
            "good" => "ToneGood",
            "attention" => "ToneAttention",
            "alert" => "ToneAlert",
            "personal" => "TonePersonal",
            _ => "TextPrimary",
        };
    }

    private static Brush Live(string key, bool forCard)
    {
        EnsureLoaded();
        if (!DeckPalette.Keys.Contains(key))
        {
            return (Brush)Application.Current.FindResource(key);
        }
        var brush = new SolidColorBrush((forCard ? CardPalette : WindowPalette)[key]);
        liveBrushes.Add((key, forCard, new WeakReference<SolidColorBrush>(brush)));
        if (liveBrushes.Count % 512 == 0)
        {
            liveBrushes.RemoveAll(entry => !entry.Brush.TryGetTarget(out _));
        }
        return brush;
    }

    private static void Fill(ResourceDictionary target, DeckPalette palette)
    {
        foreach (var key in DeckPalette.Keys)
        {
            target[key] = new SolidColorBrush(palette[key]);
        }
    }

    // The card's surface in the current scheme: a tint over Acrylic, or solid without transparency.
    public static Brush CardSurface()
    {
        return new SolidColorBrush(CardPalette.CardTint);
    }

    public static Border CardFrame(FrameworkElement content)
    {
        var frame = new Border
        {
            Background = CardSurface(),
            BorderBrush = CardBrush("ControlStroke"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(16, 14, 16, 14),
            Child = content,
        };
        // Styles inside the card find the card's palette before the windows' one.
        frame.Resources.MergedDictionaries.Add(cardResources);
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
