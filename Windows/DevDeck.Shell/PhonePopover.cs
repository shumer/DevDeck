using QRCoder;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Button = System.Windows.Controls.Button;

namespace DevDeck.Shell;

public static class PhonePopover
{
    public static byte[] QrPng(string address)
    {
        using var generator = new QRCodeGenerator();
        using var data = generator.CreateQrCode(address, QRCodeGenerator.ECCLevel.Q);
        using var code = new PngByteQRCode(data);
        return code.GetGraphic(8);
    }

    public static void Attach(Button button, string address, string title, string note)
    {
        var popup = Create(button, address, title, note);
        button.Tag = popup;
        button.Click += (_, _) => popup.IsOpen = !popup.IsOpen;
    }

    public static Popup Create(FrameworkElement target, string address, string title, string note)
    {
        var image = new Image
        {
            Source = Bitmap(QrPng(address)),
            Width = 192,
            Height = 192,
            Stretch = Stretch.Uniform,
            Margin = new Thickness(0, 12, 0, 10),
        };
        var content = new StackPanel { Width = 232 };
        content.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 16,
            FontWeight = FontWeights.SemiBold,
            Foreground = WindowsTheme.Brush("TextPrimary"),
        });
        content.Children.Add(image);
        content.Children.Add(new TextBlock
        {
            Text = note,
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            Foreground = WindowsTheme.Brush("TextSecondary"),
            Margin = new Thickness(0, 0, 0, 8),
        });
        content.Children.Add(new TextBlock
        {
            Text = address,
            FontFamily = WindowsTheme.Mono,
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap,
            Foreground = WindowsTheme.Brush("TextTertiary"),
        });
        var frame = new Border
        {
            Child = content,
            Padding = new Thickness(16),
            CornerRadius = new CornerRadius(8),
            Background = WindowsTheme.CardBackground(false),
            BorderBrush = WindowsTheme.Brush("ControlStroke"),
            BorderThickness = new Thickness(1),
            Effect = new System.Windows.Media.Effects.DropShadowEffect
            {
                BlurRadius = 20,
                Opacity = 0.45,
                ShadowDepth = 6,
                Color = Colors.Black,
            },
        };
        AutomationProperties.SetName(frame, title);
        return new Popup
        {
            Child = frame,
            PlacementTarget = target,
            Placement = PlacementMode.Bottom,
            HorizontalOffset = -208,
            VerticalOffset = 8,
            AllowsTransparency = true,
            StaysOpen = false,
        };
    }

    private static BitmapImage Bitmap(byte[] bytes)
    {
        using var stream = new MemoryStream(bytes);
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.StreamSource = stream;
        image.EndInit();
        image.Freeze();
        return image;
    }
}
