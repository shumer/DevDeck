using Microsoft.Win32;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace DevDeck.Shell;

public sealed class SettingsWindowRegistry : IDisposable
{
    private readonly SettingsClient client;
    private SettingsWindow? window;
    private JsonElement? update;
    private JsonElement? menu;

    public SettingsWindowRegistry(SettingsClient client)
    {
        this.client = client;
        client.Changed += Refresh;
        client.AnswerReceived += Receive;
    }

    public bool IsOpen => window is not null;

    public void Open(JsonElement effect)
    {
        var route = SettingsRoute.FromEffect(effect);
        if (window is null)
        {
            window = new SettingsWindow(client);
            window.Closed += (_, _) => window = null;
            window.Show();
        }
        window.Apply(client.Words, client.List, client.Cards, client.Preferences, update, menu);
        window.Navigate(route);
        window.Activate();
    }

    public void Update(JsonElement value)
    {
        update = value.Clone();
        Refresh();
    }

    public void UpdateMenu(JsonElement value)
    {
        menu = value.Clone();
        Refresh();
    }

    public void RefreshList()
    {
        if (window is not null)
        {
            client.RefreshList();
        }
    }

    public void Dispose()
    {
        client.Changed -= Refresh;
        client.AnswerReceived -= Receive;
        window?.Close();
    }

    private void Refresh()
    {
        window?.Apply(client.Words, client.List, client.Cards, client.Preferences, update, menu);
    }

    private void Receive(JsonElement answer)
    {
        window?.Receive(answer);
    }
}

public sealed record SettingsRoute(string Page, string? Item)
{
    public static SettingsRoute FromEffect(JsonElement effect)
    {
        var page = JsonModel.String(effect, "page");
        var item = JsonModel.String(effect, "item");
        var card = JsonModel.String(effect, "card");
        if (page is not null)
        {
            return new SettingsRoute(page, item);
        }
        if (card is not null)
        {
            var parts = card.Split('.');
            if (parts.Length > 1)
            {
                var kind = parts[0] == "project" ? "project" : parts[0];
                var id = parts[^1];
                return new SettingsRoute(kind, id);
            }
        }
        return new SettingsRoute("general", null);
    }
}

public sealed class SettingsWindow : Window
{
    public const double FormLabelWidth = 150;

    private readonly SettingsClient client;
    private readonly WindowsLoginItem loginItem;
    private readonly StackPanel navigation = new();
    private readonly ContentControl content = new();
    private readonly TextBox search = new();
    private readonly Button addButton = new();
    private readonly Button removeButton = new();
    private readonly Dictionary<string, JsonObject> records = [];
    private readonly HashSet<string> loadingRecords = [];
    private readonly Dictionary<string, JsonObject> checks = [];
    private readonly Dictionary<string, (string State, string Detail)> tokenStatuses = [];
    private readonly Dictionary<string, string> folderNotes = [];
    private readonly Dictionary<string, string> linkNotes = [];
    private readonly HashSet<string> expandedAdvanced = [];
    private SettingsWords words = new();
    private JsonNode? list;
    private JsonArray? cards;
    private JsonObject? preferences;
    private JsonElement? update;
    private JsonElement? menu;
    private ContextMenu? addMenu;
    private SettingsRoute route = new("general", null);
    private bool applying;

    public SettingsWindow(SettingsClient client, WindowsLoginItem? loginItem = null)
    {
        this.client = client;
        this.loginItem = loginItem ?? WindowsLoginItem.Current();
        Width = 1080;
        Height = 680;
        MinWidth = 860;
        MinHeight = 560;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = new SolidColorBrush(Color.FromRgb(32, 32, 32));
        Foreground = WindowsTheme.Brush("TextPrimary");
        FontFamily = WindowsTheme.Sans;
        FontSize = 14;
        Content = BuildShell();
        SourceInitialized += (_, _) => NativeMethods.ApplyLogWindowStyles(new WindowInteropHelper(this).Handle);
    }

    public string CurrentPage => route.Page;

    public void Apply(
        SettingsWords newWords,
        JsonNode? newList,
        JsonArray? newCards,
        JsonObject? newPreferences,
        JsonElement? newUpdate,
        JsonElement? newMenu = null)
    {
        words = newWords;
        list = newList;
        cards = newCards;
        preferences = newPreferences;
        update = newUpdate;
        menu = newMenu;
        Title = words.Get("settings.window.title");
        search.Tag = words.Get("settings.search");
        addButton.Content = words.Get("button.add");
        addButton.ToolTip = words.Get("settings.sidebar.add");
        removeButton.Content = DeckIcons.Create("remove", 13);
        removeButton.ToolTip = words.Get("settings.sidebar.remove");
        RebuildNavigation();
        Render();
    }

    public void Navigate(SettingsRoute value)
    {
        route = value;
        if (value.Item is not null && IsRecordPage(value.Page))
        {
            LoadRecord(value.Page, value.Item);
        }
        Render();
    }

    public void Receive(JsonElement answer)
    {
        foreach (var pair in new[]
        {
            (Answer: "githubAccount", Page: "github"),
            (Answer: "gitlabAccount", Page: "gitlab"),
            (Answer: "localProject", Page: "project"),
            (Answer: "arcProject", Page: "arc"),
            (Answer: "ddevProject", Page: "ddev"),
        })
        {
            if (SettingsJson.CaseValue(answer, pair.Answer) is not JsonObject record)
            {
                continue;
            }
            var id = SettingsJson.String(record, "id");
            records[RecordKey(pair.Page, id)] = record;
            Render();
            return;
        }
    }

    private FrameworkElement BuildShell()
    {
        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(240) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var left = new Grid { Margin = new Thickness(12, 10, 8, 8) };
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        search.Height = 32;
        search.Margin = new Thickness(0, 0, 4, 10);
        search.Style = WindowsTheme.Style("PromptTextBox");
        search.TextChanged += (_, _) =>
        {
            RebuildNavigation();
        };
        AutomationProperties.SetAutomationId(search, "SettingsSearch");
        left.Children.Add(search);

        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Content = navigation,
        };
        Grid.SetRow(scroll, 1);
        left.Children.Add(scroll);

        var footer = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
        ConfigureButton(addButton, "SettingsAdd");
        addButton.Click += (_, _) => OpenAddMenu();
        addButton.Margin = new Thickness(0, 0, 4, 0);
        ConfigureButton(removeButton, "SettingsRemove");
        removeButton.Click += (_, _) => RemoveSelected();
        footer.Children.Add(addButton);
        footer.Children.Add(removeButton);
        Grid.SetRow(footer, 2);
        left.Children.Add(footer);
        root.Children.Add(left);

        content.Margin = new Thickness(24, 20, 40, 24);
        var contentScroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = content,
        };
        Grid.SetColumn(contentScroll, 1);
        root.Children.Add(contentScroll);
        return root;
    }

    private void RebuildNavigation()
    {
        navigation.Children.Clear();
        AddNavigation("general", "settings.general.title", "settings");
        AddNavigation("deck", "settings.deck.title", "deck");
        AddNavigation("cards", "settings.cards.title", "grid");
        AddNavigation("notifications", "settings.notifications.title", "notification");
        AddGroup("settings.sidebar.accounts");
        AddItems("accounts");
        AddGroup("settings.sidebar.projects");
        AddItems("projects");
        removeButton.IsEnabled = route.Item is not null && IsRecordPage(route.Page);
    }

    private void AddNavigation(string page, string key, string icon)
    {
        var title = words.Get(key);
        if (!Matches(title))
        {
            return;
        }
        var button = NavigationButton(title, icon, null, route.Page == page && route.Item is null);
        button.Click += (_, _) => Navigate(new SettingsRoute(page, null));
        navigation.Children.Add(button);
    }

    private void AddGroup(string key)
    {
        navigation.Children.Add(new TextBlock
        {
            Text = words.Get(key),
            Foreground = WindowsTheme.Brush("TextTertiary"),
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(12, 14, 0, 4),
        });
    }

    private void AddItems(string group)
    {
        var root = SettingsJson.Object(list);
        if (root[group] is not JsonArray items)
        {
            return;
        }
        foreach (var node in items.OfType<JsonObject>())
        {
            var title = SettingsJson.String(node, "title");
            if (!Matches(title))
            {
                continue;
            }
            var page = SettingsJson.String(node, "kind");
            var id = SettingsJson.String(node, "id");
            var button = NavigationButton(
                title,
                SettingsJson.String(node, "mark"),
                SettingsJson.String(node, "tone"),
                route.Page == page && route.Item == id);
            button.ToolTip = SettingsJson.String(node, "detail");
            button.Opacity = SettingsJson.Bool(node, "isDimmed") ? 0.55 : 1;
            button.Click += (_, _) => Navigate(new SettingsRoute(page, id));
            navigation.Children.Add(button);
        }
    }

    private Button NavigationButton(string title, string icon, string? tone, bool selected)
    {
        var panel = new Grid();
        panel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(28) });
        panel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        panel.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var glyph = MarkIcon(icon, 15);
        panel.Children.Add(glyph);
        var label = new TextBlock
        {
            Text = title,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(label, 1);
        panel.Children.Add(label);
        if (!string.IsNullOrEmpty(tone))
        {
            var dot = new Border
            {
                Width = 7,
                Height = 7,
                CornerRadius = new CornerRadius(4),
                Background = WindowsTheme.Tone(tone),
                Margin = new Thickness(8, 0, 4, 0),
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(dot, 2);
            panel.Children.Add(dot);
        }
        var button = new Button
        {
            Content = panel,
            Height = 36,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Style = WindowsTheme.Style("RowButton"),
            Background = selected ? WindowsTheme.Brush("ControlHover") : Brushes.Transparent,
            Margin = new Thickness(0, 1, 4, 1),
        };
        return button;
    }

    private bool Matches(string value)
    {
        return search.Text.Length == 0 || value.Contains(search.Text, StringComparison.CurrentCultureIgnoreCase);
    }

    private void Render()
    {
        if (words.Count == 0)
        {
            content.Content = null;
            return;
        }
        applying = true;
        content.Content = route.Page switch
        {
            "general" => GeneralPage(),
            "deck" => DeckPage(),
            "cards" => CardsPage(),
            "notifications" => NotificationsPage(),
            "github" or "gitlab" or "project" or "arc" or "ddev" => RecordPage(),
            _ => EmptyPage(),
        };
        applying = false;
    }

    private FrameworkElement GeneralPage()
    {
        var page = PageHeader("settings.general.title", null, "settings");
        var start = LoginItemToggle();

        var language = new ComboBox { Width = 150 };
        language.Style = WindowsTheme.Style("SettingsComboBox");
        foreach (var value in new[] { "system", "en", "de", "es", "fr", "it", "ru" })
        {
            language.Items.Add(new ComboBoxItem { Content = value == "system" ? words.Get("settings.language.system") : value, Tag = value });
        }
        language.SelectedValuePath = "Tag";
        language.SelectedValue = PreferenceString("language");
        language.SelectionChanged += (_, _) =>
        {
            if (!applying && language.SelectedValue is string value)
            {
                SetPreference("language", value);
            }
        };
        page.Children.Add(Card(
            Row("settings.general.startAtLogin", null, start),
            Row("settings.language", "settings.language.detail", language)));
        page.Children.Add(GroupTitle("settings.general.updates"));
        page.Children.Add(Card(
            Row("settings.general.checkAutomatically", "settings.general.checkAutomatically.detail", TogglePreference("checksForUpdates")),
            UpdateRow()));
        page.Children.Add(Footnote(words.Get("settings.general.runningFrom", AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar))));
        return page;
    }

    private CheckBox LoginItemToggle()
    {
        var lastValue = loginItem.IsEnabled();
        var restoring = false;
        CheckBox? toggle = null;
        toggle = Toggle(lastValue, true, selected =>
        {
            if (restoring)
            {
                return;
            }
            if (loginItem.SetEnabled(selected))
            {
                lastValue = selected;
                return;
            }
            restoring = true;
            toggle!.IsChecked = lastValue;
            restoring = false;
        });
        AutomationProperties.SetAutomationId(toggle, "StartAtLogin");
        return toggle;
    }

    private FrameworkElement DeckPage()
    {
        var page = PageHeader("settings.deck.title", "settings.deck.subtitle", "deck");
        page.Children.Add(GroupTitle("settings.deck.position"));
        var placement = new ComboBox { Width = 220 };
        placement.Style = WindowsTheme.Style("SettingsComboBox");
        placement.Items.Add(new ComboBoxItem { Content = words.Get("settings.deck.place.desktop"), Tag = "desktop" });
        placement.Items.Add(new ComboBoxItem { Content = words.Get("settings.deck.place.floating"), Tag = "floating" });
        placement.SelectedValuePath = "Tag";
        placement.SelectedValue = PreferenceString("displayMode");
        placement.SelectionChanged += (_, _) =>
        {
            if (!applying && placement.SelectedValue is string value)
            {
                SetPreference("displayMode", value);
            }
        };
        page.Children.Add(Card(
            Row("settings.deck.placeCards", null, placement),
            Row("settings.deck.lock", "settings.deck.lock.detail", TogglePreference("isLocked")),
            Row("settings.deck.closeGaps", "settings.deck.closeGaps.detail", TogglePreference("packsColumns"))));
        page.Children.Add(GroupTitle("settings.deck.shortcut"));
        var shortcut = new TextBox
        {
            Text = PreferenceString("summonShortcutWindows") is { Length: > 0 } savedShortcut
                ? savedShortcut
                : SummonShortcut.DefaultText,
            Width = 170,
            Style = WindowsTheme.Style("PromptTextBox"),
        };
        shortcut.PreviewKeyDown += (_, eventArgs) => CaptureShortcut(shortcut, eventArgs);
        var reset = ActionButton("settings.deck.default", () =>
        {
            shortcut.Text = SummonShortcut.DefaultText;
            SetPreference("summonShortcutWindows", null);
        });
        var shortcutControls = new StackPanel { Orientation = Orientation.Horizontal };
        shortcutControls.Children.Add(shortcut);
        reset.Margin = new Thickness(8, 0, 0, 0);
        shortcutControls.Children.Add(reset);
        page.Children.Add(Card(
            Row("settings.deck.summon", "settings.deck.summon.detail", TogglePreference("summonEnabled")),
            Row("settings.deck.shortcut", null, shortcutControls),
            Row("settings.deck.dim", null, TogglePreference("summonDims"))));
        page.Children.Add(Footnote(words.Get("settings.deck.footnote")));
        return page;
    }

    private FrameworkElement CardsPage()
    {
        var page = PageHeader("settings.cards.title", "settings.cards.subtitle", "grid");
        var cardRows = cards?
            .OfType<JsonObject>()
            .Select(card => ModelRow(
                SettingsJson.String(card, "title"),
                SettingsJson.String(card, "detail"),
                Toggle(
                    SettingsJson.Bool(card, "isEnabled"),
                    true,
                    isEnabled => client.Request(SettingsJson.SetCard(SettingsJson.String(card, "id"), isEnabled)))))
            .ToArray() ?? [];
        if (cardRows.Length > 0)
        {
            page.Children.Add(GroupTitle("settings.cards.onDeck"));
            page.Children.Add(Card(cardRows));
        }
        page.Children.Add(GroupTitle("settings.cards.fetching"));
        var interval = new ComboBox { Width = 150 };
        interval.Style = WindowsTheme.Style("SettingsComboBox");
        foreach (var seconds in new[] { 60, 120, 300, 600 })
        {
            interval.Items.Add(new ComboBoxItem
            {
                Content = words.Get($"settings.cards.interval.{seconds / 60}"),
                Tag = seconds,
            });
        }
        interval.SelectedValuePath = "Tag";
        interval.SelectedValue = (int)PreferenceDouble("refreshIntervalSeconds");
        interval.SelectionChanged += (_, _) =>
        {
            if (!applying && interval.SelectedValue is int value)
            {
                SetPreference("refreshIntervalSeconds", value);
            }
        };
        var repositories = new TextBox
        {
            Text = string.Join(", ", PreferenceArray("actionsRepositories")),
            Style = WindowsTheme.Style("PromptTextBox"),
            MinWidth = 280,
        };
        if (route.Item == "actionsRepositories")
        {
            repositories.Loaded += (_, _) =>
            {
                repositories.Focus();
                repositories.SelectAll();
            };
        }
        repositories.LostKeyboardFocus += (_, _) =>
            SetPreference(
                "actionsRepositories",
                new JsonArray(
                    repositories.Text
                        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                        .Select(value => (JsonNode?)JsonValue.Create(value))
                        .ToArray()));
        page.Children.Add(Card(
            Row("settings.cards.refreshEvery", null, interval),
            FormRow(words.Get("settings.cards.actionsRepositories"), "", repositories)));
        page.Children.Add(Footnote(words.Get("settings.cards.actions.footnote")));
        return page;
    }

    private FrameworkElement NotificationsPage()
    {
        EnsureNotificationRecords();
        var page = PageHeader("settings.notifications.title", "settings.notifications.subtitle", "notification");
        page.Children.Add(Card(
            Row("settings.notifications.allow", "settings.notifications.allow.detail", TogglePreference("notificationsEnabled")),
            Row("settings.notifications.updates", null, TogglePreference("notifiesUpdates")),
            Row("settings.notifications.test", null, DisabledButton("settings.notifications.test.button"))));
        page.Children.Add(GroupTitle("settings.notifications.accounts"));
        page.Children.Add(NotificationRows("accounts"));
        page.Children.Add(Footnote(words.Get("settings.notifications.runs.footnote")));
        page.Children.Add(GroupTitle("settings.notifications.projects"));
        page.Children.Add(NotificationRows("projects"));
        page.Children.Add(Footnote(words.Get("settings.notifications.down.footnote")));
        page.Children.Add(Footnote(words.Get("settings.notifications.footnote")));
        return page;
    }

    private FrameworkElement NotificationRows(string group)
    {
        var rows = new List<FrameworkElement> { NotificationHeader(group) };
        var root = SettingsJson.Object(list);
        if (root[group] is JsonArray items)
        {
            foreach (var item in items.OfType<JsonObject>())
            {
                var page = SettingsJson.String(item, "kind");
                var id = SettingsJson.String(item, "id");
                var key = RecordKey(page, id);
                rows.Add(group == "accounts"
                    ? NotificationAccountRow(item, page, id, key)
                    : NotificationProjectRow(item, id));
            }
        }
        return rows.Count == 1 ? Card(ModelRow(words.Get("settings.sidebar.empty"), "", null)) : Card(rows.ToArray());
    }

    private FrameworkElement NotificationHeader(string group)
    {
        var keys = group == "accounts"
            ? new[]
            {
                "settings.notifications.column.review",
                "settings.notifications.column.stuck",
                "settings.notifications.column.runs",
            }
            : new[]
            {
                "settings.notifications.column.down",
                "settings.notifications.column.startFailed",
            };
        var grid = NotificationGrid(keys.Length, 34);
        for (var index = 0; index < keys.Length; index++)
        {
            var label = new TextBlock
            {
                Text = words.Get(keys[index]),
                FontSize = 11,
                Foreground = WindowsTheme.Brush("TextTertiary"),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                TextAlignment = TextAlignment.Center,
                TextWrapping = TextWrapping.Wrap,
            };
            Grid.SetColumn(label, index + 1);
            grid.Children.Add(label);
        }
        return grid;
    }

    private FrameworkElement NotificationAccountRow(JsonObject item, string page, string id, string key)
    {
        if (!records.TryGetValue(key, out var record))
        {
            return ModelRow(SettingsJson.String(item, "title"), SettingsJson.String(item, "detail"), null);
        }
        var controls = new List<FrameworkElement>
        {
            NotificationToggle(
            SettingsJson.Bool(record, "notifiesReviewRequests"),
            value => SaveNotificationRecord(page, id, record, "notifiesReviewRequests", value)),
            NotificationToggle(
            SettingsJson.Bool(record, "notifiesBlocked"),
            value => SaveNotificationRecord(page, id, record, "notifiesBlocked", value)),
        };
        if (page == "github")
        {
            controls.Add(NotificationToggle(
                SettingsJson.Bool(record, "notifiesFailedRuns"),
                value => SaveNotificationRecord(page, id, record, "notifiesFailedRuns", value)));
        }
        else
        {
            controls.Add(new TextBlock
            {
                Text = "-",
                Foreground = WindowsTheme.Brush("TextTertiary"),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            });
        }
        return NotificationDataRow(item, controls);
    }

    private FrameworkElement NotificationProjectRow(JsonObject item, string id)
    {
        return NotificationDataRow(item,
        [
            NotificationToggle(
                !PreferenceArray("projectsQuietWhenDown").Contains(id, StringComparer.Ordinal),
                value => SetProjectNotification("projectsQuietWhenDown", id, value)),
            NotificationToggle(
                !PreferenceArray("projectsQuietWhenStartFails").Contains(id, StringComparer.Ordinal),
                value => SetProjectNotification("projectsQuietWhenStartFails", id, value)),
        ]);
    }

    private FrameworkElement NotificationDataRow(JsonObject item, IReadOnlyList<FrameworkElement> controls)
    {
        var grid = NotificationGrid(controls.Count, 52);
        var copy = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        copy.Children.Add(new TextBlock { Text = SettingsJson.String(item, "title") });
        copy.Children.Add(new TextBlock
        {
            Text = SettingsJson.String(item, "detail"),
            FontSize = 12,
            Foreground = WindowsTheme.Brush("TextTertiary"),
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        grid.Children.Add(copy);
        for (var index = 0; index < controls.Count; index++)
        {
            Grid.SetColumn(controls[index], index + 1);
            grid.Children.Add(controls[index]);
        }
        return grid;
    }

    private static Grid NotificationGrid(int controlCount, double minHeight)
    {
        var grid = new Grid { MinHeight = minHeight, Margin = new Thickness(16, 4, 16, 4) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (var index = 0; index < controlCount; index++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(94) });
        }
        return grid;
    }

    private static FrameworkElement NotificationToggle(bool selected, Action<bool> changed)
    {
        var toggle = Toggle(selected, true, changed);
        toggle.HorizontalAlignment = HorizontalAlignment.Center;
        return toggle;
    }

    private void EnsureNotificationRecords()
    {
        var root = SettingsJson.Object(list);
        if (root["accounts"] is not JsonArray accounts)
        {
            return;
        }
        foreach (var item in accounts.OfType<JsonObject>())
        {
            LoadRecord(SettingsJson.String(item, "kind"), SettingsJson.String(item, "id"));
        }
    }

    private void SaveNotificationRecord(
        string page,
        string id,
        JsonObject record,
        string property,
        bool value)
    {
        SettingsJson.Set(record, property, value);
        var request = page == "github" ? "saveGitHubAccount" : "saveGitLabAccount";
        client.Request(SettingsJson.Value(request, record), _ => client.RefreshList());
        records[RecordKey(page, id)] = record;
    }

    private void SetProjectNotification(string preference, string id, bool enabled)
    {
        var values = PreferenceArray(preference).ToHashSet(StringComparer.Ordinal);
        if (enabled)
        {
            values.Remove(id);
        }
        else
        {
            values.Add(id);
        }
        SetPreference(
            preference,
            new JsonArray(
                values
                    .Order(StringComparer.Ordinal)
                    .Select(value => (JsonNode?)JsonValue.Create(value))
                    .ToArray()));
    }

    private FrameworkElement RecordPage()
    {
        if (route.Item is null || !records.TryGetValue(RecordKey(route.Page, route.Item), out var record))
        {
            return EmptyPage();
        }
        return route.Page switch
        {
            "github" or "gitlab" => AccountPage(record),
            _ => ProjectPage(record),
        };
    }

    private FrameworkElement AccountPage(JsonObject record)
    {
        var title = SettingsJson.String(record, "label");
        var subtitle = route.Page == "github" ? SettingsJson.String(record, "apiBaseURL") : SettingsJson.String(record, "host");
        var page = ModelHeader(title, subtitle, route.Page, record);
        if (route.Page == "gitlab")
        {
            page.Children.Add(GroupTitle("account.section.instance"));
            page.Children.Add(Card(
                FieldRow("account.name", record, "label", false),
                FieldRow("account.gitlab.address", record, "host", true),
                BrowserRow(record)));
        }
        page.Children.Add(GroupTitle("account.section.token"));
        page.Children.Add(TokenCard(record));
        page.Children.Add(TokenPageLink(record));
        if (route.Page == "github")
        {
            page.Children.Add(GroupTitle("account.section.account"));
            page.Children.Add(Card(
                FieldRow("account.name", record, "label", false),
                BrowserRow(record)));
            var recordKey = RecordKey(route.Page, route.Item ?? "");
            page.Children.Add(AdvancedDisclosure(recordKey));
            if (expandedAdvanced.Contains(recordKey))
            {
                page.Children.Add(Card(ArrayFieldRow(
                    "account.github.organisations",
                    "account.github.organisations.placeholder",
                    record,
                    "organizations")));
            }
        }
        return page;
    }

    private FrameworkElement TokenPageLink(JsonObject record)
    {
        var key = route.Page == "github" ? "account.github.create" : "account.gitlab.create";
        var value = route.Page == "github" ? null : AccountHost(record);
        var button = new Button
        {
            Content = words.Get(key, value),
            Style = WindowsTheme.Style("LinkButton"),
            Margin = new Thickness(6, 5, 0, 0),
        };
        button.Click += (_, _) =>
        {
            var request = route.Page == "github"
                ? SettingsJson.Empty("openGitHubTokenPage")
                : SettingsJson.Value("openGitLabTokenPage", record);
            client.Request(request);
        };
        return button;
    }

    private FrameworkElement AdvancedDisclosure(string recordKey)
    {
        var open = expandedAdvanced.Contains(recordKey);
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        panel.Children.Add(DeckIcons.Create(open ? "collapse" : "expand", 10));
        panel.Children.Add(new TextBlock
        {
            Text = words.Get("account.advanced"),
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(7, 0, 10, 0),
        });
        panel.Children.Add(new TextBlock
        {
            Text = words.Get("account.github.advanced.summary"),
            Foreground = WindowsTheme.Brush("TextTertiary"),
        });
        var button = new Button
        {
            Content = panel,
            Style = WindowsTheme.Style("RowButton"),
            Margin = new Thickness(0, 14, 0, 2),
            HorizontalContentAlignment = HorizontalAlignment.Left,
        };
        button.Click += (_, _) =>
        {
            if (!expandedAdvanced.Add(recordKey))
            {
                expandedAdvanced.Remove(recordKey);
            }
            Render();
        };
        return button;
    }

    private static string AccountHost(JsonObject record)
    {
        var address = SettingsJson.String(record, "host");
        return Uri.TryCreate(address, UriKind.Absolute, out var url) ? url.Host : address;
    }

    private FrameworkElement TokenCard(JsonObject record)
    {
        var recordKey = RecordKey(route.Page, route.Item ?? "");
        var submission = new TokenSubmission();
        var password = new PasswordBox
        {
            Height = 32,
            Style = WindowsTheme.Style("SettingsPasswordBox"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        password.PasswordChanged += (_, _) => submission.Typed = password.Password;
        var save = ActionButton("token.save", () =>
        {
            var typed = submission.Take();
            password.Clear();
            var request = route.Page == "github" ? "checkGitHubToken" : "checkGitLabToken";
            SetTokenChecking(recordKey);
            client.Request(SettingsJson.Token(request, record, typed), answer => ApplyTokenAnswer(recordKey, answer));
        });
        var controls = new Grid();
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        controls.Children.Add(password);
        save.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(save, 1);
        controls.Children.Add(save);
        var status = tokenStatuses.TryGetValue(recordKey, out var current)
            ? current
            : (words.Get("token.none"), words.Get("token.none.detail"));
        return Card(
            ModelRow(status.Item1, status.Item2, ActionButton("token.verify", () =>
            {
                SetTokenChecking(recordKey);
                client.Request(
                    SettingsJson.Token(route.Page == "github" ? "checkGitHubToken" : "checkGitLabToken", record, ""),
                    answer => ApplyTokenAnswer(recordKey, answer));
            })),
            FormRow(words.Get("token.field"), "", controls));
    }

    private FrameworkElement ProjectPage(JsonObject record)
    {
        var title = SettingsJson.String(record, route.Page == "ddev" ? "title" : "title");
        if (title.Length == 0 && route.Page == "ddev")
        {
            title = SettingsJson.String(record, "name");
        }
        var folder = SettingsJson.String(record, "folder");
        var page = ModelHeader(title, folder, route.Page, record);
        page.Children.Add(GroupTitle("project.section.project"));
        page.Children.Add(Card(
            FieldRow(
                "account.name",
                record,
                "title",
                false,
                initialValue: route.Page == "ddev" ? title : null),
            FolderRow(record)));
        if (route.Page == "project")
        {
            page.Children.Add(GroupTitle("project.section.start"));
            page.Children.Add(Card(
                StartCommandRow(record),
                FieldRow("project.stopCommand", record, "stopCommand", true, "project.stop.placeholder"),
                BoolRow("project.longRunning", "project.longRunning.detail", record, "holdsProcess"),
                BoolRow("project.needsDocker", "project.needsDocker.detail", record, "requiresDocker")));
            page.Children.Add(GroupTitle("project.section.health"));
            page.Children.Add(Card(
                FieldRow("project.checkURL", record, "healthURL", true),
                FieldRow("project.openURL", record, "localSiteURL", true, "project.openURL.placeholder"),
                CheckRow(record)));
            AddLinks(page, record, "links");
            page.Children.Add(Card(BrowserRow(record)));
        }
        else if (route.Page == "arc")
        {
            page.Children.Add(GroupTitle("project.section.stack"));
            page.Children.Add(Card(
                FieldRow("project.startCommand", record, "startCommand", true),
                FieldRow("project.stopCommand", record, "stopCommand", true),
                FieldRow("project.checkURL", record, "healthPath", true),
                FieldRow("project.openURL", record, "localURL", true),
                CheckRow(record)));
            page.Children.Add(GroupTitle("project.arc.organisation"));
            page.Children.Add(Card(
                FieldRow("project.arc.organisation", record, "organization", false),
                FieldRow("project.arc.site", record, "site", false, "project.arc.site.placeholder")));
            page.Children.Add(Footnote(words.Get("project.arc.footnote")));
            AddLinks(page, record, "links");
            page.Children.Add(Card(BrowserRow(record)));
        }
        else if (route.Page == "ddev")
        {
            page.Children.Add(GroupTitle("project.ddev.tools"));
            page.Children.Add(Card(
                BoolRow("Mailpit", null, record, "showsMailpit"),
                BoolRow("xhgui", null, record, "showsXhgui")));
            AddLinks(page, record, "customLinks");
            page.Children.Add(Card(BrowserRow(record)));
        }
        return page;
    }

    private FrameworkElement FolderRow(JsonObject record)
    {
        var field = BoundTextBox(record, "folder", true, null);
        var recordKey = RecordKey(route.Page, route.Item ?? "");
        if (route.Page == "ddev")
        {
            field.LostKeyboardFocus += (_, _) =>
                client.Request(
                    SettingsJson.Named("ddevFolderNote", "folder", field.Text),
                    answer => ApplyFolderNote(recordKey, answer));
        }
        var placeText = Place(SettingsJson.String(record, "folder"));
        var choose = ActionButton("button.choose", () => ChooseFolder(field));
        choose.Margin = new Thickness(8, 0, 0, 0);
        var controls = new Grid();
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        controls.Children.Add(field);
        var column = 1;
        if (placeText.Length > 0)
        {
            controls.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var place = new Border
            {
                BorderBrush = WindowsTheme.Brush("TextTertiary"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(4),
                Padding = new Thickness(8, 4, 8, 4),
                Margin = new Thickness(8, 0, 0, 0),
                Child = new TextBlock { Text = placeText, FontSize = 12 },
            };
            Grid.SetColumn(place, column++);
            controls.Children.Add(place);
        }
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(choose, column);
        controls.Children.Add(choose);
        return FormRow(
            words.Get("project.folder"),
            folderNotes.TryGetValue(recordKey, out var note) ? note : "",
            controls);
    }

    private FrameworkElement StartCommandRow(JsonObject record)
    {
        var field = BoundTextBox(record, "startCommand", true, "project.start.placeholder");
        var detect = ActionButton("button.detect", () =>
        {
            var recordKey = RecordKey(route.Page, route.Item ?? "");
            client.Request(
                SettingsJson.Named("detect", "folder", SettingsJson.String(record, "folder")),
                answer => ApplyDetection(recordKey, record, answer));
        });
        detect.Margin = new Thickness(8, 0, 0, 0);
        var controls = new Grid();
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        controls.Children.Add(field);
        Grid.SetColumn(detect, 1);
        controls.Children.Add(detect);
        return FormRow(words.Get("project.startCommand"), "", controls);
    }

    private FrameworkElement BrowserRow(JsonObject record)
    {
        var recordKey = RecordKey(route.Page, route.Item ?? "");
        var browser = SettingsJson.Object(record["browser"]);
        var browserPicker = new ComboBox
        {
            Style = WindowsTheme.Style("SettingsComboBox"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        var choices = WindowsBrowserCatalog.Installed().ToList();
        var current = SettingsJson.String(browser, "bundleIdentifier");
        if (current.Length > 0 && !choices.Any(choice => string.Equals(choice.Identifier, current, StringComparison.OrdinalIgnoreCase)))
        {
            if (WindowsBrowserCatalog.Resolve(current, choices) is { } legacy)
            {
                choices.Add(legacy);
            }
        }
        foreach (var choice in choices)
        {
            browserPicker.Items.Add(new ComboBoxItem { Content = choice.Name, Tag = choice });
        }
        browserPicker.SelectedIndex = Math.Max(0, choices.FindIndex(choice =>
            string.Equals(choice.Identifier ?? "", current, StringComparison.OrdinalIgnoreCase)));

        var profilePicker = new ComboBox
        {
            Style = WindowsTheme.Style("SettingsComboBox"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Margin = new Thickness(8, 0, 0, 0),
        };
        var profileColumn = new ColumnDefinition { Width = new GridLength(0) };
        var changingProfile = false;
        void ReloadProfiles(string? selectedDirectory)
        {
            changingProfile = true;
            profilePicker.Items.Clear();
            var selectedBrowser = (browserPicker.SelectedItem as ComboBoxItem)?.Tag as WindowsBrowserOption;
            var profiles = selectedBrowser is null
                ? []
                : WindowsBrowserCatalog.Profiles(selectedBrowser).ToArray();
            foreach (var profile in profiles)
            {
                profilePicker.Items.Add(new ComboBoxItem { Content = profile.Name, Tag = profile.Directory });
            }
            profileColumn.Width = profiles.Length > 0
                ? new GridLength(1, GridUnitType.Star)
                : new GridLength(0);
            profilePicker.Visibility = profiles.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
            profilePicker.SelectedIndex = profiles.Length == 0
                ? -1
                : Math.Max(0, Array.FindIndex(profiles, profile =>
                    string.Equals(profile.Directory, selectedDirectory, StringComparison.OrdinalIgnoreCase)));
            changingProfile = false;
        }
        ReloadProfiles(SettingsJson.String(browser, "profileDirectory"));
        browserPicker.SelectionChanged += (_, _) =>
        {
            if (applying || browserPicker.SelectedItem is not ComboBoxItem item ||
                item.Tag is not WindowsBrowserOption choice)
            {
                return;
            }
            browser["bundleIdentifier"] = choice.Identifier is { } identifier
                ? JsonValue.Create(identifier)
                : null;
            browser["profileDirectory"] = null;
            ReloadProfiles(null);
            browser["profileDirectory"] = profilePicker.SelectedItem is ComboBoxItem profile &&
                profile.Tag is string directory
                ? JsonValue.Create(directory)
                : null;
            record["browser"] = browser;
            SaveRecord(record);
        };
        profilePicker.SelectionChanged += (_, _) =>
        {
            if (applying || changingProfile || profilePicker.SelectedItem is not ComboBoxItem item)
            {
                return;
            }
            browser["profileDirectory"] = item.Tag is string directory
                ? JsonValue.Create(directory)
                : null;
            record["browser"] = browser;
            SaveRecord(record);
        };
        var controls = new Grid();
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        controls.ColumnDefinitions.Add(profileColumn);
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        controls.Children.Add(browserPicker);
        Grid.SetColumn(profilePicker, 1);
        controls.Children.Add(profilePicker);
        var test = ActionButton("button.test", () => TestLink(recordKey, record));
        test.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(test, 2);
        controls.Children.Add(test);
        return FormRow(
            words.Get("account.openLinksIn"),
            linkNotes.TryGetValue(recordKey, out var note) ? note : "",
            controls);
    }

    private void AddLinks(StackPanel page, JsonObject record, string property)
    {
        if (record[property] is not JsonArray links || links.Count == 0)
        {
            return;
        }
        page.Children.Add(GroupTitle("project.section.links"));
        page.Children.Add(Card(links.OfType<JsonObject>().Select(link => LinkRow(record, link)).ToArray()));
    }

    private FrameworkElement LinkRow(JsonObject record, JsonObject link)
    {
        var enabled = Toggle(SettingsJson.Bool(link, "isEnabled"), true, selected =>
        {
            SettingsJson.Set(link, "isEnabled", selected);
            SaveRecord(record);
        });
        var chip = new Border
        {
            Background = WindowsTheme.Brush("ControlHover"),
            Height = 20,
            CornerRadius = new CornerRadius(3),
            Padding = new Thickness(6, 0, 6, 0),
            Margin = new Thickness(8, 0, 8, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock
            {
                Text = SettingsJson.String(link, "label").ToUpperInvariant(),
                FontSize = 10,
                FontFamily = WindowsTheme.Mono,
                VerticalAlignment = VerticalAlignment.Center,
            },
        };
        var field = new TextBox
        {
            Text = SettingsJson.String(link, "urlTemplate"),
            Height = 32,
            FontFamily = WindowsTheme.Mono,
            Style = WindowsTheme.Style("PromptTextBox"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        field.LostKeyboardFocus += (_, _) =>
        {
            SettingsJson.Set(link, "urlTemplate", field.Text);
            SaveRecord(record);
        };
        var row = new Grid { MinHeight = 48, Margin = new Thickness(16, 6, 16, 6) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.Children.Add(enabled);
        Grid.SetColumn(chip, 1);
        row.Children.Add(chip);
        Grid.SetColumn(field, 2);
        row.Children.Add(field);
        return row;
    }

    private FrameworkElement ArrayFieldRow(
        string labelKey,
        string placeholderKey,
        JsonObject record,
        string property)
    {
        var values = record[property] as JsonArray;
        var field = new TextBox
        {
            Text = values is null
                ? ""
                : string.Join(", ", values.Select(value => value?.GetValue<string>() ?? "")),
            Tag = words.Get(placeholderKey),
            MinWidth = 300,
            Height = 32,
            Style = WindowsTheme.Style("PromptTextBox"),
        };
        field.LostKeyboardFocus += (_, _) =>
        {
            record[property] = new JsonArray(
                field.Text
                    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                    .Select(value => (JsonNode?)JsonValue.Create(value))
                    .ToArray());
            SaveRecord(record);
        };
        return FormRow(words.Get(labelKey), "", field);
    }

    private FrameworkElement CheckRow(JsonObject record)
    {
        var recordKey = RecordKey(route.Page, route.Item ?? "");
        var summary = checks.TryGetValue(recordKey, out var current) ? current : null;
        return ModelRow(
            summary is null ? words.Get("check.notChecked") : SettingsJson.String(summary, "state"),
            summary is null ? "" : SettingsJson.String(summary, "detail"),
            ActionButton("button.checkNow", () =>
            {
                var request = route.Page == "project" ? "checkLocalProject" : "checkArcStack";
                checks[recordKey] = new JsonObject
                {
                    ["state"] = words.Get("check.working"),
                    ["detail"] = "",
                };
                Render();
                client.Request(SettingsJson.Value(request, record), answer => ApplyCheckAnswer(recordKey, answer));
            }));
    }

    private StackPanel ModelHeader(string title, string subtitle, string mark, JsonObject record)
    {
        var page = new StackPanel();
        var header = new Grid { Margin = new Thickness(0, 0, 0, 18) };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(50) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.Children.Add(BigIcon(mark));
        var copy = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        copy.Children.Add(new TextBlock { Text = title, FontSize = 20, FontWeight = FontWeights.SemiBold });
        copy.Children.Add(new TextBlock { Text = subtitle, FontSize = 12, Foreground = WindowsTheme.Brush("TextSecondary"), TextTrimming = TextTrimming.CharacterEllipsis });
        Grid.SetColumn(copy, 1);
        header.Children.Add(copy);
        var toggle = Toggle(SettingsJson.Bool(record, "isEnabled"), true, selected =>
        {
            SettingsJson.Set(record, "isEnabled", selected);
            SaveRecord(record);
        });
        var enabled = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        enabled.Children.Add(new TextBlock { Text = words.Get("account.showOnDeck"), Foreground = WindowsTheme.Brush("TextSecondary"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0) });
        enabled.Children.Add(toggle);
        Grid.SetColumn(enabled, 2);
        header.Children.Add(enabled);
        page.Children.Add(header);
        return page;
    }

    private StackPanel PageHeader(string titleKey, string? subtitleKey, string icon)
    {
        var page = new StackPanel();
        var header = new Grid { Margin = new Thickness(0, 0, 0, 18) };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(50) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.Children.Add(BigIcon(icon));
        var copy = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        copy.Children.Add(new TextBlock { Text = words.Get(titleKey), FontSize = 20, FontWeight = FontWeights.SemiBold });
        if (subtitleKey is not null)
        {
            copy.Children.Add(new TextBlock { Text = words.Get(subtitleKey), FontSize = 12, Foreground = WindowsTheme.Brush("TextSecondary") });
        }
        Grid.SetColumn(copy, 1);
        header.Children.Add(copy);
        page.Children.Add(header);
        return page;
    }

    private Border BigIcon(string icon)
    {
        return new Border
        {
            Width = 36,
            Height = 36,
            CornerRadius = new CornerRadius(8),
            Background = WindowsTheme.Brush("ControlHover"),
            Child = MarkIcon(icon, 18),
        };
    }

    private static FrameworkElement MarkIcon(string name, double size)
    {
        return BrandMarks.Names.Contains(name)
            ? BrandMarks.Create(name, size)
            : DeckIcons.Create(name, size);
    }

    private TextBlock GroupTitle(string key)
    {
        return new TextBlock
        {
            Text = words.Get(key),
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 18, 0, 8),
        };
    }

    private Border Card(params FrameworkElement[] rows)
    {
        var panel = new StackPanel();
        for (var index = 0; index < rows.Length; index++)
        {
            if (index > 0)
            {
                panel.Children.Add(new Border { Height = 1, Background = WindowsTheme.Brush("SeparatorStroke") });
            }
            panel.Children.Add(rows[index]);
        }
        return new Border
        {
            Background = WindowsTheme.Brush("ControlFill"),
            BorderBrush = WindowsTheme.Brush("ControlStroke"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Child = panel,
        };
    }

    private FrameworkElement Row(string labelKey, string? detailKey, FrameworkElement control)
    {
        return ModelRow(words.Get(labelKey), detailKey is null ? "" : words.Get(detailKey), control);
    }

    private FrameworkElement ModelRow(string label, string detail, FrameworkElement? control)
    {
        var grid = new Grid { MinHeight = 48, Margin = new Thickness(16, 6, 16, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var copy = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        copy.Children.Add(new TextBlock { Text = label });
        if (detail.Length > 0)
        {
            copy.Children.Add(new TextBlock { Text = detail, FontSize = 12, Foreground = WindowsTheme.Brush("TextTertiary"), TextWrapping = TextWrapping.Wrap });
        }
        grid.Children.Add(copy);
        if (control is not null)
        {
            control.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(control, 1);
            grid.Children.Add(control);
        }
        return grid;
    }

    private FrameworkElement FormRow(string label, string detail, FrameworkElement control)
    {
        var grid = new Grid { MinHeight = 48, Margin = new Thickness(16, 6, 16, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(FormLabelWidth) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var copy = new StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 12, 0),
        };
        copy.Children.Add(new TextBlock { Text = label });
        if (detail.Length > 0)
        {
            copy.Children.Add(new TextBlock
            {
                Text = detail,
                FontSize = 12,
                Foreground = WindowsTheme.Brush("TextTertiary"),
                TextWrapping = TextWrapping.Wrap,
            });
        }
        grid.Children.Add(copy);
        control.VerticalAlignment = VerticalAlignment.Center;
        control.HorizontalAlignment = HorizontalAlignment.Stretch;
        Grid.SetColumn(control, 1);
        grid.Children.Add(control);
        return grid;
    }

    private FrameworkElement FieldRow(
        string labelKey,
        JsonObject record,
        string property,
        bool mono,
        string? placeholderKey = null,
        string? initialValue = null)
    {
        var field = BoundTextBox(record, property, mono, placeholderKey, initialValue);
        return FormRow(words.Get(labelKey), "", field);
    }

    private TextBox BoundTextBox(
        JsonObject record,
        string property,
        bool mono,
        string? placeholderKey,
        string? initialValue = null)
    {
        var field = new TextBox
        {
            Text = initialValue ?? SettingsJson.String(record, property),
            Height = 32,
            FontFamily = mono ? WindowsTheme.Mono : WindowsTheme.Sans,
            Style = WindowsTheme.Style("PromptTextBox"),
            Tag = placeholderKey is null ? null : words.Get(placeholderKey),
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        field.LostKeyboardFocus += (_, _) =>
        {
            SettingsJson.Set(record, property, field.Text);
            SaveRecord(record);
        };
        return field;
    }

    private FrameworkElement BoolRow(string labelKey, string? detailKey, JsonObject record, string property)
    {
        var label = labelKey.Contains('.') ? words.Get(labelKey) : labelKey;
        var detail = detailKey is null ? "" : words.Get(detailKey);
        return ModelRow(label, detail, Toggle(SettingsJson.Bool(record, property), true, selected =>
        {
            SettingsJson.Set(record, property, selected);
            SaveRecord(record);
        }));
    }

    private CheckBox TogglePreference(string name)
    {
        return Toggle(PreferenceBool(name), true, value => SetPreference(name, value));
    }

    private static CheckBox Toggle(bool value, bool enabled, Action<bool> changed)
    {
        var toggle = new CheckBox
        {
            IsChecked = value,
            IsEnabled = enabled,
            VerticalAlignment = VerticalAlignment.Center,
            Style = WindowsTheme.Style("SettingsToggle"),
        };
        toggle.Checked += (_, _) => changed(true);
        toggle.Unchecked += (_, _) => changed(false);
        return toggle;
    }

    private Button ActionButton(string key, Action action)
    {
        var button = new Button { Content = words.Get(key), Style = WindowsTheme.Style("FluentButton"), Height = 32 };
        button.Click += (_, _) => action();
        return button;
    }

    private static void ConfigureButton(Button button, string automationId)
    {
        button.Style = WindowsTheme.Style("FluentButton");
        button.Height = 32;
        AutomationProperties.SetAutomationId(button, automationId);
    }

    private FrameworkElement UpdateRow()
    {
        if (update is not { } value)
        {
            return ModelRow("", "", ActionButton("update.button.check", () => client.SendIntent("update.check")));
        }
        var summary = JsonModel.Object(value, "summary", out var found) ? found : default;
        var state = summary.ValueKind == JsonValueKind.Object ? JsonModel.String(summary, "state") ?? "" : "";
        var detail = summary.ValueKind == JsonValueKind.Object ? JsonModel.String(summary, "detail") ?? "" : "";
        var button = new Button
        {
            Content = JsonModel.String(value, "button") ?? "",
            IsEnabled = JsonModel.Bool(value, "isEnabled"),
            Style = WindowsTheme.Style("FluentButton"),
        };
        button.Click += (_, _) => client.SendIntent("update.act");
        return ModelRow(state, detail, button);
    }

    private Button DisabledButton(string key)
    {
        return new Button
        {
            Content = words.Get(key),
            Style = WindowsTheme.Style("FluentButton"),
            Height = 32,
            IsEnabled = false,
        };
    }

    private TextBlock Footnote(string text)
    {
        return new TextBlock
        {
            Text = text,
            FontSize = 12,
            Foreground = WindowsTheme.Brush("TextTertiary"),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(2, 8, 2, 0),
        };
    }

    private FrameworkElement EmptyPage()
    {
        return new TextBlock { Text = words.Get(route.Item is null ? "settings.empty.nothingSelected" : "settings.empty.nothingYet") };
    }

    private void LoadRecord(string page, string id)
    {
        var key = RecordKey(page, id);
        if (records.ContainsKey(key) || !loadingRecords.Add(key))
        {
            return;
        }
        var request = page switch
        {
            "github" => "githubAccount",
            "gitlab" => "gitlabAccount",
            "project" => "localProject",
            "arc" => "arcProject",
            "ddev" => "ddevProject",
            _ => "",
        };
        if (request.Length == 0)
        {
            return;
        }
        client.Request(SettingsJson.Named(request, "id", id), answer =>
        {
            loadingRecords.Remove(key);
            if (SettingsJson.CaseValue(answer, request) is JsonObject record)
            {
                records[key] = record;
                Render();
            }
        });
    }

    private void SaveRecord(JsonObject record)
    {
        if (applying)
        {
            return;
        }
        var page = route.Page;
        var item = route.Item;
        var request = page switch
        {
            "github" => "saveGitHubAccount",
            "gitlab" => "saveGitLabAccount",
            "project" => "saveLocalProject",
            "arc" => "saveArcProject",
            "ddev" => "saveDDEVProject",
            _ => "",
        };
        if (request.Length > 0)
        {
            client.Request(SettingsJson.Value(request, record), answer =>
            {
                client.RefreshList();
                if (SettingsJson.Case(answer, "saved", out var saved) && JsonModel.Bool(saved, "checkAgain"))
                {
                    var check = page == "project" ? "checkLocalProject" : "checkArcStack";
                    var recordKey = RecordKey(page, item ?? "");
                    client.Request(SettingsJson.Value(check, record), answer => ApplyCheckAnswer(recordKey, answer));
                }
            });
        }
    }

    private void SetPreference(string name, object? value)
    {
        if (applying || preferences is null)
        {
            return;
        }
        preferences[name] = value switch
        {
            null => null,
            JsonNode node => node.DeepClone(),
            string text => JsonValue.Create(text),
            bool selected => JsonValue.Create(selected),
            int number => JsonValue.Create(number),
            _ => throw new InvalidOperationException(),
        };
        client.SavePreferences(preferences);
    }

    private bool PreferenceBool(string name)
    {
        return preferences?[name]?.GetValue<bool>() ?? false;
    }

    private string PreferenceString(string name)
    {
        return preferences?[name]?.GetValue<string>() ?? "";
    }

    private double PreferenceDouble(string name)
    {
        return preferences?[name]?.GetValue<double>() ?? 0;
    }

    private IEnumerable<string> PreferenceArray(string name)
    {
        return preferences?[name] is JsonArray values
            ? values.Select(value => value?.GetValue<string>() ?? "")
            : [];
    }

    private void CaptureShortcut(TextBox field, KeyEventArgs eventArgs)
    {
        if (eventArgs.Key is Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin)
        {
            return;
        }
        var parts = new List<string>();
        if ((Keyboard.Modifiers & ModifierKeys.Control) != 0)
        {
            parts.Add("Ctrl");
        }
        if ((Keyboard.Modifiers & ModifierKeys.Shift) != 0)
        {
            parts.Add("Shift");
        }
        if ((Keyboard.Modifiers & ModifierKeys.Alt) != 0)
        {
            parts.Add("Alt");
        }
        if (Keyboard.IsKeyDown(Key.LWin) || Keyboard.IsKeyDown(Key.RWin))
        {
            parts.Add("Win");
        }
        if (parts.Count == 0)
        {
            return;
        }
        parts.Add(eventArgs.Key.ToString());
        field.Text = string.Join("+", parts);
        SetPreference("summonShortcutWindows", field.Text);
        eventArgs.Handled = true;
    }

    private string Place(string folder)
    {
        if (folder.Length == 0)
        {
            return "";
        }
        const string prefix = @"\\wsl.localhost\";
        if (folder.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            var rest = folder[prefix.Length..];
            var end = rest.IndexOf('\\');
            var distribution = end < 0 ? rest : rest[..end];
            return words.Get("project.place.wsl", distribution);
        }
        return words.Get("project.place.windows");
    }

    private void ChooseFolder(TextBox target)
    {
        using var dialog = new System.Windows.Forms.FolderBrowserDialog();
        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            target.Text = dialog.SelectedPath;
            target.MoveFocus(new TraversalRequest(FocusNavigationDirection.Next));
        }
    }

    private void OpenAddMenu()
    {
        if (addMenu is not null)
        {
            addMenu.IsOpen = false;
        }
        addMenu = new ContextMenu { Style = WindowsTheme.Style("DeckContextMenu") };
        AddMenuItem(addMenu, "settings.add.github", () => AddSimple("addGitHubAccount", "github"));
        AddMenuItem(addMenu, "settings.add.gitlab", () => AddSimple("addGitLabAccount", "gitlab"));
        AddMenuItem(addMenu, "settings.add.local", AddLocal);
        AddMenuItem(addMenu, "settings.add.arc", () => AddSimple("addArcProject", "arc"));
        AddMenuItem(addMenu, "settings.add.ddev", AddDdev);
        addMenu.PlacementTarget = addButton;
        addMenu.Placement = System.Windows.Controls.Primitives.PlacementMode.Top;
        addMenu.VerticalOffset = -4;
        addMenu.Closed += (_, _) => addMenu = null;
        addMenu.IsOpen = true;
    }

    private void AddMenuItem(ContextMenu menu, string key, Action action)
    {
        var item = new MenuItem { Header = words.Get(key), Style = WindowsTheme.Style("DeckMenuItem") };
        item.Click += (_, _) => action();
        menu.Items.Add(item);
    }

    private void AddSimple(string request, string page)
    {
        client.Request(SettingsJson.Empty(request), answer => Added(answer, page));
    }

    private void AddLocal()
    {
        using var dialog = new System.Windows.Forms.FolderBrowserDialog();
        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            client.Request(SettingsJson.Named("addLocalProject", "folder", dialog.SelectedPath), answer => Added(answer, "project"));
        }
    }

    private void AddDdev()
    {
        client.Request(SettingsJson.Empty("ddevCandidates"), answer =>
        {
            if (DdevCandidates(answer) is { Count: > 0 } candidates)
            {
                var selected = DdevCandidateDialog.Choose(
                    this,
                    words.Get("settings.add.ddev"),
                    candidates,
                    words.Get("button.add"),
                    words.Get("button.cancel"));
                if (selected is not null)
                {
                    client.Request(SettingsJson.Value("addDDEVProject", selected), result => Added(result, "ddev"));
                }
                return;
            }
            var message = DdevMessage(answer);
            if (message.Length > 0)
            {
                MessageBox.Show(this, message, words.Get("settings.add.ddev"), MessageBoxButton.OK, MessageBoxImage.None);
            }
        });
    }

    private static IReadOnlyList<JsonObject>? DdevCandidates(JsonElement answer)
    {
        if (!SettingsJson.Case(answer, "ddevCandidates", out var payload) ||
            !DeckEvent.TryProperty(payload, "_0", out var candidates) ||
            !candidates.TryGetProperty("some", out var some) ||
            !DeckEvent.TryProperty(some, "_0", out var items) ||
            items.ValueKind != JsonValueKind.Array)
        {
            return null;
        }
        return items
            .EnumerateArray()
            .Select(item => SettingsJson.Object(JsonNode.Parse(item.GetRawText())))
            .ToArray();
    }

    private string DdevMessage(JsonElement answer)
    {
        if (!SettingsJson.Case(answer, "ddevCandidates", out var payload) ||
            !DeckEvent.TryProperty(payload, "_0", out var candidates))
        {
            return "";
        }
        if (candidates.TryGetProperty("unavailable", out _)) return words.Get("ddev.silent.detail");
        if (candidates.TryGetProperty("none", out _)) return words.Get("ddev.none.detail");
        if (candidates.TryGetProperty("allAdded", out _)) return words.Get("ddev.all.detail");
        if (candidates.TryGetProperty("some", out var some) && some.TryGetProperty("_0", out var items) && items.ValueKind == JsonValueKind.Array)
        {
            return string.Join(Environment.NewLine, items.EnumerateArray().Select(item => JsonModel.String(item, "name") ?? ""));
        }
        return "";
    }

    private void Added(JsonElement answer, string page)
    {
        if (SettingsJson.Case(answer, "added", out var payload) && JsonModel.String(payload, "id") is { } id)
        {
            client.RefreshList();
            Navigate(new SettingsRoute(page, id));
        }
    }

    private void RemoveSelected()
    {
        if (route.Item is null || !records.TryGetValue(RecordKey(route.Page, route.Item), out var record))
        {
            return;
        }
        var account = route.Page is "github" or "gitlab";
        var title = words.Get("settings.remove.account.title", RecordTitle(record));
        var detailKey = account ? "settings.remove.account.detail" : $"settings.remove.project.detail.{(route.Page == "project" ? "local" : route.Page)}";
        if (!SettingsConfirmation.Show(this, title, words.Get(detailKey), words.Get("button.remove"), words.Get("button.cancel")))
        {
            return;
        }
        var request = route.Page switch
        {
            "github" => "removeGitHubAccount",
            "gitlab" => "removeGitLabAccount",
            "project" => "removeLocalProject",
            "arc" => "removeArcProject",
            "ddev" => "removeDDEVProject",
            _ => "",
        };
        if (request.Length > 0)
        {
            client.Request(SettingsJson.Named(request, "id", route.Item), _ =>
            {
                records.Remove(RecordKey(route.Page, route.Item));
                route = new SettingsRoute("general", null);
                client.RefreshList();
                Render();
            });
        }
    }

    private void ApplyTokenAnswer(string recordKey, JsonElement answer)
    {
        if (!SettingsJson.Case(answer, "token", out var payload) || !DeckEvent.TryProperty(payload, "_0", out var token))
        {
            return;
        }
        var state = token.TryGetProperty("works", out var works) ? words.Get("token.works") : words.Get("token.refused");
        var detail = token.TryGetProperty("works", out works)
            ? JsonModel.String(works, "_0") ?? ""
            : token.TryGetProperty("refused", out var refused) ? JsonModel.String(refused, "_0") ?? "" : "";
        tokenStatuses[recordKey] = (state, detail);
        if (CurrentRecordKey() == recordKey)
        {
            Render();
        }
    }

    private void SetTokenChecking(string recordKey)
    {
        tokenStatuses[recordKey] = (words.Get("token.checking"), "");
        if (CurrentRecordKey() == recordKey)
        {
            Render();
        }
    }

    private void TestLink(string recordKey, JsonObject record)
    {
        var request = route.Page switch
        {
            "github" => "testGitHubAccountLink",
            "gitlab" => "testGitLabAccountLink",
            "project" => "testLocalProjectLink",
            "arc" => "testArcProjectLink",
            "ddev" => "testDDEVProjectLink",
            _ => "",
        };
        if (request.Length == 0)
        {
            return;
        }
        linkNotes.Remove(recordKey);
        client.Request(SettingsJson.Value(request, record), answer => ApplyLinkNote(recordKey, answer));
    }

    private void ApplyLinkNote(string recordKey, JsonElement answer)
    {
        if (!SettingsJson.Case(answer, "note", out var payload))
        {
            return;
        }
        var note = DeckEvent.TryProperty(payload, "_0", out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? ""
            : "";
        if (note.Length == 0)
        {
            linkNotes.Remove(recordKey);
        }
        else
        {
            linkNotes[recordKey] = note;
        }
        if (CurrentRecordKey() == recordKey)
        {
            Render();
        }
    }

    private void ApplyFolderNote(string recordKey, JsonElement answer)
    {
        if (!SettingsJson.Case(answer, "note", out var payload))
        {
            return;
        }
        var note = DeckEvent.TryProperty(payload, "_0", out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? ""
            : "";
        if (note.Length == 0)
        {
            folderNotes.Remove(recordKey);
        }
        else
        {
            folderNotes[recordKey] = note;
        }
        if (CurrentRecordKey() == recordKey)
        {
            Render();
        }
    }

    private void ApplyCheckAnswer(string recordKey, JsonElement answer)
    {
        if (SettingsJson.CaseValue(answer, "check") is JsonObject check)
        {
            checks[recordKey] = check;
            if (CurrentRecordKey() == recordKey)
            {
                Render();
            }
        }
    }

    private void ApplyDetection(string recordKey, JsonObject record, JsonElement answer)
    {
        if (SettingsJson.CaseValue(answer, "detection") is not JsonObject detection)
        {
            return;
        }
        if (detection["suggestion"] is JsonObject suggestion)
        {
            foreach (var property in new[]
            {
                "subtitle",
                "startCommand",
                "stopCommand",
                "holdsProcess",
                "requiresDocker",
                "healthURL",
            })
            {
                if (suggestion[property] is { } value)
                {
                    record[property] = value.DeepClone();
                }
            }
            SaveRecord(record);
        }
        checks[recordKey] = new JsonObject
        {
            ["state"] = SettingsJson.String(detection, "note"),
            ["detail"] = "",
        };
        if (CurrentRecordKey() == recordKey)
        {
            Render();
        }
    }

    private string? CurrentRecordKey()
    {
        return route.Item is null ? null : RecordKey(route.Page, route.Item);
    }

    private static bool IsRecordPage(string page)
    {
        return page is "github" or "gitlab" or "project" or "arc" or "ddev";
    }

    private static string RecordKey(string page, string id)
    {
        return $"{page}:{id}";
    }

    private static string RecordTitle(JsonObject record)
    {
        var title = SettingsJson.String(record, "title");
        return title.Length > 0 ? title : SettingsJson.String(record, "label");
    }
}

public static class DdevCandidateDialog
{
    public static JsonObject? Choose(
        Window owner,
        string title,
        IReadOnlyList<JsonObject> candidates,
        string add,
        string cancel)
    {
        JsonObject? selected = null;
        var window = new Window
        {
            Owner = owner,
            Title = title,
            Width = 520,
            Height = 400,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Background = new SolidColorBrush(Color.FromRgb(43, 43, 47)),
            Foreground = WindowsTheme.Brush("TextPrimary"),
            FontFamily = WindowsTheme.Sans,
        };
        var root = new Grid { Margin = new Thickness(20) };
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var list = new ListBox
        {
            Background = WindowsTheme.Brush("ControlFill"),
            BorderBrush = WindowsTheme.Brush("ControlStroke"),
            BorderThickness = new Thickness(1),
            Foreground = WindowsTheme.Brush("TextPrimary"),
            Padding = new Thickness(4),
        };
        foreach (var candidate in candidates)
        {
            list.Items.Add(new ListBoxItem
            {
                Style = WindowsTheme.Style("SettingsListBoxItem"),
                Content = new TextBlock
                {
                    Text = $"{SettingsJson.String(candidate, "name")}  {SettingsJson.String(candidate, "approot")}",
                    TextTrimming = TextTrimming.CharacterEllipsis,
                },
                Tag = candidate,
            });
        }
        root.Children.Add(list);
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0),
        };
        var cancelButton = new Button { Content = cancel, Style = WindowsTheme.Style("FluentButton"), MinWidth = 90 };
        cancelButton.Click += (_, _) => window.Close();
        var addButton = new Button { Content = add, Style = WindowsTheme.Style("FluentButton"), MinWidth = 90, Margin = new Thickness(8, 0, 0, 0) };
        addButton.Click += (_, _) =>
        {
            selected = (list.SelectedItem as ListBoxItem)?.Tag as JsonObject;
            if (selected is not null)
            {
                window.Close();
            }
        };
        buttons.Children.Add(cancelButton);
        buttons.Children.Add(addButton);
        Grid.SetRow(buttons, 1);
        root.Children.Add(buttons);
        window.Content = root;
        window.SourceInitialized += (_, _) => NativeMethods.ApplyLogWindowStyles(new WindowInteropHelper(window).Handle);
        window.ShowDialog();
        return selected;
    }
}

public static class SettingsConfirmation
{
    public static bool Show(Window owner, string title, string detail, string confirm, string cancel)
    {
        var result = false;
        var window = new Window
        {
            Owner = owner,
            Title = title,
            Width = 430,
            Height = 210,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = new SolidColorBrush(Color.FromRgb(43, 43, 47)),
            Foreground = WindowsTheme.Brush("TextPrimary"),
            FontFamily = WindowsTheme.Sans,
        };
        var root = new Grid { Margin = new Thickness(24) };
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var copy = new StackPanel();
        copy.Children.Add(new TextBlock { Text = title, FontSize = 20, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        copy.Children.Add(new TextBlock { Text = detail, Foreground = WindowsTheme.Brush("TextSecondary"), Margin = new Thickness(0, 10, 0, 0), TextWrapping = TextWrapping.Wrap });
        root.Children.Add(copy);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancelButton = new Button { Content = cancel, Style = WindowsTheme.Style("FluentButton"), MinWidth = 90 };
        cancelButton.Click += (_, _) => window.Close();
        var confirmButton = new Button { Content = confirm, Style = WindowsTheme.Style("FluentButton"), MinWidth = 90, Margin = new Thickness(8, 0, 0, 0) };
        confirmButton.Click += (_, _) => { result = true; window.Close(); };
        buttons.Children.Add(cancelButton);
        buttons.Children.Add(confirmButton);
        Grid.SetRow(buttons, 1);
        root.Children.Add(buttons);
        window.Content = root;
        window.SourceInitialized += (_, _) => NativeMethods.ApplyLogWindowStyles(new WindowInteropHelper(window).Handle);
        window.ShowDialog();
        return result;
    }
}
