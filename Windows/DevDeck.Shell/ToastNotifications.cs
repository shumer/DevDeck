using System.Security.Cryptography;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Xml;
using Windows.UI.Notifications;

namespace DevDeck.Shell;

public interface IToastPlatform : IDisposable
{
    event Action<string>? Activated;
    void Show(string xml);
}

public sealed class NotificationController : IDisposable
{
    private readonly IToastPlatform platform;
    private readonly Func<string, string> artwork;
    private readonly Action<DeckCommand> command;
    private readonly HashSet<string> shown = new(StringComparer.Ordinal);
    private readonly Dictionary<string, DeckCommand> commands = new(StringComparer.Ordinal);

    public NotificationController(
        IToastPlatform platform,
        Func<string, string> artwork,
        Action<DeckCommand> command)
    {
        this.platform = platform;
        this.artwork = artwork;
        this.command = command;
        platform.Activated += OnActivated;
    }

    public void Show(IReadOnlyList<DeckNotification> notifications)
    {
        foreach (var notification in notifications)
        {
            if (!shown.Add(notification.Id))
            {
                continue;
            }

            commands[notification.Id] = notification.Command;
            platform.Show(ToastPayload.Build(notification, artwork(notification.Source)));
        }
    }

    public void Dispose()
    {
        platform.Activated -= OnActivated;
        platform.Dispose();
    }

    private void OnActivated(string id)
    {
        if (commands.TryGetValue(id, out var notificationCommand))
        {
            command(notificationCommand);
        }
    }
}

public static class ToastPayload
{
    public static string Build(DeckNotification notification, string artworkUri)
    {
        var output = new StringBuilder();
        var settings = new XmlWriterSettings
        {
            Indent = false,
            OmitXmlDeclaration = true,
        };
        using (var writer = XmlWriter.Create(output, settings))
        {
            writer.WriteStartElement("toast");
            writer.WriteAttributeString("launch", notification.Id);
            writer.WriteStartElement("visual");
            writer.WriteStartElement("binding");
            writer.WriteAttributeString("template", "ToastGeneric");
            writer.WriteStartElement("image");
            writer.WriteAttributeString("placement", "appLogoOverride");
            writer.WriteAttributeString("hint-crop", "circle");
            writer.WriteAttributeString("src", artworkUri);
            writer.WriteEndElement();
            WriteText(writer, notification.Title);
            WriteText(writer, notification.Subtitle);
            WriteText(writer, notification.Body);
            writer.WriteEndElement();
            writer.WriteEndElement();
            if (notification.IsQuiet)
            {
                writer.WriteStartElement("audio");
                writer.WriteAttributeString("silent", "true");
                writer.WriteEndElement();
            }
            writer.WriteEndElement();
        }
        return output.ToString();
    }

    private static void WriteText(XmlWriter writer, string value)
    {
        writer.WriteElementString("text", value);
    }
}

public sealed class WindowsToastPlatform : IToastPlatform
{
    private readonly Dictionary<ToastNotification, string> active = [];
    private readonly ToastNotifier notifier;

    public event Action<string>? Activated;

    public WindowsToastPlatform()
    {
        ToastShortcutRegistration.Ensure();
        notifier = ToastNotificationManager.CreateToastNotifier(ToastShortcutRegistration.AppId);
    }

    public void Show(string xml)
    {
        var document = new Windows.Data.Xml.Dom.XmlDocument();
        document.LoadXml(xml);
        var notification = new ToastNotification(document);
        var id = document.DocumentElement.GetAttribute("launch");
        notification.Activated += OnActivated;
        notification.Dismissed += OnDismissed;
        notification.Failed += OnFailed;
        lock (active)
        {
            active[notification] = id;
        }
        notifier.Show(notification);
    }

    public void Dispose()
    {
        lock (active)
        {
            foreach (var notification in active.Keys)
            {
                notification.Activated -= OnActivated;
                notification.Dismissed -= OnDismissed;
                notification.Failed -= OnFailed;
            }
            active.Clear();
        }
    }

    private void OnActivated(ToastNotification sender, object arguments)
    {
        if (Take(sender, out var id))
        {
            Activated?.Invoke(id);
        }
    }

    private void OnDismissed(ToastNotification sender, ToastDismissedEventArgs arguments)
    {
        _ = Take(sender, out _);
    }

    private void OnFailed(ToastNotification sender, ToastFailedEventArgs arguments)
    {
        _ = Take(sender, out _);
    }

    private bool Take(ToastNotification notification, out string id)
    {
        lock (active)
        {
            if (!active.Remove(notification, out id!))
            {
                return false;
            }
        }
        notification.Activated -= OnActivated;
        notification.Dismissed -= OnDismissed;
        notification.Failed -= OnFailed;
        return true;
    }
}

public static class NotificationArtwork
{
    private const int Size = 128;

    public static string FileUri(string source)
    {
        if (!BrandMarks.Names.Contains(source, StringComparer.Ordinal))
        {
            throw new InvalidDataException($"Unknown notification source: {source}.");
        }

        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "DevDeck",
            "NotificationAssets");
        Directory.CreateDirectory(directory);
        var name = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(source)))[..16];
        var path = Path.Combine(directory, $"{name}.png");
        if (!File.Exists(path))
        {
            Render(source, path);
        }
        return new Uri(path).AbsoluteUri;
    }

    private static void Render(string source, string path)
    {
        var mark = BrandMarks.Create(source, 76.8);
        mark.HorizontalAlignment = HorizontalAlignment.Center;
        mark.VerticalAlignment = VerticalAlignment.Center;
        var tile = new Border
        {
            Width = Size,
            Height = Size,
            CornerRadius = new CornerRadius(28),
            Background = new SolidColorBrush(Color.FromRgb(26, 30, 36)),
            Child = mark,
        };
        tile.Measure(new Size(Size, Size));
        tile.Arrange(new Rect(0, 0, Size, Size));
        tile.UpdateLayout();

        var bitmap = new RenderTargetBitmap(Size, Size, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(tile);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
    }
}
