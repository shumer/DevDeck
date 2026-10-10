using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace DevDeck.Shell;

public sealed record DeckStatusModel(int? Tier, string Tooltip, string AccessibilityValue)
{
    public static DeckStatusModel Parse(JsonElement value)
    {
        int? tier = null;
        if (DeckEvent.TryProperty(value, "tier", out var tierValue) && tierValue.ValueKind == JsonValueKind.Number)
        {
            tier = tierValue.GetInt32();
        }
        return new(
            tier,
            DeckEvent.RequiredString(value, "tooltip"),
            DeckEvent.RequiredString(value, "accessibilityValue"));
    }
}

public sealed class TrayController : IDisposable
{
    private const string PersonalizeKey = @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private readonly System.Windows.Forms.NotifyIcon tray = new();
    private readonly MenuPresenter menu;
    private DeckStatusModel status = new(null, "DevDeck", "DevDeck");
    private System.Drawing.Icon? icon;

    public TrayController(Action<DeckCommand> command)
    {
        menu = new MenuPresenter(command);
        tray.Visible = true;
        tray.MouseUp += OnMouseUp;
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        ApplyStatus();
    }

    public MenuPresenter Menu => menu;
    public DeckStatusModel Status => status;

    public void UpdateStatus(JsonElement value)
    {
        status = DeckStatusModel.Parse(value);
        ApplyStatus();
    }

    public void UpdateMenu(JsonElement value)
    {
        menu.Update(value);
        AutomationProperties.SetName(menu.View, status.AccessibilityValue);
    }

    public void OpenMenu()
    {
        menu.Open();
    }

    public void Dispose()
    {
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        tray.MouseUp -= OnMouseUp;
        tray.Visible = false;
        tray.Dispose();
        icon?.Dispose();
    }

    private void OnMouseUp(object? sender, System.Windows.Forms.MouseEventArgs eventArguments)
    {
        if (eventArguments.Button is System.Windows.Forms.MouseButtons.Left or System.Windows.Forms.MouseButtons.Right)
        {
            menu.Open();
        }
    }

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs eventArguments)
    {
        if (eventArguments.Category is UserPreferenceCategory.Color or UserPreferenceCategory.General)
        {
            Application.Current.Dispatcher.BeginInvoke(ApplyStatus);
        }
    }

    private void ApplyStatus()
    {
        var replacement = TrayIconFactory.Create(status.Tier, IsLightTaskbar());
        tray.Icon = replacement;
        icon?.Dispose();
        icon = replacement;
        tray.Text = status.Tooltip.Length <= 127 ? status.Tooltip : status.Tooltip[..127];
        AutomationProperties.SetName(menu.View, status.AccessibilityValue);
    }

    private static bool IsLightTaskbar()
    {
        return Registry.GetValue(PersonalizeKey, "SystemUsesLightTheme", 0) is int value && value != 0;
    }
}

public static class TrayIconFactory
{
    public static System.Drawing.Icon Create(int? tier, bool lightTaskbar)
    {
        var images = new[] { Render(16, tier, lightTaskbar), Render(32, tier, lightTaskbar) };
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream, System.Text.Encoding.UTF8, true);
        writer.Write((ushort)0);
        writer.Write((ushort)1);
        writer.Write((ushort)images.Length);
        var offset = 6 + images.Length * 16;
        foreach (var image in images)
        {
            writer.Write((byte)(image.Size == 256 ? 0 : image.Size));
            writer.Write((byte)(image.Size == 256 ? 0 : image.Size));
            writer.Write((byte)0);
            writer.Write((byte)0);
            writer.Write((ushort)1);
            writer.Write((ushort)32);
            writer.Write(image.Bytes.Length);
            writer.Write(offset);
            offset += image.Bytes.Length;
        }
        foreach (var image in images)
        {
            writer.Write(image.Bytes);
        }
        writer.Flush();
        stream.Position = 0;
        using var loaded = new System.Drawing.Icon(stream);
        return (System.Drawing.Icon)loaded.Clone();
    }

    public static BitmapSource Preview(int size, int? tier, bool lightTaskbar)
    {
        return RenderBitmap(size, tier, lightTaskbar);
    }

    private static (int Size, byte[] Bytes) Render(int size, int? tier, bool lightTaskbar)
    {
        var bitmap = RenderBitmap(size, tier, lightTaskbar);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return (size, stream.ToArray());
    }

    private static RenderTargetBitmap RenderBitmap(int size, int? tier, bool lightTaskbar)
    {
        WindowsTheme.EnsureLoaded();
        var root = new System.Windows.Controls.Grid
        {
            Width = size,
            Height = size,
            Background = Brushes.Transparent,
        };
        var foreground = new SolidColorBrush(lightTaskbar ? Color.FromRgb(34, 34, 34) : Color.FromRgb(246, 246, 246));
        var mark = BrandMarks.Create("project", size * 0.72, foreground);
        mark.HorizontalAlignment = HorizontalAlignment.Left;
        mark.VerticalAlignment = VerticalAlignment.Top;
        root.Children.Add(mark);
        if (tier is 0 or 1 or 2)
        {
            var badge = new System.Windows.Shapes.Ellipse
            {
                Width = size * 0.34,
                Height = size * 0.34,
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Bottom,
                Fill = tier switch
                {
                    0 => WindowsTheme.Brush("ToneAlert"),
                    1 => foreground,
                    _ => Brushes.Transparent,
                },
                Stroke = tier == 2 ? foreground : null,
                StrokeThickness = tier == 2 ? Math.Max(1, size / 16.0) : 0,
            };
            root.Children.Add(badge);
        }
        root.Measure(new Size(size, size));
        root.Arrange(new Rect(0, 0, size, size));
        var result = new RenderTargetBitmap(size, size, 96, 96, PixelFormats.Pbgra32);
        result.Render(root);
        result.Freeze();
        return result;
    }
}
