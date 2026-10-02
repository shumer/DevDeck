using System;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed class RemoteCard : Window
{
    private readonly DeckController controller;
    private readonly RemoteCardSettings settings;
    private readonly bool live;
    private readonly Func<CancellationToken,Task<RemoteSnapshot>>? snapshotReader;
    private readonly TextBlock state = new() { Text = Text.L("windows.connecting"), FontSize = 24, FontWeight = FontWeights.SemiBold, Margin = new(0, 10, 0, 10) };
    private readonly TextBlock footer = new() { Foreground = CardTheme.Quiet, FontSize = 10, TextWrapping = TextWrapping.Wrap, Margin = new(0, 9, 0, 12) };
    private readonly StackPanel rows = new();
    private readonly StackPanel body = new();
    private readonly Grid healthBar = new() { Height = 3, Margin = new(0,0,0,5) };
    private readonly TextBlock foldedNote = new() { FontSize = 10, Foreground = CardTheme.Secondary, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly WrapPanel actions = new();
    private readonly Button? markRest, markAll;
    private readonly Button cancel;
    private CancellationTokenSource? mutation;
    private readonly TextBlock timestamp = new() { Text = "--:--:--", Foreground = CardTheme.Quiet, FontFamily = new("Consolas"), FontSize = 10, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock verdict = new() { FontSize = 11, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
    private readonly CancellationTokenSource lifetime = new();
    private Task? refreshing;
    private RemoteSnapshot? latest;
    private RemoteSnapshot? sourceSnapshot;
    private InboxReadTarget? pendingInboxRead;
    private bool closed;
    private bool deckVisible = true;
    private bool floating;
    private nint handle;
    private bool collapsed;
    private bool mutating;
    private bool expanded;
    private readonly Button expand;
    private readonly Button refreshButton;
    private readonly Button collapseButton;
    private readonly MenuItem compactMenu = new();
    private bool presentingMutation;
    private Window? listWindow;
    private readonly StackPanel fullRows = new() { Margin = new(18) };
    internal RemoteSnapshot? Latest => latest;
    internal RemoteSnapshot? AuthorizationSnapshot => sourceSnapshot;
    internal RemoteCardSettings Configuration => settings;
    internal bool IsClosed => closed;
    internal InboxReadTarget? PendingInboxRead => pendingInboxRead;
    internal string CardID => settings.Id;
    internal bool IsMutating => mutating || presentingMutation;
    internal bool DeckVisible => deckVisible;
    internal RemoteAccountFailure[] LastRefreshFailures { get; private set; } = [];
    internal double? LastServerHint { get; private set; }

    internal RemoteCard(DeckController controller, RemoteCardSettings settings, bool live = true, Func<CancellationToken,Task<RemoteSnapshot>>? snapshotReader = null)
    {
        this.live = live; this.snapshotReader = snapshotReader;
        this.controller = controller; this.settings = settings; collapsed = settings.Collapsed;
        Title = "DevDeck · " + settings.Title; Width = CardTheme.Width; SizeToContent = SizeToContent.Height;
        Left = settings.X; Top = settings.Y; Foreground = CardTheme.Ink; FontFamily = new FontFamily("Segoe UI");
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; AllowsTransparency = true;
        Background = Brushes.Transparent; ShowInTaskbar = false; ShowActivated = false;
        var panel = new StackPanel { Margin = new(14, 12, 14, 12) };
        var header = new DockPanel();
        collapseButton = CardTheme.Button(Text.L("menu.card.collapse"), () => { ToggleCollapsed(); return Task.CompletedTask; }, "collapse", iconOnly:true);
        collapseButton.Margin = new(0); collapseButton.Background = Brushes.Transparent;
        DockPanel.SetDock(collapseButton,Dock.Right); header.Children.Add(collapseButton);
        var accounts = CardTheme.Button(Text.L("windows.accounts"), () => { controller.ShowSettings(settings.AccountIDs.Length == 1 ? "account:" + settings.AccountIDs[0] : "cards"); return Task.CompletedTask; }, "settings", iconOnly: true);
        accounts.Background = Brushes.Transparent; accounts.Margin = new(0);
        DockPanel.SetDock(accounts, Dock.Right); header.Children.Add(accounts);
        var dashboard = CardTheme.Button(Text.L("card.action.openInBrowser"), () => { OpenDashboard(); return Task.CompletedTask; }, "site", iconOnly: true);
        dashboard.Margin = new(0); DockPanel.SetDock(dashboard,Dock.Right); header.Children.Add(dashboard);
        refreshButton = CardTheme.Button(Text.L("menu.refresh"), RefreshAsync);
        refreshButton.Content = timestamp; refreshButton.Padding = new(0);
        refreshButton.Background = Brushes.Transparent; DockPanel.SetDock(refreshButton, Dock.Right); header.Children.Add(refreshButton);
        var title = CardTheme.Heading(settings.Title.ToUpperInvariant());
        var brand = BrandMarks.Create(settings.Kind == "mergeRequests" ? "gitlab" : "github");
        DockPanel.SetDock(brand,Dock.Left); header.Children.Add(brand); title.Margin = new(8,0,8,0);
        title.MouseLeftButtonDown += (_, e) => {
            if (e.ClickCount == 2) { ToggleCollapsed(); return; }
            if (e.LeftButton == MouseButtonState.Pressed && !controller.Settings.Locked) { DragMove(); controller.SavePosition(settings.Id, Left, Top); }
        };
        var titleGroup = new StackPanel { VerticalAlignment = VerticalAlignment.Center }; titleGroup.Children.Add(title); titleGroup.Children.Add(foldedNote); header.Children.Add(titleGroup);
        panel.Children.Add(header); panel.Children.Add(body);
        var headline = new DockPanel(); DockPanel.SetDock(verdict,Dock.Right); headline.Children.Add(verdict); headline.Children.Add(state);
        body.Children.Add(headline); body.Children.Add(healthBar); body.Children.Add(rows); body.Children.Add(footer);
        expand = CardTheme.Button(Text.L("card.showMore", 5), () => { expanded = !expanded; if (latest is { } snapshot) RenderSnapshot(snapshot); return Task.CompletedTask; });
        expand.Visibility = Visibility.Collapsed; actions.Children.Add(expand);
        actions.Children.Add(CardTheme.Button(Text.L("windows.allItems"), () => { ShowAll(); return Task.CompletedTask; }));
        if (settings.Kind == "inbox") {
            markRest = CardTheme.Button(Text.L("windows.markRest"), () => MarkBulkAsync(false)); actions.Children.Add(markRest);
            markAll = CardTheme.Button(Text.L("card.inbox.readAll.capped"), () => MarkBulkAsync(true)); actions.Children.Add(markAll);
        }
        cancel = CardTheme.Button(Text.L("button.cancel"), () => { mutation?.Cancel(); return Task.CompletedTask; }); cancel.Visibility = Visibility.Collapsed; body.Children.Add(cancel);
        body.Children.Add(actions);
        Content = CardTheme.Frame(panel);
        SetCollapsed(collapsed);
        ContextMenu = new ContextMenu();
        compactMenu.Tag = "compact"; compactMenu.Click += (_,_) => ToggleCollapsed();
        ContextMenu.Opened += (_,_) => PopulateContextMenu();
        PopulateContextMenu();
        SourceInitialized += (_, _) =>
        {
            handle = new WindowInteropHelper(this).Handle;
            HwndSource.FromHwnd(handle)?.AddHook((nint hwnd, int message, nint wparam, nint lparam, ref bool handled) =>
            { if (message == 0x21 && !floating) { handled = true; return 3; } return 0; });
            ApplyMode(controller.Settings.Floating);
        };
        Deactivated += (_, _) => { if (!floating) ApplyMode(false); };
        Closed += (_, _) => { closed = true; lifetime.Cancel(); mutation?.Cancel(); listWindow?.Close(); CloseTransientMenus(); };
        Loaded += (_, _) => { if (deckVisible) DesktopRecovery.EnsureReachable(this); };
    }
    private void PopulateContextMenu()
    {
        if (ContextMenu is not { } menu) return;
        menu.Items.Clear();
        menu.Items.Add(new MenuItem { Header=controller.Settings.RemoteCardList.FirstOrDefault(card => card.Id == settings.Id)?.Title ?? settings.Title, IsEnabled=false, Tag="header" });
        compactMenu.Header = Text.L(collapsed ? "menu.card.showWhole" : "menu.card.collapse"); compactMenu.IsEnabled = !closed && !IsMutating; menu.Items.Add(compactMenu);
        void LabelItem(string tag,string label,Func<Task> action,bool enabled=true) {
            var item = new MenuItem { Header=label, Tag=tag, IsEnabled=enabled && !closed };
            item.Click += async (_,_) => await controller.RunMenuAsync(action); menu.Items.Add(item);
        }
        void Item(string tag,string key,Func<Task> action,bool enabled=true) => LabelItem(tag,Text.L(key),action,enabled);
        if (settings.Kind == "inbox" && latest is { Total:>0 } snapshot) {
            var allAvailable = !IsMutating && snapshot.Failures.Length == 0 && RemotePresentation.ReadCutoffs(snapshot).Count > 0;
            var restAvailable = allAvailable && (snapshot.Capped || snapshot.Rows.Any(row => row.IsUnread && row.Health == "ready"));
            var allLabel = snapshot.Capped ? Text.L("card.inbox.readAll.capped") : Text.LN("card.inbox.readAll",snapshot.Total);
            LabelItem("readRest",restAvailable ? Text.LN("card.inbox.readRest",snapshot.ActionableCount) : allLabel,
                () => MarkBulkAsync(!restAvailable),allAvailable);
            LabelItem("readAll",allLabel,() => MarkBulkAsync(true),allAvailable);
        }
        Item("hide","menu.card.hide",() => controller.SetCardVisibleAsync(settings.Id,false));
        Item("settings","menu.card.settings",() => { controller.ShowSettings(settings.AccountIDs.Length == 1 ? "account:" + settings.AccountIDs[0] : "cards"); return Task.CompletedTask; });
        menu.Items.Add(new Separator());
        var currentAccounts = controller.Settings.AccountList.Where(account => account.Enabled && settings.AccountIDs.Contains(account.Id)).ToArray();
        Item("dashboard","card.action.openInBrowser",() => { OpenDashboard(); return Task.CompletedTask; },currentAccounts.Length > 0);
        Item("allItems","windows.allItems",() => { ShowAll(); return Task.CompletedTask; },latest is not null);
        foreach (var account in currentAccounts) {
            var item = new MenuItem { Header=account.Label, Tag="account:" + account.Id, IsEnabled=!closed };
            item.Click += (_,_) => OpenDashboard(account); menu.Items.Add(item);
        }
        menu.Items.Add(new Separator());
        var locked = new MenuItem { Header=Text.L("menu.lock"), Tag="lock", IsCheckable=true, IsChecked=controller.Settings.Locked, IsEnabled=!closed };
        locked.Click += (_,_) => controller.SetLocked(!controller.Settings.Locked); menu.Items.Add(locked);
        Item("tidy","menu.tidy",() => controller.ArrangeAsync());
        Item("refresh","menu.refresh",controller.RefreshAllAsync);
    }
    private void CloseTransientMenus()
    {
        if (ContextMenu is not null) ContextMenu.IsOpen = false;
        foreach (var row in rows.Children.OfType<FrameworkElement>().Concat(fullRows.Children.OfType<FrameworkElement>()))
            if (row.ContextMenu is not null) row.ContextMenu.IsOpen = false;
    }
    internal void SetDeckVisible(bool value)
    {
        if (closed) return;
        var showing = value && (!deckVisible || !IsVisible);
        deckVisible = value;
        if (!value) { CloseTransientMenus(); if (IsVisible) Hide(); return; }
        if (!IsVisible) Show();
        ApplyMode(controller.Settings.Floating);
        if (live && showing) controller.ScheduleSharedRefresh();
    }
    internal Task RefreshAsync() => closed || !deckVisible || IsMutating ? Task.CompletedTask : refreshing is { IsCompleted: false } ? refreshing : refreshing = ReadAsync();
    private async Task ReadAsync()
    {
        try { var value = await (snapshotReader is null ? controller.FetchRemoteAsync(settings, lifetime.Token) : snapshotReader(lifetime.Token)); if (!closed) ApplySnapshot(value); }
        catch (OperationCanceledException) { }
        catch (Exception error) when (error is System.IO.IOException or InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            if (closed) return;
            LastRefreshFailures = error is WorkerException { Remote: { Failures.Length:>0 } failed } ? failed.Failures : [new(null,"other")];
            LastServerHint = null;
            ApplyFailure(error);
        }
    }
    internal void ApplySnapshot(RemoteSnapshot value)
    {
        LastRefreshFailures = value.Failures.ToArray(); LastServerHint = value.PollIntervalSeconds;
        sourceSnapshot = value;
        RenderSnapshot(MaskPendingRead(value),checkedRead:true);
    }
    private void RenderSnapshot(RemoteSnapshot value,bool checkedRead=false)
    {
        latest = value;
        if(checkedRead)timestamp.Text = DateTime.Now.ToString("HH:mm:ss");
        verdict.Text = RemoteWords.Pill(value); verdict.Foreground = value.Blocked > 0 ? CardTheme.Red : value.ReviewCount > 0 || value.ActionableCount > 0 ? CardTheme.Amber : CardTheme.Green;
        foldedNote.Text = RemoteWords.Collapsed(value) + (value.Capped ? "+" : ""); foldedNote.ToolTip = foldedNote.Text;
        state.Text = value.Kind == "actions" ? value.RepositoryCount == 0 ? RemoteWords.Quiet(value) : value.Total == 0 ? Text.LN("card.actions.quiet.title",value.WindowDays) : (value.SuccessRate is { } rate ? Math.Round(rate * 100).ToString() + " " + Text.L("card.actions.successWindow",value.WindowDays) : Text.L("card.na"))
            : Text.L("windows.items", value.Total + (value.Capped ? "+" : ""));
        state.Foreground = CardTheme.Ink;
        state.FontSize = value.Kind == "actions" && (value.Total == 0 || value.RepositoryCount == 0) ? 14 : 24;
        state.TextWrapping = TextWrapping.Wrap;
        if (value.Kind is "pullRequests" or "mergeRequests") {
            state.Inlines.Clear(); state.Inlines.Add(new System.Windows.Documents.Run(value.Total + (value.Capped ? "+" : "")) { FontSize = 30 });
            state.Inlines.Add(new System.Windows.Documents.Run(" " + Text.L("card.open")) { FontSize = 12, Foreground = CardTheme.Secondary });
        }
        if (value.Kind == "inbox") state.Text = value.Total + (value.Capped ? "+ " : " ") + Text.L("card.inbox.unread.word");
        healthBar.Children.Clear(); healthBar.ColumnDefinitions.Clear();
        if (value.Kind is "pullRequests" or "mergeRequests") foreach (var health in new[] { "blocked","attention","ready" }) {
            var count = value.Rows.Count(row => row.Health == health); if (count == 0) continue;
            var column = healthBar.ColumnDefinitions.Count; healthBar.ColumnDefinitions.Add(new() { Width = new(count,GridUnitType.Star) });
            var stripe = new Border { CornerRadius = new(2), Background = health == "blocked" ? CardTheme.Red : health == "attention" ? CardTheme.Amber : CardTheme.Green, Opacity = .6, Margin = new(0,0,2,0) };
            Grid.SetColumn(stripe,column); healthBar.Children.Add(stripe);
        }
        healthBar.Visibility = healthBar.Children.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        rows.Children.Clear();
        foreach (var row in RemotePresentation.CardRows(value, expanded)) rows.Children.Add(Row(row));
        if (value.Kind == "actions" && value.RepositoryCount == 0) {
            rows.Children.Add(new TextBlock { Text = Text.L("card.actions.empty.detail"), TextWrapping = TextWrapping.Wrap, Foreground = CardTheme.Secondary, FontSize = 11 });
            rows.Children.Add(CardTheme.Button(Text.L("card.actions.empty.choose"), () => { controller.ShowSettings(settings.AccountIDs.Length == 1 ? "account:"+settings.AccountIDs[0] : "cards"); return Task.CompletedTask; }));
        } else if (value.Kind == "actions" && value.Total == 0) rows.Children.Add(new TextBlock { Text = Text.L("card.actions.quiet.detail",string.Join(", ", (value.WatchedRepositories ?? []).Select(repository => repository.Split('/').Last()))), FontSize = 11, TextWrapping = TextWrapping.Wrap, Foreground = CardTheme.Secondary });
        expand.Visibility = value.Kind != "actions" && value.Rows.Length > 3 ? Visibility.Visible : Visibility.Collapsed;
        expand.Content = Text.L(expanded ? "card.showLess" : "card.showMore", value.Rows.Length - 3);
        if (listWindow is not null) UpdateFullList();
        footer.Text = value.Failures.Length > 0 ? string.Join(" · ", value.Failures.Select(failure =>
            (controller.Settings.AccountList.FirstOrDefault(account => account.Id == failure.AccountID)?.Label ?? "GitHub / GitLab") + ": " + Text.L(failure.Kind switch {
                "rejected" => "error.unauthorized", "forbidden" => "error.forbidden", "rateLimited" => "error.rateLimited", "unreachable" => "error.offline", _ => "error.decoding" })))
            : RemoteWords.Summary(value) + (expanded && value.Rows.Length > 12 ? Text.L("card.notShown",value.Rows.Length - 12) : "");
        if (markAll is not null) {
            markAll.Content = value.Capped ? Text.L("card.inbox.readAll.capped") : Text.LN("card.inbox.readAll",value.Total);
            markAll.IsEnabled = !mutating && value.Total > 0 && value.Failures.Length == 0 && RemotePresentation.ReadCutoffs(value).Count > 0;
            markRest!.Content = value.ActionableCount > 0 ? Text.LN("card.inbox.readRest",value.ActionableCount) : Text.L("windows.markRest");
            markRest.IsEnabled = !mutating && value.Failures.Length == 0 && (value.Capped || value.Rows.Any(row => row.IsUnread && row.Health == "ready"));
        }
    }
    private UIElement Row(RemoteRow row)
    {
        var tint = row.Health == "blocked" ? CardTheme.Red : row.Health == "attention" ? CardTheme.Amber : CardTheme.Green;
        var panel = new StackPanel();
        panel.Children.Add(new TextBlock { Text = (row.NeedsReview && settings.Kind != "inbox" ? Text.L("windows.reviewPrefix") : "") + (settings.Kind == "actions" ? row.Repository.Split('/').Last() + " · " : "") + (row.Subject ?? row.Title), TextTrimming = TextTrimming.CharacterEllipsis,
            FontSize = 12, FontWeight = FontWeights.Medium, Foreground = settings.Kind == "inbox" && !row.IsUnread ? CardTheme.Secondary : CardTheme.Ink });
        var content = new Grid();
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(13) });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        content.Children.Add(new System.Windows.Shapes.Ellipse { Width = 5, Height = 5, Fill = tint, HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top, Margin = new(0, 6, 0, 0) });
        var accountName = controller.Settings.AccountList.FirstOrDefault(account => account.Id == row.AccountID)?.Label ?? (settings.Kind == "mergeRequests" ? "GitLab" : "GitHub");
        var badge = CardTheme.Badge(settings.Kind == "inbox" ? Text.L(RemotePresentation.ReasonKey(row.Detail)) : accountName.ToUpperInvariant()); badge.MaxWidth = 62; badge.Padding = new(5,2,5,2); badge.ToolTip = accountName;
        var badgeLabel = (TextBlock)badge.Child; badgeLabel.Foreground = CardTheme.Blue; badgeLabel.TextTrimming = TextTrimming.CharacterEllipsis; badgeLabel.FontSize = 9;
        var badges = new StackPanel { Orientation = Orientation.Horizontal };
        if (settings.Kind == "inbox" || settings.AccountIDs.Length > 1) badges.Children.Add(badge);
        if (settings.Kind == "inbox" && settings.AccountIDs.Length > 1) { var accountBadge = CardTheme.Badge(accountName.ToUpperInvariant()); accountBadge.MaxWidth = 62; ((TextBlock)accountBadge.Child).TextTrimming = TextTrimming.CharacterEllipsis; badges.Children.Add(accountBadge); }
        Grid.SetColumn(badges,1); content.Children.Add(badges);
        if (row.TicketKey is { } key) { var ticket = new TextBlock { Text = key, FontFamily = new("Consolas"), FontSize = 10, Foreground = CardTheme.Secondary, Margin = new(0,0,6,0), VerticalAlignment = VerticalAlignment.Center }; Grid.SetColumn(ticket,2); content.Children.Add(ticket); }
        Grid.SetColumn(panel, 3); content.Children.Add(panel);
        var code = new TextBlock { Text = row.StatusCode ?? (settings.Kind == "actions" && row.Health == "attention" ? Text.L("card.state.running") : settings.Kind is "actions" or "inbox" ? RemoteWords.Age(row.UpdatedAt) : ""), FontFamily = new("Consolas"), Foreground = CardTheme.Secondary, FontSize = 10, Margin = new(5,0,0,0), VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(code,4); content.Children.Add(code);
        var button = ProjectCard.MakeButton("", () =>
        {
            if (Uri.TryCreate(row.Url, UriKind.Absolute, out var url) && url.Scheme is "https" or "http" && url.UserInfo.Length == 0)
            {
                var account = controller.Settings.AccountList.FirstOrDefault(account => account.Id == row.AccountID);
                BrowserLaunch.Open(account?.Browser ?? "system", account?.BrowserProfile, url.AbsoluteUri);
            }
            return Task.CompletedTask;
        });
        button.Content = content; button.HorizontalContentAlignment = HorizontalAlignment.Stretch; button.Background = Brushes.Transparent;
        button.IsEnabled = row.Url is not null;
        button.Margin = new(0); button.Padding = new(0,7,0,7); button.ToolTip = row.Title + "\n" + row.Repository + " · " + row.Detail;
        System.Windows.Automation.AutomationProperties.SetName(button, row.Title);
        if (settings.Kind != "inbox") return new Border { Child = button, BorderThickness = new(0,0,0,1), BorderBrush = new SolidColorBrush(Color.FromArgb(16,255,255,255)) };
        var container = new Border { Child = button, BorderThickness = new(0,0,0,1), BorderBrush = new SolidColorBrush(Color.FromArgb(16,255,255,255)) };
        container.ContextMenu = new ContextMenu();
        var mark = new MenuItem { Header = Text.L("card.inbox.markRead"), IsEnabled = row.IsUnread && !mutating };
        mark.Click += async (_, _) => await MarkReadAsync(row); container.ContextMenu.Items.Add(mark);
        // Check-suite notifications can have no web URL but still support a per-thread read.
        button.ContextMenu = container.ContextMenu; ContextMenuService.SetShowOnDisabled(button,true);
        button.ContextMenuOpening += (_, e) => { if (mutating || closed) e.Handled = true; };
        return container;
    }
    private async Task MarkReadAsync(RemoteRow row)
    {
        if (!row.IsUnread) return;
        await MutateAsync(token => controller.MarkInboxReadAsync(settings,row.AccountID,[row.Id],token,onProgress:ShowProgress));
    }
    private RemoteSnapshot MaskPendingRead(RemoteSnapshot value)
    {
        if(pendingInboxRead is not{} target || value.Kind!="inbox" || value.CardID!=target.CardID)return value;
        var removed=value.Rows.Where(row=>row.AccountID==target.AccountID && row.Id==target.ThreadID).ToArray();
        if(removed.Length==0)return value;
        var identity=InboxReadValidation.Identity(target.AccountID,target.ThreadID);
        return value with {
            Rows=value.Rows.Where(row=>row.AccountID!=target.AccountID || row.Id!=target.ThreadID).ToArray(),
            Total=Math.Max(0,value.Total-removed.Count(row=>row.IsUnread)),
            ActionableCount=Math.Max(0,value.ActionableCount-removed.Count(row=>row.IsUnread && row.Detail is "securityAlert" or "reviewRequested" or "mention" or "teamMention" or "assigned")),
            Attention=value.Attention?.Where(item=>item.AccountID!=target.AccountID || item.Id!=identity).ToArray(),
            Signals=value.Signals is{} signals ? signals with {Items=signals.Items.Where(item=>item.InboxRead!=target).ToArray()} : null
        };
    }
    internal async Task<bool> ReadAttentionAsync(InboxReadTarget target)
    {
        if(IsMutating || !controller.CanReadInboxAttention(this,target))return false;
        mutating=true; pendingInboxRead=target;
        using var source=CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);mutation=source;
        if(sourceSnapshot is{} snapshot)RenderSnapshot(MaskPendingRead(snapshot));
        controller.RemoveReadAttention(target);SetMutationPresentation(true);
        var admitted=false;string? failure=null;Exception? capturedError=null;
        try {
            if(refreshing is{IsCompleted:false})await refreshing;
            source.Token.ThrowIfCancellationRequested();
            admitted=await controller.SendInboxAttentionReadAsync(this,target,source.Token,ShowProgress);
        } catch(OperationCanceledException) {failure=Text.L("button.cancel");}
        catch(Exception error) when(error is System.IO.IOException or InvalidOperationException or System.ComponentModel.Win32Exception) {
            capturedError=error;
            failure=Text.L("card.inbox.progress.failed",Text.Failure(error));
        } finally {
            pendingInboxRead=null;mutation=null;mutating=false;
            if(!closed){SetMutationPresentation(false);if(controller.CanRefreshInboxOwner(this,target))await RefreshAsync();if(failure is not null)footer.Text=failure;}
        }
        if(capturedError is not null && !closed)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(capturedError).Throw();
        return admitted;
    }
    private async Task MarkBulkAsync(bool all)
    {
        if (latest is not { Failures.Length: 0, Total: > 0 } snapshot) return;
        // Capture the displayed cutoff before a refresh can replace it; never use the click time.
        var cutoffs = RemotePresentation.ReadCutoffs(snapshot);
        await MutateAsync(async token => {
            foreach (var accountID in settings.AccountIDs.Where(id => controller.Settings.AccountList.Any(account => account.Id == id && account.Enabled))) {
                if (all && !cutoffs.ContainsKey(accountID)) continue;
                await controller.MarkInboxReadAsync(settings, accountID, null, token, all ? cutoffs[accountID] : null, ShowProgress);
            }
        });
    }
    private async Task MutateAsync(Func<CancellationToken,Task> action) {
        if (IsMutating || closed || !deckVisible) return;
        mutating = true; string? failure = null;
        using var source = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token); mutation = source;
        SetMutationPresentation(true);
        try { if (refreshing is { IsCompleted: false }) await refreshing; source.Token.ThrowIfCancellationRequested(); await action(source.Token); }
        catch (OperationCanceledException) { failure = Text.L("button.cancel"); }
        catch (Exception error) when (error is System.IO.IOException or InvalidOperationException) { failure = Text.L("card.inbox.progress.failed",Text.Failure(error)); }
        finally {
            mutation = null; mutating = false;
            if (!closed) { SetMutationPresentation(false); await RefreshAsync(); if (failure is not null) footer.Text = failure; }
        }
    }
    internal void SetMutationPresentation(bool busy) {
        presentingMutation = busy;
        actions.IsEnabled = !busy; refreshButton.IsEnabled = !busy; cancel.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        collapseButton.IsEnabled = !busy;
        rows.IsEnabled = !busy; fullRows.IsEnabled = !busy;
        if (busy) footer.Text = Text.L("card.inbox.progress.gathering");
    }
    private void ShowProgress(string progress) => Dispatcher.BeginInvoke(() => {
        if (closed || !mutating) return;
        var parts = progress.Split(':');
        footer.Text = progress == "markingAll" ? Text.L("card.inbox.progress.markingAll") : parts.Length == 3 && int.TryParse(parts[1],out var done) && int.TryParse(parts[2],out var total) ? Text.L("card.inbox.progress.marking",done,total) : Text.L("card.inbox.progress.gathering");
    });
    internal void ApplyFailure(Exception error) {
        if (latest is null) state.Text = Text.L("windows.unavailable");
        verdict.Text = Text.L("windows.refreshFailed"); verdict.Foreground = CardTheme.Amber;
        foldedNote.Text = (latest is null ? "" : RemoteWords.Collapsed(latest) + " · ") + Text.L("windows.refreshFailed");
        footer.Text = Text.Failure(error) + (latest is null ? "" : " " + Text.L("windows.previousResults"));
        if (markAll is not null) markAll.IsEnabled = markRest!.IsEnabled = false;
    }
    internal void SetCollapsed(bool value) {
        collapsed = value; body.Visibility = value ? Visibility.Collapsed : Visibility.Visible;
        CardTheme.CollapseControl(collapseButton,value);
        compactMenu.Header = Text.L(value ? "menu.card.showWhole" : "menu.card.collapse");
        foldedNote.Visibility = value ? Visibility.Visible : Visibility.Collapsed; refreshButton.Visibility = value ? Visibility.Collapsed : Visibility.Visible;
    }
    private void ToggleCollapsed() { if (IsMutating) return; SetCollapsed(!collapsed); controller.SaveCollapsed(settings.Id,collapsed); }
    internal void SetExpanded(bool value) { expanded = value; if (latest is not null) RenderSnapshot(latest); }
    private void OpenDashboard() {
        var account = controller.Settings.AccountList.Where(account => account.Enabled && settings.AccountIDs.Contains(account.Id)).OrderBy(account => account.Id,StringComparer.Ordinal).FirstOrDefault();
        if (account is not null) OpenDashboard(account);
    }
    private void OpenDashboard(RemoteAccountSettings account) => BrowserLaunch.Open(account.Browser,account.BrowserProfile,RemotePresentation.Dashboard(account,settings.Kind));
    private void ShowAll()
    {
        if (closed || !deckVisible || latest is null) return;
        if (listWindow is null) {
            listWindow = new Window { Title = Title, Width = 760, Height = 600, Background = new SolidColorBrush(Color.FromRgb(29, 37, 50)), Foreground = Brushes.White,
                Content = new ScrollViewer { Content = fullRows, VerticalScrollBarVisibility = ScrollBarVisibility.Auto } };
            listWindow.Closed += (_, _) => listWindow = null;
        }
        UpdateFullList(); listWindow.Show(); listWindow.WindowState = WindowState.Normal; listWindow.Activate();
    }
    private void UpdateFullList() { fullRows.Children.Clear(); if (latest is not null) foreach (var row in latest.Rows) {
        fullRows.Children.Add(Row(row)); fullRows.Children.Add(new TextBlock { Text = row.Repository + " · " + row.Detail, Foreground = CardTheme.Secondary, FontSize = 11, TextWrapping = TextWrapping.Wrap });
    } }
    internal void ApplyMode(bool value)
    {
        floating = value; Topmost = value;
        if (handle != 0)
        {
            WidgetWindow.ExcludeFromSwitcher(handle);
            SetWindowPos(handle, value ? (nint)(-1) : (nint)1, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
        }
    }
    internal void Summon()
    {
        if (closed || !deckVisible) return;
        Show(); WindowState = WindowState.Normal; ApplyMode(controller.Settings.Floating);
        if (!controller.Settings.Floating && handle != 0)
        {
            SetWindowPos(handle, 0, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
            var retreat = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
            retreat.Tick += (_, _) => { retreat.Stop(); if (!closed) ApplyMode(controller.Settings.Floating); }; retreat.Start();
        }
    }
    [DllImport("user32.dll")] private static extern bool SetWindowPos(nint window, nint after, int x, int y, int cx, int cy, uint flags);
}
