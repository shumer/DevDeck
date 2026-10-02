using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed class SettingsWindow : Window
{
    // Unsaved tokens belong only to this open window; never to persisted settings or the controller.
    private readonly System.Collections.Generic.Dictionary<string,string> tokenDrafts = new(StringComparer.Ordinal);
    private readonly System.Collections.Generic.Dictionary<string,CheckBox> builtinVisibility = new(StringComparer.Ordinal);
    private readonly System.Collections.Generic.Dictionary<string,CheckBox> customVisibility = new(StringComparer.Ordinal);
    private readonly Dictionary<string,SettingsSidebarRow> sidebarRows = new(StringComparer.Ordinal);
    private readonly Dictionary<string,bool> tokenAvailability = new(StringComparer.Ordinal);
    private readonly Func<RemoteAccountSettings,bool> tokenAvailable;
    private readonly DeckController controller;
    private readonly bool live;
    private readonly Func<SettingsRemovalRequest,bool>? confirmation;
    private readonly TextBox search = new() { Margin = new(12), Padding = new(8) };
    private readonly ListBox navigation = new() { BorderThickness = new(0), Background = Brushes.Transparent };
    private readonly ScrollViewer page = new() { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
    private readonly Button remove;
    private readonly TextBlock geometryError = new() { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.Firebrick, Margin = new(16,10,16,10) };
    private readonly Border geometryBanner;
    private HwndSource? geometrySource;
    private SettingsWindowGeometry? resizeEntry;
    private long geometryGeneration;
    private SettingsForm? form;
    private TextBox? arrangementName;
    private ComboBox? arrangements;
    private CheckBox? deckFloating, deckLocked, wifVisibility, wifCompact;
    private Button? saveArrangement, applyArrangement, forgetArrangement;
    private bool arrangementAction;
    private bool changing, allowingClose, sidebarClosed;
    private string selected = "general";
    private sealed record Entry(string ID, string Title, string Detail, bool Heading = false, bool Hint = false,
        string Kind = "", bool Dimmed = false, Brush? Dot = null, string Module = "");
    private sealed record Choice(string ID, string Title) { public override string ToString() => Title; }
    internal ScrollViewer Page => page;
    internal string SelectedPage => selected;
    internal ListBox Navigation => navigation;
    internal TextBox Search => search;
    internal bool GeometryOwnerClosed => sidebarClosed;
    internal bool GeometryPersistenceEnabled => live;
    internal void ReconcileDeckModes()
    {
        if (selected != "deck") return;
        if (deckFloating is not null) deckFloating.IsChecked = controller.Settings.Floating;
        if (deckLocked is not null) deckLocked.IsChecked = controller.Settings.Locked;
    }
    internal void ReconcileArrangements()
    {
        if (selected != "deck" || arrangements is null) return;
        var previous = arrangements.SelectedItem as string;
        var names = controller.Settings.ArrangementList.Select(item => item.Name).ToArray();
        if (arrangements.ItemsSource is not string[] current || !current.SequenceEqual(names, StringComparer.Ordinal)) {
            arrangements.ItemsSource = names;
            arrangements.SelectedItem = names.FirstOrDefault(name => string.Equals(name, previous, StringComparison.OrdinalIgnoreCase));
        }
        RefreshArrangementButtons();
    }
    private void RefreshArrangementButtons()
    {
        if (selected != "deck" || arrangementName is null || arrangements is null) return;
        var raw = arrangementName.Text;
        if (saveArrangement is not null) saveArrangement.IsEnabled = !arrangementAction && !raw.Any(char.IsControl) && raw.Trim().Length is >0 and <=128;
        var chosen = arrangements.SelectedItem as string;
        if (applyArrangement is not null) applyArrangement.IsEnabled = !arrangementAction && chosen is not null;
        if (forgetArrangement is not null) {
            var title = chosen is null ? Text.L("button.remove") : Text.L("arrangements.forget", chosen);
            forgetArrangement.Content = new TextBlock { Text = title, TextWrapping = TextWrapping.Wrap };
            System.Windows.Automation.AutomationProperties.SetName(forgetArrangement, title);
            forgetArrangement.IsEnabled = !arrangementAction && chosen is not null;
        }
    }
    internal void ReconcileCardVisibility(string permanentID)
    {
        ReconcileProjectSidebar(permanentID);
        if (permanentID == CheckoutCatalog.CardID) {
            var preference = controller.Settings.WorkInFlight;
            if (wifVisibility is not null) wifVisibility.IsChecked = preference?.Enabled == true;
            if (wifCompact is not null) { wifCompact.IsChecked = preference?.Collapsed == true; wifCompact.IsEnabled = preference is not null; }
        }
        if (form is ProjectSettingsForm project && controller.Settings.Cards.FirstOrDefault(card => card.Project.Id == permanentID) is { } current)
            project.ReconcileEnabled(current);
        foreach (var pair in builtinVisibility) {
            var card = RemoteCardCatalog.Resolve(controller.Settings, pair.Key);
            if (card?.Id == permanentID) pair.Value.IsChecked = card.Enabled && RemoteCardCatalog.Available(controller.Settings, pair.Key);
        }
        if (customVisibility.TryGetValue(permanentID, out var toggle) && controller.Settings.RemoteCardList.FirstOrDefault(card => card.Id == permanentID) is { } custom)
            toggle.IsChecked = custom.Enabled;
    }
    internal async Task<bool> CloseSettingsAsync()
    {
        resizeEntry = null; geometryGeneration++;
        if (form is not null) await form.FlushAsync();
        if (form?.HasUncommittedChanges == true) { IsEnabled = true; return false; }
        allowingClose = true; form?.Dispose(); Close();
        return true;
    }

    internal SettingsWindow(DeckController controller, bool live = true, Func<SettingsRemovalRequest,bool>? confirmation = null,
        Func<RemoteAccountSettings,bool>? tokenAvailable = null)
    {
        this.controller = controller; this.live = live; this.confirmation = confirmation;
        this.tokenAvailable = tokenAvailable ?? (live ? controller.Tokens.HasToken : _ => false);
        Title = Text.L("settings.window.title");
        var workArea = GeometryWorkArea();
        var restored = SettingsGeometry.Restore(controller.Settings.SettingsWindow, workArea?.Width, workArea?.Height);
        Width = restored.Width; Height = restored.Height;
        MinWidth = SettingsGeometry.MinimumWidth; MinHeight = SettingsGeometry.MinimumHeight;
        if (workArea is { } area && double.IsFinite(area.Width) && double.IsFinite(area.Height) && area.Width >= MinWidth && area.Height >= MinHeight) MaxHeight = area.Height;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Brushes.White; FontFamily = new("Segoe UI"); FontSize = 13;
        SettingsStyles.AddTo(Resources);
        var grid = new Grid(); grid.ColumnDefinitions.Add(new() { Width = new GridLength(245) }); grid.ColumnDefinitions.Add(new());
        Resources[typeof(ListBoxItem)] = (Style)System.Windows.Markup.XamlReader.Parse("""
            <Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="ListBoxItem">
              <Setter Property="Padding" Value="8,6"/><Setter Property="Margin" Value="8,1"/>
              <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem">
                <Border x:Name="row" CornerRadius="7" Padding="{TemplateBinding Padding}" Background="Transparent"><ContentPresenter/></Border>
                <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="row" Property="Background" Value="#E0E0DF"/></Trigger>
                  <Trigger Property="IsSelected" Value="True"><Setter TargetName="row" Property="Background" Value="#3478F4"/><Setter Property="Foreground" Value="White"/></Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate></Setter.Value></Setter>
            </Style>
            """);
        VirtualizingPanel.SetScrollUnit(navigation, ScrollUnit.Pixel);
        ScrollViewer.SetCanContentScroll(navigation, false);
        ScrollViewer.SetHorizontalScrollBarVisibility(navigation, ScrollBarVisibility.Disabled);
        var sidebar = new DockPanel { Background = new SolidColorBrush(Color.FromRgb(237,237,235)) };
        search.ToolTip = Text.L("settings.search"); System.Windows.Automation.AutomationProperties.SetName(search, Text.L("settings.search"));
        search.Tag = Text.L("settings.search"); search.Height = 32; search.Template = (ControlTemplate)System.Windows.Markup.XamlReader.Parse("""
            <ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="TextBox">
              <Border Background="#F8F8F7" BorderBrush="#D3D3D1" BorderThickness="1" CornerRadius="12" Padding="10,6">
                <Grid><ScrollViewer x:Name="PART_ContentHost" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden"/><TextBlock x:Name="hint" Text="{TemplateBinding Tag}" Foreground="Gray" Visibility="Collapsed" IsHitTestVisible="False"/></Grid>
              </Border>
              <ControlTemplate.Triggers><Trigger Property="Text" Value=""><Setter TargetName="hint" Property="Visibility" Value="Visible"/></Trigger></ControlTemplate.Triggers>
            </ControlTemplate>
            """);
        var searchBox = new StackPanel { Margin = new(0,14,0,6) }; searchBox.Children.Add(search);
        DockPanel.SetDock(searchBox, Dock.Top); sidebar.Children.Add(searchBox);
        var add = new WrapPanel { Margin = new(12) };
        add.Children.Add(SettingsForm.Button(Text.L("windows.newProject"), () => SelectPageAsync("new-project")));
        add.Children.Add(SettingsForm.Button(Text.L("windows.newAccount"), () => SelectPageAsync("new-account")));
        remove = SettingsForm.Button(Text.L("settings.sidebar.remove"), RemoveSelectedAsync);
        remove.Content = new System.Windows.Shapes.Path { Data = Geometry.Parse("M 2,8 L 14,8"), Width = 14, Height = 14,
            Stroke = Brushes.Black, StrokeThickness = 1.4, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, Stretch = Stretch.Uniform };
        remove.Width = 32; remove.Height = 30; remove.Padding = new(7); remove.ToolTip = Text.L("settings.sidebar.remove");
        add.Children.Add(remove);
        DockPanel.SetDock(add, Dock.Bottom); sidebar.Children.Add(add); sidebar.Children.Add(navigation);
        geometryBanner = new Border { Background = new SolidColorBrush(Color.FromRgb(255,244,241)), Child = geometryError, Visibility = Visibility.Collapsed };
        System.Windows.Automation.AutomationProperties.SetLiveSetting(geometryError, System.Windows.Automation.AutomationLiveSetting.Polite);
        var detail = new DockPanel(); DockPanel.SetDock(geometryBanner, Dock.Top); detail.Children.Add(geometryBanner); detail.Children.Add(page);
        grid.Children.Add(sidebar); Grid.SetColumn(detail, 1); grid.Children.Add(detail); Content = grid;
        search.TextChanged += (_, _) => ReloadNavigation();
        navigation.SelectionChanged += async (_, _) => {
            if (!changing && navigation.SelectedItem is ListBoxItem item && item.Tag is Entry entry && !entry.Heading) await SelectPageAsync(entry.ID);
        };
        PreviewKeyDown += async (_, args) => {
            if (args.Handled) return;
            var modifiers = Keyboard.Modifiers;
            if ((args.Key == Key.F && modifiers == ModifierKeys.Control) ||
                (modifiers == ModifierKeys.None && navigation.IsKeyboardFocusWithin && args.Key is Key.Up or Key.Down or Key.Delete or Key.Back)) {
                args.Handled = true;
                await HandleSettingsKeyAsync(args.Key, modifiers, navigation.IsKeyboardFocusWithin);
            }
        };
        Closing += async (_, args) => {
            resizeEntry = null; geometryGeneration++;
            if (allowingClose) return;
            args.Cancel = true; IsEnabled = false;
            // Finish the native Closing callback before asking WPF to close again after autosave.
            await System.Windows.Threading.Dispatcher.Yield(System.Windows.Threading.DispatcherPriority.Background);
            await CloseSettingsAsync();
        };
        SourceInitialized += (_, _) => {
            geometrySource = HwndSource.FromHwnd(new WindowInteropHelper(this).Handle);
            geometrySource?.AddHook(GeometryHook);
        };
        StateChanged += (_, _) => { resizeEntry = null; geometryGeneration++; };
        Closed += (_, _) => {
            sidebarClosed = true; resizeEntry = null; geometryGeneration++;
            geometrySource?.RemoveHook(GeometryHook); geometrySource = null;
            form?.Dispose(); tokenDrafts.Clear(); tokenAvailability.Clear(); sidebarRows.Clear();
        };
        IsVisibleChanged += (_, args) => {
            if (args.NewValue is false) { resizeEntry = null; geometryGeneration++; }
            if (args.NewValue is true && !sidebarClosed) ReloadNavigation();
        };
        foreach (var account in controller.Settings.AccountList) RefreshTokenAvailability(account);
        ReloadNavigation(); ShowPage();
    }
    private nint GeometryHook(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message == 0x0231) {
            geometryGeneration++;
            resizeEntry = GeometryCanPersist(hwnd) ? new(ActualWidth,ActualHeight) : null;
        } else if (message == 0x0232 && resizeEntry is { } entry) {
            resizeEntry = null;
            var generation = geometryGeneration;
            var requested = new SettingsWindowGeometry(Width,Height);
            // Finish native sizing first. A subsequent hide, close, replacement,
            // state transition or programmatic size change invalidates this receipt.
            Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => {
                if (generation != geometryGeneration || !GeometryCanPersist(hwnd)
                    || Math.Abs(Width-requested.Width) > .01 || Math.Abs(Height-requested.Height) > .01) return;
                UpdateLayout();
                var size = new SettingsWindowGeometry(ActualWidth,ActualHeight);
                if (!SettingsGeometry.Valid(size) || Math.Abs(size.Width-entry.Width) < .01 && Math.Abs(size.Height-entry.Height) < .01) return;
                try {
                    if (controller.SaveSettingsWindowGeometry(this,size,hwnd)) {
                        geometryError.Text = ""; geometryBanner.Visibility = Visibility.Collapsed;
                    }
                } catch (Exception error) when (error is System.IO.IOException or UnauthorizedAccessException
                    or ArgumentException or InvalidOperationException or System.Runtime.InteropServices.ExternalException) {
                    PresentGeometryFailure(error);
                }
            }));
        }
        return 0;
    }
    internal void PresentGeometryFailure(Exception error)
    {
        if (sidebarClosed) return;
        geometryError.Text = Text.L("windows.settingsSizeSaveFailed",Text.Failure(error));
        System.Windows.Automation.AutomationProperties.SetName(geometryError,geometryError.Text);
        geometryBanner.Visibility = Visibility.Visible;
    }
    private bool GeometryCanPersist(nint hwnd) => live && !sidebarClosed && IsVisible && WindowState == WindowState.Normal
        && !Dispatcher.HasShutdownStarted && ReferenceEquals(controller.SettingsView,this) && hwnd != 0 && new WindowInteropHelper(this).Handle == hwnd;
    private static Rect? GeometryWorkArea()
    {
        try { return SystemParameters.WorkArea; }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.ExternalException or PlatformNotSupportedException) { return null; }
    }
    internal async void SelectPage(string id) => await SelectPageAsync(id);
    internal async Task<bool> HandleSettingsKeyAsync(Key key, ModifierKeys modifiers, bool sidebarFocused)
    {
        if (key == Key.F && modifiers == ModifierKeys.Control) {
            search.Focus(); search.SelectAll(); return true;
        }
        if (!sidebarFocused || modifiers != ModifierKeys.None) return false;
        if (key is Key.Delete or Key.Back) { await RemoveSelectedAsync(); return true; }
        if (key is not (Key.Up or Key.Down)) return false;
        var items = navigation.Items.OfType<ListBoxItem>().Where(item => item.IsEnabled).ToArray();
        if (items.Length == 0) return true;
        var index = Array.FindIndex(items, item => item.Tag is Entry entry && entry.ID == selected);
        var next = index < 0 ? 0 : Math.Clamp(index + (key == Key.Down ? 1 : -1), 0, items.Length - 1);
        await SelectPageAsync(((Entry)items[next].Tag).ID);
        if (navigation.SelectedItem is ListBoxItem chosen) { navigation.ScrollIntoView(chosen); navigation.UpdateLayout(); chosen.Focus(); }
        return true;
    }
    internal Task RemoveSelectedAsync() => form switch {
        ProjectSettingsForm project => project.RemoveAsync(),
        AccountSettingsForm account => account.RemoveAsync(),
        _ => Task.CompletedTask
    };
    internal async Task SelectPageAsync(string id)
    {
        if (changing) return;
        changing = true;
        try {
            if (form is not null) await form.FlushAsync();
            if (form?.HasUncommittedChanges == true) { ReloadNavigation(); return; }
            if (form is AccountSettingsForm accountForm) tokenDrafts[selected] = accountForm.TokenDraft;
            form?.Dispose(); form = null; selected = id; ShowPage(); ReloadNavigation();
        } finally { changing = false; }
    }
    internal void ReloadNavigation()
    {
        if (sidebarClosed) return;
        var focused = navigation.IsKeyboardFocusWithin;
        var focusedRow = navigation.Items.OfType<SettingsSidebarRow>().FirstOrDefault(row => row.IsKeyboardFocusWithin);
        var previous = changing; changing = true;
        try {
            var entries = Entries();
            if (selected.StartsWith("account:", StringComparison.Ordinal) || selected.StartsWith("project:", StringComparison.Ordinal)) {
                if (!entries.Any(entry => entry.ID == selected)) selected = RemovalFallback(selected);
            }
            var currentTargets = controller.Settings.AccountList.Select(account => account.CredentialTarget).ToHashSet(StringComparer.Ordinal);
            foreach (var target in tokenAvailability.Keys.Where(target => !currentTargets.Contains(target)).ToArray()) tokenAvailability.Remove(target);
            var query = search.Text.Trim();
            bool Matches(Entry entry) => query.Length == 0 || (entry.Title + " " + entry.Detail).Contains(query, StringComparison.CurrentCultureIgnoreCase);
            var desired = new List<Entry>();
            for (var index = 0; index < entries.Length; index++) {
                var entry = entries[index];
                if (entry.Hint && query.Length > 0) continue;
                if (entry.Heading ? query.Length > 0 && !entries.Skip(index + 1).TakeWhile(next => !next.Heading).Any(next => !next.Hint && Matches(next)) : !Matches(entry)) continue;
                desired.Add(entry);
            }
            var desiredIDs = desired.Select(entry => entry.ID).ToHashSet(StringComparer.Ordinal);
            var viewport = CaptureViewport(desiredIDs);
            foreach (var entry in entries) UpdateRow(entry);
            for (var index = 0; index < desired.Count; index++) {
                var row = sidebarRows[desired[index].ID];
                var oldIndex = navigation.Items.IndexOf(row);
                if (oldIndex == index) continue;
                if (oldIndex >= 0) navigation.Items.RemoveAt(oldIndex);
                navigation.Items.Insert(index, row);
            }
            while (navigation.Items.Count > desired.Count) navigation.Items.RemoveAt(navigation.Items.Count - 1);
            var configuredIDs = entries.Select(entry => entry.ID).ToHashSet(StringComparer.Ordinal);
            foreach (var id in sidebarRows.Keys.Where(id => !configuredIDs.Contains(id)).ToArray()) sidebarRows.Remove(id);
            foreach (var row in navigation.Items.OfType<SettingsSidebarRow>()) row.IsSelected = row.Tag is Entry entry && entry.ID == selected;
            RefreshSelectedPresentation(entries);
            RestoreViewport(viewport);
        } finally { changing = previous; }
        if (focused) {
            if (focusedRow is not null && navigation.Items.Contains(focusedRow)) focusedRow.Focus(); else navigation.Focus();
        }
    }
    internal void ReconcileProjectSidebar(string permanentID)
    {
        if (sidebarClosed) return;
        if (!Dispatcher.CheckAccess()) { Dispatcher.BeginInvoke(new Action(() => ReconcileProjectSidebar(permanentID))); return; }
        var card = controller.Settings.Cards.FirstOrDefault(card => card.Project.Id == permanentID);
        if (card is null) return;
        if (sidebarRows.TryGetValue("project:" + permanentID, out var row)) UpdateRow(ProjectEntry(card), row);
        RefreshSelectedPresentation();
    }
    internal void ReconcileAccountSidebar(string accountID, bool refreshAvailability = false)
    {
        if (sidebarClosed) return;
        var captured = controller.Settings.AccountList.FirstOrDefault(account => account.Id == accountID);
        if (!Dispatcher.CheckAccess()) {
            var target = captured?.CredentialTarget;
            Dispatcher.BeginInvoke(new Action(() => {
                if (sidebarClosed || controller.Settings.AccountList.FirstOrDefault(account => account.Id == accountID)?.CredentialTarget != target) return;
                ReconcileAccountSidebar(accountID, refreshAvailability);
            })); return;
        }
        if (refreshAvailability && captured is not null) RefreshTokenAvailability(captured);
        ReloadNavigation();
    }
    private void RefreshTokenAvailability(RemoteAccountSettings account)
    {
        if (sidebarClosed) return;
        var present = false;
        try { present = tokenAvailable(account); }
        catch (Exception error) when (error is System.IO.IOException or System.ComponentModel.Win32Exception or ArgumentException
            or InvalidOperationException or UnauthorizedAccessException or System.Runtime.InteropServices.ExternalException or PlatformNotSupportedException) { }
        if (!sidebarClosed && controller.Settings.AccountList.FirstOrDefault(current => current.Id == account.Id)?.CredentialTarget == account.CredentialTarget)
            tokenAvailability[account.CredentialTarget] = present;
    }
    private Entry[] Entries()
    {
        var accounts = SettingsSidebarOrdering.Accounts(controller.Settings.AccountList);
        var projects = SettingsSidebarOrdering.Projects(controller.Settings.Cards);
        return new[] {
            new Entry("general", Text.L("settings.general.title"), Text.L("settings.language") + " " + Text.L("settings.general.startAtLogin"), Kind: "general"),
            new Entry("deck", Text.L("settings.deck.title"), Text.L("settings.deck.position") + " " + Text.L("menu.arrangements"), Kind: "deck"),
            new Entry("cards", Text.L("settings.cards.title"), Text.L("windows.refreshInterval") + " GitHub GitLab " + Text.L("card.title.workInFlight"), Kind: "cards"),
            new Entry("notifications", Text.L("settings.notifications.title"), Text.L("settings.notifications.subtitle"), Kind: "notifications"),
            new Entry("accounts", Text.L("settings.sidebar.accounts"), "", Heading: true)
        }.Concat(accounts.Select(AccountEntry))
            .Concat(accounts.Length == 0 ? new[] { new Entry("accounts:empty", Text.L("settings.sidebar.empty"), "", Hint: true) } : [])
            .Append(new Entry("projects", Text.L("settings.sidebar.projects"), "", Heading: true))
            .Concat(projects.Select(ProjectEntry))
            .Concat(projects.Length == 0 ? new[] { new Entry("projects:empty", Text.L("settings.sidebar.empty"), "", Hint: true) } : []).ToArray();
    }
    private Entry AccountEntry(RemoteAccountSettings account)
    {
        var present = tokenAvailability.TryGetValue(account.CredentialTarget, out var available) && available;
        var detail = account.Provider + " " + account.Endpoint;
        return new("account:" + account.Id, account.Label, present ? detail : Text.L("settings.list.noToken", detail),
            Kind: account.Provider, Dimmed: !account.Enabled, Dot: present ? null : CardTheme.Amber, Module: account.Provider);
    }
    private Entry ProjectEntry(CardSettings card)
    {
        var owner = controller.AllLocalViews.FirstOrDefault(owner => owner.Reference.Id == card.Project.Id);
        var activity = SidebarProjectActivity.None;
        if (owner is not null && !owner.SidebarOwnerClosed && (owner.Latest is null || owner.Latest.ProjectID == card.Project.Id)
            && JsonSerializer.Serialize(owner.Reference with { Title = card.Title }, WorkerProtocol.Json)
                == JsonSerializer.Serialize(card.Project with { Title = card.Title }, WorkerProtocol.Json)) activity = owner.SidebarActivity;
        return new("project:" + card.Project.Id, card.Title, card.Project.Kind + " " + card.Project.Distribution + " " + card.Project.Path,
            Kind: BrandMarks.ProjectKind(card.Project.Kind, card.Project.Subtitle, card.Project.StartCommand), Dimmed: !card.Enabled,
            Dot: activity == SidebarProjectActivity.Running ? CardTheme.Green : activity == SidebarProjectActivity.Busy ? CardTheme.Amber : null, Module: card.Project.Kind);
    }
    private void UpdateRow(Entry entry, SettingsSidebarRow? existing = null)
    {
        if (existing is null && !sidebarRows.TryGetValue(entry.ID, out existing)) {
            existing = new SettingsSidebarRow { Style = (Style)Resources[typeof(ListBoxItem)] }; sidebarRows.Add(entry.ID, existing);
        }
        existing.Tag = entry;
        existing.Update(entry.Title, entry.Detail, entry.Kind, entry.Dimmed, entry.Dot, entry.Heading, entry.Hint);
    }
    private void RefreshSelectedPresentation(Entry[]? entries = null)
    {
        var chosen = (entries ?? Entries()).FirstOrDefault(entry => entry.ID == selected && !entry.Heading && !entry.Hint);
        Title = chosen is null ? Text.L("settings.window.title") : Text.L("settings.window.titleFor", chosen.Title);
        remove.IsEnabled = selected.StartsWith("project:", StringComparison.Ordinal) && controller.Settings.Cards.Any(card => "project:" + card.Project.Id == selected) ||
            selected.StartsWith("account:", StringComparison.Ordinal) && controller.Settings.AccountList.Any(account => "account:" + account.Id == selected);
    }
    private sealed record Viewport(ScrollViewer Scroll, double Offset, SettingsSidebarRow? Anchor, double AnchorTop);
    private Viewport? CaptureViewport(HashSet<string> surviving)
    {
        var scroll = VisualDescendant<ScrollViewer>(navigation);
        if (scroll is null) return null;
        foreach (var row in navigation.Items.OfType<SettingsSidebarRow>().Where(row => row.Tag is Entry entry && surviving.Contains(entry.ID))) {
            if (row.ActualHeight <= 0 || PresentationSource.FromVisual(row) is null) continue;
            var top = row.TranslatePoint(new(0,0), scroll).Y;
            if (top + row.ActualHeight > 0 && top < scroll.ViewportHeight) return new(scroll, scroll.VerticalOffset, row, top);
        }
        return new(scroll, scroll.VerticalOffset, null, 0);
    }
    private void RestoreViewport(Viewport? viewport)
    {
        if (viewport is null) return;
        navigation.UpdateLayout();
        var offset = viewport.Offset;
        if (viewport.Anchor is { } anchor && navigation.Items.Contains(anchor) && PresentationSource.FromVisual(anchor) is not null)
            offset = viewport.Scroll.VerticalOffset + anchor.TranslatePoint(new(0,0), viewport.Scroll).Y - viewport.AnchorTop;
        viewport.Scroll.ScrollToVerticalOffset(Math.Clamp(offset, 0, viewport.Scroll.ScrollableHeight));
    }
    private static T? VisualDescendant<T>(DependencyObject source) where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(source); index++) {
            var child = VisualTreeHelper.GetChild(source, index);
            if (child is T found) return found;
            if (VisualDescendant<T>(child) is { } nested) return nested;
        }
        return null;
    }
    private void ShowPage()
    {
        builtinVisibility.Clear(); customVisibility.Clear();
        arrangementName = null; arrangements = null; saveArrangement = null; applyArrangement = null; forgetArrangement = null;
        deckFloating = null; deckLocked = null; wifVisibility = null; wifCompact = null;
        if (selected.StartsWith("project:", StringComparison.Ordinal) || selected == "new-project") {
            form = new ProjectSettingsForm(controller, controller.Settings.Cards.FirstOrDefault(card => "project:" + card.Project.Id == selected), live, id => { selected = id.Length == 0 ? RemovalFallback(selected) : "project:" + id; ReloadNavigation(); if (id.Length == 0) { form?.Dispose(); form = null; ShowPage(); } }, confirmation: confirmation); page.Content = form;
        } else if (selected.StartsWith("account:", StringComparison.Ordinal) || selected.StartsWith("new-account", StringComparison.Ordinal)) {
            var draftKey = selected;
            var accountForm = new AccountSettingsForm(controller, controller.Settings.AccountList.FirstOrDefault(account => "account:" + account.Id == selected), live, id => {
                if (id.Length == 0 || draftKey.StartsWith("new-account", StringComparison.Ordinal)) tokenDrafts.Remove(draftKey);
                if (id.Length > 0 && controller.Settings.AccountList.FirstOrDefault(account => account.Id == id) is { } committed
                    && !tokenAvailability.ContainsKey(committed.CredentialTarget)) ReconcileAccountSidebar(id, refreshAvailability: true);
                selected = id.Length == 0 ? RemovalFallback(selected) : "account:" + id; ReloadNavigation();
                if (id.Length == 0) { form?.Dispose(); form = null; ShowPage(); }
            }, selected == "new-account:gitlab" ? "gitlab" : "github", confirmation,
                credentialChanged: id => ReconcileAccountSidebar(id, refreshAvailability: true));
            accountForm.TokenDraft = tokenDrafts.TryGetValue(draftKey, out var draft) ? draft : ""; form = accountForm; page.Content = form;
        } else page.Content = selected switch { "deck" => DeckPage(), "cards" => CardsPage(), "notifications" => NotificationSettingsWindow.CreateContent(controller), _ => GeneralPage() };
        page.ScrollToTop();
    }
    private string RemovalFallback(string previous)
    {
        var module = sidebarRows.TryGetValue(previous, out var row) && row.Tag is Entry entry ? entry.Module : "";
        if (previous.StartsWith("account:", StringComparison.Ordinal)) {
            var next = SettingsSidebarOrdering.Accounts(controller.Settings.AccountList).FirstOrDefault(account => account.Provider == module);
            if (next is not null) return "account:" + next.Id;
        } else if (previous.StartsWith("project:", StringComparison.Ordinal)) {
            var next = SettingsSidebarOrdering.Projects(controller.Settings.Cards).FirstOrDefault(card => card.Project.Kind == module);
            if (next is not null) return "project:" + next.Project.Id;
        }
        return "general";
    }
    private StackPanel GeneralPage()
    {
        var panel = SettingsForm.Page(Text.L("settings.general.title")); SettingsForm.Note(panel, Text.L("windows.autosave"));
        var choices = new[] { new Choice("system", Text.L("settings.language.system")), new("en", "English"), new("ru", "Русский"), new("de", "Deutsch"), new("es", "Español"), new("fr", "Français"), new("it", "Italiano") };
        var language = new ComboBox { ItemsSource = choices, SelectedItem = choices.Single(choice => choice.ID == controller.Settings.Language), MaxWidth = 300, HorizontalAlignment = HorizontalAlignment.Left };
        SettingsForm.Field(panel, Text.L("settings.language"), language);
        language.SelectionChanged += async (_, _) => { if (live && language.SelectedItem is Choice choice) await controller.RunMenuAsync(() => controller.SaveSettingsAsync(current => current with { Language = choice.ID })); };
        var startup = SettingsForm.Toggle(Text.L("settings.general.startAtLogin"), live && controller.StartsAtLogin); panel.Children.Add(startup);
        startup.Click += async (_, _) => { if (live) await controller.RunMenuAsync(() => { controller.SetStartAtLogin(startup.IsChecked == true); return Task.CompletedTask; }); };
        SettingsForm.Section(panel, Text.L("settings.general.updates"));
        var version = System.Reflection.Assembly.GetExecutingAssembly().GetCustomAttributes(typeof(System.Reflection.AssemblyInformationalVersionAttribute), false).Cast<System.Reflection.AssemblyInformationalVersionAttribute>().First().InformationalVersion;
        SettingsForm.Note(panel, "DevDeck " + version); var result = SettingsForm.Note(panel, "");
        panel.Children.Add(SettingsForm.Button(Text.L("button.checkNow"), async () => {
            if (!live) return;
            var runtime = "win-" + System.Runtime.InteropServices.RuntimeInformation.OSArchitecture.ToString().ToLowerInvariant();
            var update = await WindowsUpdateCheck.CheckAsync(version, runtime);
            result.Text = update is null ? Text.L("windows.noUpdate") : Text.L("windows.updateAvailable", update.Version);
            if (update is not null) BrowserLaunch.Open("system", null, update.PageURL);
        })); return panel;
    }
    private StackPanel DeckPage()
    {
        var panel = SettingsForm.Page(Text.L("settings.deck.title")); SettingsForm.Note(panel, Text.L("settings.deck.subtitle"));
        var floating = SettingsForm.Toggle(Text.L("settings.deck.place.floating"), controller.Settings.Floating);
        var locked = SettingsForm.Toggle(Text.L("settings.deck.lock"), controller.Settings.Locked); panel.Children.Add(floating); panel.Children.Add(locked);
        deckFloating = floating; deckLocked = locked;
        floating.Click += async (_, _) => { if (live) {
            var value = floating.IsChecked == true;
            try { await controller.RunMenuAsync(() => { controller.SetFloating(value); return Task.CompletedTask; }); }
            finally { ReconcileDeckModes(); }
        } };
        locked.Click += async (_, _) => { if (live) {
            var value = locked.IsChecked == true;
            try { await controller.RunMenuAsync(() => { controller.SetLocked(value); return Task.CompletedTask; }); }
            finally { ReconcileDeckModes(); }
        } };
        SettingsForm.Note(panel, Text.L("windows.showCards") + " · Ctrl+Alt+Space"); SettingsForm.Section(panel, Text.L("menu.arrangements"));
        var name = new TextBox { MaxLength = 128, ToolTip = Text.L("arrangements.name.placeholder") }; arrangementName = name;
        SettingsForm.Note(panel, Text.L("arrangements.save.detail")); SettingsForm.Field(panel, Text.L("account.name"), name);
        var choices = new ComboBox { ItemsSource = controller.Settings.ArrangementList.Select(item => item.Name).ToArray() }; arrangements = choices;
        saveArrangement = ArrangementButton(Text.L("button.save"), "arrangement.save", () => {
            var raw = name.Text;
            if (!raw.Any(char.IsControl) && raw.Trim().Length is >0 and <=128) controller.SaveArrangement(raw);
            return Task.CompletedTask;
        }); panel.Children.Add(saveArrangement);
        SettingsForm.Field(panel, Text.L("menu.arrangements"), choices);
        var actions = new WrapPanel();
        applyArrangement = ArrangementButton(Text.L("button.chooseShort"), "arrangement.apply", () => choices.SelectedItem is string chosen ? controller.ApplyArrangementAsync(chosen) : Task.CompletedTask);
        forgetArrangement = ArrangementButton(Text.L("button.remove"), "arrangement.forget", () => {
            if (choices.SelectedItem is string chosen) controller.ForgetArrangement(chosen);
            return Task.CompletedTask;
        }); actions.Children.Add(applyArrangement); actions.Children.Add(forgetArrangement); panel.Children.Add(actions);
        name.TextChanged += (_, _) => RefreshArrangementButtons(); choices.SelectionChanged += (_, _) => RefreshArrangementButtons();
        name.KeyDown += (_, args) => {
            if (args.Key != Key.Return || Keyboard.Modifiers != ModifierKeys.None) return;
            args.Handled = true;
            if (saveArrangement?.IsEnabled == true) saveArrangement.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        };
        RefreshArrangementButtons(); return panel;
    }
    private Button ArrangementButton(string title, string tag, Func<Task> action)
    {
        var button = new Button { Content = new TextBlock { Text = title, TextWrapping = TextWrapping.Wrap }, Tag = tag,
            Padding = new(12,7,12,7), Margin = new(0,6,8,4), HorizontalAlignment = HorizontalAlignment.Left };
        System.Windows.Automation.AutomationProperties.SetName(button, title);
        button.Click += async (_, _) => {
            if (!live || arrangementAction || !button.IsEnabled) return;
            arrangementAction = true; RefreshArrangementButtons();
            try { await controller.RunMenuAsync(action); }
            finally { arrangementAction = false; ReconcileArrangements(); }
        };
        return button;
    }
    private StackPanel CardsPage()
    {
        var panel = SettingsForm.Page(Text.L("settings.cards.title")); SettingsForm.Note(panel, Text.L("windows.autosave"));
        var intervals = new[] { 60, 120, 300, 600 };
        var interval = new ComboBox { ItemsSource = intervals.Select(value => new Choice(value.ToString(), Text.L("windows.everySeconds", value))).ToArray(), SelectedIndex = Array.IndexOf(intervals, controller.Settings.RefreshSeconds) };
        SettingsForm.Field(panel, Text.L("windows.refreshInterval"), interval);
        interval.SelectionChanged += async (_, _) => { if (live && interval.SelectedItem is Choice choice) await controller.RunMenuAsync(() => controller.SaveSettingsAsync(current => current with { RefreshSeconds = int.Parse(choice.ID) })); };
        SettingsForm.Section(panel, Text.L("menu.cards"));
        foreach (var descriptor in RemoteCardCatalog.All) {
            var card = RemoteCardCatalog.Resolve(controller.Settings, descriptor.Kind);
            var enabled = SettingsForm.Toggle(Text.L(descriptor.TitleKey), card?.Enabled == true && RemoteCardCatalog.Available(controller.Settings, descriptor.Kind));
            enabled.Tag = descriptor.Kind; builtinVisibility[descriptor.Kind] = enabled; panel.Children.Add(enabled);
            enabled.Click += async (_, _) => { if (live) {
                var visible = enabled.IsChecked == true;
                try { await controller.RunMenuAsync(() => controller.SetRemoteVisibleAsync(descriptor.Kind, visible)); }
                finally { ReconcileCardVisibility(RemoteCardCatalog.Resolve(controller.Settings, descriptor.Kind)?.Id ?? descriptor.Id); }
            } };
            if (!RemoteCardCatalog.Available(controller.Settings, descriptor.Kind)) {
                panel.Children.Add(SettingsForm.Button(Text.L("windows.addAccount") + " · " + (descriptor.Provider == "gitlab" ? "GitLab" : "GitHub"), () => SelectPageAsync("new-account:" + descriptor.Provider)));
            }
            if (card is not null) AddScope(card);
        }
        var work = SettingsForm.Toggle(Text.L("card.title.workInFlight"),controller.Settings.WorkInFlight?.Enabled == true);
        work.Tag = CheckoutCatalog.CardID; work.IsEnabled = controller.WorkInFlightAvailable; wifVisibility = work; panel.Children.Add(work);
        if (!work.IsEnabled) panel.Children.Add(new TextBlock { Text=Text.L("windows.wif.conflict"),TextWrapping=TextWrapping.Wrap,Margin=new(18,0,0,8) });
        work.Click += async (_,_) => { if (live) {
            var visible = work.IsChecked == true;
            try { await controller.RunMenuAsync(() => controller.SetWIFVisibleAsync(visible)); }
            finally { ReconcileCardVisibility(CheckoutCatalog.CardID); }
        } };
        var workScope = new StackPanel { Margin = new(18,0,0,8) };
        var workCompact = SettingsForm.Toggle(Text.L("windows.compactCard"),controller.Settings.WorkInFlight?.Collapsed == true);
        workCompact.IsEnabled = controller.Settings.WorkInFlight is not null; wifCompact = workCompact; workScope.Children.Add(workCompact); panel.Children.Add(workScope);
        workCompact.Click += async (_,_) => { if (live) {
            try { await controller.RunMenuAsync(() => { controller.SetCardCollapsed(CheckoutCatalog.CardID,workCompact.IsChecked == true); return Task.CompletedTask; }); }
            finally { ReconcileCardVisibility(CheckoutCatalog.CardID); }
        } };
        foreach (var card in controller.Settings.RemoteCardList.Where(card => RemoteCardCatalog.Resolve(controller.Settings, card.Kind)?.Id != card.Id)) {
            var enabled = SettingsForm.Toggle(card.Title, card.Enabled); enabled.Tag = card.Id; customVisibility[card.Id] = enabled; panel.Children.Add(enabled);
            enabled.Click += async (_, _) => { if (live) {
                var visible = enabled.IsChecked == true;
                try { await controller.RunMenuAsync(() => controller.SetCardVisibleAsync(card.Id, visible)); }
                finally { ReconcileCardVisibility(card.Id); }
            } };
            AddScope(card);
            panel.Children.Add(SettingsForm.Button(Text.L("windows.removeCard"), async () => { if (live) { await controller.SaveSettingsAsync(current => current with { RemoteCards = current.RemoteCardList.Where(item => item.Id != card.Id).ToArray() }); ShowPage(); } }));
        }
        return panel;
        void AddScope(RemoteCardSettings card) {
            var scope = new StackPanel { Margin = new(18,0,0,8) };
            var compact = SettingsForm.Toggle(Text.L("windows.compactCard"),card.Collapsed); scope.Children.Add(compact);
            compact.Click += async (_,_) => { if (live) await controller.RunMenuAsync(() => {
                if (!controller.SetCardCollapsed(card.Id,compact.IsChecked == true)) compact.IsChecked = controller.Settings.RemoteCardList.Single(item => item.Id == card.Id).Collapsed;
                return Task.CompletedTask;
            }); };
            var provider = card.Kind == "mergeRequests" ? "gitlab" : "github";
            var all = SettingsForm.Toggle(Text.L("windows.allAccounts"), card.UseAllAccounts); scope.Children.Add(all);
            all.Click += async (_, _) => { if (live) {
                await controller.RunMenuAsync(() => controller.SaveSettingsAsync(current => current with { RemoteCards = current.RemoteCardList.Select(item =>
                    item.Id == card.Id ? item with { UseAllAccounts = all.IsChecked == true } : item).ToArray() }));
                ShowPage();
            } };
            foreach (var account in controller.Settings.AccountList.Where(account => account.Provider == provider)) {
                var selected = SettingsForm.Toggle(account.Label,card.AccountIDs.Contains(account.Id)); selected.IsEnabled = !card.UseAllAccounts; scope.Children.Add(selected);
                selected.Click += async (_, _) => { if (live) await controller.RunMenuAsync(async () => {
                    await controller.SaveSettingsAsync(current => current with { RemoteCards = current.RemoteCardList.Select(item => {
                        if (item.Id != card.Id) return item;
                        var ids = selected.IsChecked == true ? item.AccountIDs.Append(account.Id).Distinct(StringComparer.Ordinal).ToArray() : item.AccountIDs.Where(id => id != account.Id).ToArray();
                        if (ids.Length == 0) { selected.IsChecked = true; throw new InvalidOperationException(Text.L("windows.validationAccount")); }
                        return item with { AccountIDs = ids, UseAllAccounts = false };
                    }).ToArray() });
                }); };
            }
            var distribution = new ComboBox { ItemsSource = controller.Settings.Workers.Select(worker => worker.Distribution).ToArray(), SelectedItem = card.Distribution };
            SettingsForm.Field(scope, Text.L("windows.distribution"), distribution);
            distribution.SelectionChanged += async (_, _) => { if (live && distribution.SelectedItem is string distro)
                await controller.RunMenuAsync(() => controller.SaveSettingsAsync(current => current with { RemoteCards = current.RemoteCardList.Select(item => item.Id == card.Id ? item with { Distribution = distro } : item).ToArray() })); };
            panel.Children.Add(new Expander { Header = Text.L("windows.advanced"),Content = scope,Margin = new(0,0,0,8) });
        }
    }
}
