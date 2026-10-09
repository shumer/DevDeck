using Microsoft.Win32;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace DevDeck.Shell;

public static class WindowsTheme
{
    private const string PersonalizeKey = @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private static bool isLoaded;

    public static void EnsureLoaded()
    {
        if (isLoaded || Application.Current is null)
        {
            return;
        }

        Application.Current.Resources.MergedDictionaries.Add(new ResourceDictionary
        {
            Source = new Uri("/DevDeck.Shell;component/WindowsStyles.xaml", UriKind.Relative),
        });
        isLoaded = true;
    }

    public static Style Style(string key)
    {
        EnsureLoaded();
        return (Style)Application.Current.FindResource(key);
    }

    public static Brush Brush(string key)
    {
        EnsureLoaded();
        return (Brush)Application.Current.FindResource(key);
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

    public static Brush CardBackground(bool transparencyEnabled)
    {
        return new SolidColorBrush(
            transparencyEnabled
                ? Color.FromArgb(168, 40, 40, 44)
                : Color.FromRgb(43, 43, 47));
    }

    public static bool IsTransparencyEnabled()
    {
        return Registry.GetValue(PersonalizeKey, "EnableTransparency", 1) is not int value || value != 0;
    }

    public static Border CardFrame(FrameworkElement content)
    {
        var frame = new Border
        {
            Background = CardBackground(IsTransparencyEnabled()),
            BorderBrush = Brush("ControlStroke"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(14, 12, 14, 14),
            Child = content,
        };
        RenderOptions.SetClearTypeHint(frame, ClearTypeHint.Enabled);
        return frame;
    }

    public static FontFamily Sans => (FontFamily)Application.Current.FindResource("DevDeckSans");
    public static FontFamily Mono => (FontFamily)Application.Current.FindResource("DevDeckMono");
}
