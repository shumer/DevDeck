using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Actual native view inspection; fixture settings only, with no worker or real action.
internal static class TrayAttentionActionsTests
{
    internal static Task RunRedAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        using var fixture = new Fixture(application);
        AttentionWindow? window = null;
        try {
            Text.Use("en");
            var inbox = Inbox(url: false);
            var none = Item("status-only", new("none"), enabled: true);
            window = new AttentionWindow(fixture.Controller, [inbox, none]);
            var buttons = Descendants<Button>(window).ToArray();
            var primary = buttons.Single(button => button.Content is StackPanel content
                && Descendants<TextBlock>(content).Any(text => text.Text == none.Title));
            var read = buttons.SingleOrDefault(button => button.Content as string == Text.L("menu.markRead", inbox.Title));
            var readPresent = read is { IsEnabled: true };
            var noneDisabled = !primary.IsEnabled;
            if (!readPresent || !noneDisabled)
                throw new IOException("Actual AttentionWindow parity red: explicitUrlLessRead=" + readPresent
                    + ", actionNoneDisabled=" + noneDisabled + "; no real action was invoked.");
            checks.Add(new { name = "attention.fullList.actualReadAndStatusOnly", explicitUrlLessRead = true,
                actionNoneDisabled = true, noRealActions = true });
            return Task.CompletedTask;
        } finally { window?.Close(); Text.Use(language); }
    }

    private static AttentionItem Inbox(bool url = true) => Item("owned.inbox", url
        ? new("open", Url: "https://example.test/review/41", Service: "github", AccountID: "owned-account")
        : new("none"), enabled: url) with {
        InboxRead = new("github.inbox", "owned-account", "0041", "https://api.example.test")
    };

    private static AttentionItem Item(string id, AttentionAction action, bool enabled = true, bool dismissible = false) =>
        new(id, id, "waiting", "github", "Review & deployment " + id,
            "Owned work account · example/shop · full diagnostic", 1_780_000_000, action, enabled, dismissible);

    private static IEnumerable<T> Descendants<T>(DependencyObject source) where T : DependencyObject
    {
        foreach (var child in LogicalTreeHelper.GetChildren(source).OfType<DependencyObject>()) {
            if (child is T item) yield return item;
            foreach (var nested in Descendants<T>(child)) yield return nested;
        }
    }

    private sealed class Fixture : IDisposable
    {
        private readonly string path = Path.Combine(Path.GetTempPath(), "devdeck-attention-actions-" + Guid.NewGuid().ToString("N") + ".json");
        private readonly byte[] persisted;
        internal DeckController Controller { get; }
        internal Fixture(Application application)
        {
            var store = new SettingsStore(path);
            store.Save(DeckSettings.Empty with { Workers = [], Cards = [], Notifications = false });
            Controller = new DeckController(application, store, live: false);
            // Constructor discovery may canonically add default-off built-in cards. The
            // contract here is that opening/using the synthetic view performs no save.
            persisted = File.ReadAllBytes(path);
        }
        public void Dispose()
        {
            try {
                if (Controller.LocalPollEnabled || Controller.SharedPollEnabled
                    || !File.ReadAllBytes(path).SequenceEqual(persisted))
                    throw new IOException("Attention native fixture started polling or changed its persisted settings.");
            } finally {
                Controller.CloseViews();
                foreach (var file in new[] { path, path + ".bak" }) if (File.Exists(file)) File.Delete(file);
            }
        }
    }
}
