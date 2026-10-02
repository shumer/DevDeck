using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed class PhonePanel : Border
{
    internal PhoneLinkResult Link { get; }
    private readonly Action<string> copy;
    private readonly Action dismiss;
    internal PhonePanel(Uri address) : this(new(address,PhoneLinkIssue.None),Clipboard.SetText,() => { },() => { }) { }
    internal PhonePanel(PhoneLinkResult link, Action<string> copy, Action dismiss, Action settings)
    {
        Link = link; this.copy = copy; this.dismiss = dismiss;
        Background = CardTheme.PanelBackground; BorderBrush = CardTheme.PanelBorder; BorderThickness = new(1); CornerRadius = new(12); Padding = new(18);
        var panel = new StackPanel { Width = 270 };
        panel.Children.Add(new TextBlock { Text = Text.L("card.phone.title"), Foreground = CardTheme.Ink, FontWeight = FontWeights.SemiBold, FontSize = 16 });
        if (link.Address is not { } address) {
            panel.Children.Add(new TextBlock { Text = Text.L("windows.phone."+link.Issue), Foreground = CardTheme.Ink, TextWrapping = TextWrapping.Wrap, FontSize = 13, Margin = new(0,14,0,12) });
            if (link.Issue is PhoneLinkIssue.RoutedHost or PhoneLinkIssue.NoSite or PhoneLinkIssue.InvalidURL) {
                panel.Children.Add(new TextBlock { Text = Text.L("windows.phoneURLHint"), Foreground = CardTheme.Secondary, TextWrapping = TextWrapping.Wrap, FontSize = 11, Margin = new(0,0,0,12) });
                panel.Children.Add(CardTheme.Button(Text.L("menu.settings"), () => { dismiss(); settings(); return Task.CompletedTask; }));
            }
            panel.Children.Add(CardTheme.Button(Text.L("windows.phoneClose"), () => { dismiss(); return Task.CompletedTask; }));
            Child = panel; return;
        }
        var modules = PhoneCode.Encode(address);
        var scale = Math.Max(1, Math.Min(6, 240 / modules.Length));
        var width = modules.Length * scale;
        var pixels = new byte[width * width];
        for (var y = 0; y < width; y++) for (var x = 0; x < width; x++) pixels[y * width + x] = modules[y / scale][x / scale] ? (byte)0 : (byte)255;
        var bitmap = BitmapSource.Create(width, width, 96, 96, PixelFormats.Gray8, null, pixels, width); bitmap.Freeze();
        var image = new Image { Source = bitmap, Width = width, Height = width, Margin = new(0, 16, 0, 12), HorizontalAlignment = HorizontalAlignment.Center };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.NearestNeighbor);
        panel.Children.Add(image);
        panel.Children.Add(new TextBox { Text = address.AbsoluteUri, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, FontFamily = new("Consolas"),
            FontSize = 11, Foreground = CardTheme.Ink, Background = Brushes.Transparent, BorderThickness = new(0), MaxHeight = 64 });
        panel.Children.Add(new TextBlock { Text = Text.L("windows.phoneNote"), Foreground = CardTheme.Secondary, TextWrapping = TextWrapping.Wrap, FontSize = 11, Margin = new(0, 10, 0, 14) });
        panel.Children.Add(CardTheme.Button(Text.L("windows.copyLink"), () => { CopyLink(); return Task.CompletedTask; }));
        Child = panel;
    }
    internal void CopyLink()
    {
        if (Link.Address is not { } address) return;
        copy(address.AbsoluteUri); dismiss();
    }
}
