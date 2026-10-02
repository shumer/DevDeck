using System;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed class ProjectCard : Window
{
    private readonly DeckController controller;
    private readonly TextBlock state = new() { Text = Text.L("windows.connecting"), FontSize = 22, FontWeight = FontWeights.SemiBold, Margin = new(0, 10, 0, 6) };
    private readonly TextBlock detail = new() { TextWrapping = TextWrapping.Wrap, Foreground = CardTheme.Secondary, FontSize = 12, MaxHeight = 48, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock versions = new() { FontFamily = new("Consolas"), Foreground = CardTheme.Secondary, FontSize = 11, MaxWidth = 210,
        Margin = new(12,0,0,0), TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Top, Visibility = Visibility.Collapsed };
    private readonly Button site;
    private readonly Button localEditor;
    private readonly Button phone;
    private readonly Popup phonePopup = new() { StaysOpen = false, AllowsTransparency = true, Placement = PlacementMode.Bottom };
    private readonly Func<string?> phoneAddress;
    private readonly Action<string> copyPhoneLink;
    private bool phoneSnapshotVerified;
    internal PhonePanel? PhoneContent => phonePopup.Child as PhonePanel;
    internal bool PhoneOpen => phonePopup.IsOpen;
    internal PhoneLinkResult CurrentPhoneLink => phoneSnapshotVerified ? PhoneLink.Resolve(Latest?.SiteURL, Latest?.State == "running", phoneAddress(), settings.PhoneURL)
        : new(null,PhoneLinkIssue.Unavailable);
    private readonly CardSettings settings;
    private readonly bool live;
    private readonly Func<string?,CancellationToken,Task<WorkerResponse>>? statusReader;
    private readonly Func<string,CancellationToken,Action<string>,Task<WorkerResponse>>? actionRunner;
    private readonly CancellationTokenSource lifetime = new();
    private readonly WrapPanel projectLinks = new() { Margin = new(0, 8, 8, 0) };
    private readonly WrapPanel siteLinks = new() { Margin = new(0, 8, 0, 0) };
    private readonly Button start;
    private readonly Button stop;
    private readonly Button restart;
    private readonly Button cancel;
    private readonly Button openDocker;
    private bool containerStartAllowed = true;
    private CancellationTokenSource? operation;
    private Task? refresh;
    private bool closed;
    private string? ddevPowerOffToken, ddevPowerOffProgress;
    private long presentationGeneration;
    private DDEVPowerOffPresentation? ddevPowerOffPresentation;
    private sealed record DDEVPowerOffPresentation(ProjectStatus? Snapshot, bool Succeeded, string State, Brush Foreground,
        string Detail, Brush? Dot, Brush? CompactDot, string Timestamp, bool PhoneVerified, Visibility PhoneVisibility,
        Visibility CancelVisibility, (Button Control, bool Enabled)[] Controls);
    private bool deckVisible = true;
    private bool floating;
    private nint handle;
    private bool collapsed;
    private readonly StackPanel body = new();
    private readonly Grid layout = new();
    private readonly DockPanel header = new();
    private readonly WrapPanel actions = new();
    private readonly TextBlock timestamp = new() { Text = "--:--:--", FontSize = 10, FontFamily = new("Consolas"), Foreground = CardTheme.Quiet, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock branch = new() { FontSize = 12, FontFamily = new("Consolas"), Foreground = CardTheme.Blue, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
    private readonly System.Windows.Shapes.Ellipse stateDot = new() { Width = 10, Height = 10, Fill = CardTheme.Quiet, VerticalAlignment = VerticalAlignment.Center, Margin = new(0,10,10,6) };
    private readonly System.Windows.Shapes.Ellipse compactDot = new() { Width = 8, Height = 8, Fill = CardTheme.Quiet, Margin = new(8,0,8,0), VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock heading;
    private readonly Border brand = new();
    private readonly Button folder, terminal, logButton, settingsButton, refreshButton, collapseButton;
    private readonly MenuItem compactMenu = new();
    internal ProjectReference Reference { get; }
    internal ProjectStatus? Latest { get; private set; }
    internal bool LastRefreshSucceeded { get; private set; }
    internal bool ModeApplied { get; private set; }
    internal bool DeckVisible => deckVisible;
    internal bool CanRefresh => deckVisible && Reference.HasLocalFolder && !closed && operation is null && ddevPowerOffToken is null && cancel.Visibility != Visibility.Visible;
    internal bool DDEVPowerOffBusy => ddevPowerOffToken is not null;
    internal bool SidebarOwnerClosed => closed;
    internal SidebarProjectActivity SidebarActivity => closed ? SidebarProjectActivity.None
        : operation is not null || ddevPowerOffToken is not null || cancel.Visibility == Visibility.Visible ? SidebarProjectActivity.Busy
        : Latest is { } snapshot && snapshot.ProjectID == Reference.Id ? snapshot.State switch {
            "working" => SidebarProjectActivity.Busy,
            "starting" when Reference.Kind == "local" => SidebarProjectActivity.Busy,
            "running" => SidebarProjectActivity.Running,
            _ => SidebarProjectActivity.None
        } : SidebarProjectActivity.None;
    internal void BeginDDEVPowerOff(string groupToken)
    {
        if (closed || Reference.Kind != "ddev" || ddevPowerOffToken is not null) return;
        if (string.IsNullOrWhiteSpace(groupToken)) throw new ArgumentException("A DDEV group token is required.",nameof(groupToken));
        var controls = new[] { start, stop, restart, site, localEditor, phone, refreshButton, openDocker }
            .Concat(projectLinks.Children.OfType<Button>().Concat(siteLinks.Children.OfType<Button>()).Where(button => button.Tag is true)).Distinct();
        ddevPowerOffPresentation = new(Latest,LastRefreshSucceeded,state.Text,state.Foreground,detail.Text,stateDot.Fill,compactDot.Fill,
            timestamp.Text,phoneSnapshotVerified,phone.Visibility,cancel.Visibility,controls.Select(button => (button,button.IsEnabled)).ToArray());
        ddevPowerOffToken = groupToken; ddevPowerOffProgress = null; presentationGeneration++;
        if (operation is null) cancel.Visibility = Visibility.Collapsed;
        phonePopup.IsOpen = false; ShowDDEVPowerOff(); RestoreActionVisibility();
        controller.NotifySidebarProjectPresentation(this);
    }
    internal void ReportDDEVPowerOffProgress(string groupToken,string message)
    {
        if (closed || ddevPowerOffToken != groupToken) return;
        ddevPowerOffProgress = message; ShowDDEVPowerOff();
    }
    internal void CompleteDDEVPowerOff(string groupToken,ProjectStatus? status=null,string? failure=null)
    {
        if (closed || ddevPowerOffToken != groupToken || status is not null && status.ProjectID != Reference.Id) return;
        var previous = ddevPowerOffPresentation;
        ddevPowerOffToken = null; ddevPowerOffProgress = null; ddevPowerOffPresentation = null; presentationGeneration++;
        if (status is null && string.IsNullOrWhiteSpace(failure)) {
            if (previous is null) { controller.NotifySidebarProjectPresentation(this); return; }
            Latest = previous.Snapshot; LastRefreshSucceeded = previous.Succeeded; state.Text = previous.State;
            state.Foreground = previous.Foreground; detail.Text = previous.Detail; stateDot.Fill = previous.Dot; compactDot.Fill = previous.CompactDot;
            timestamp.Text = previous.Timestamp; phoneSnapshotVerified = previous.PhoneVerified;
            foreach (var control in previous.Controls) control.Control.IsEnabled = control.Enabled;
            phone.Visibility = collapsed ? Visibility.Collapsed : previous.PhoneVisibility;
            cancel.Visibility = operation is null ? Visibility.Collapsed : previous.CancelVisibility; RestoreActionVisibility();
            controller.NotifySidebarProjectPresentation(this); return;
        }
        var physical = status ?? (previous?.Snapshot is { } snapshot
            ? snapshot with { State="unavailable", SiteURL=null, LocalEditorURL=null, NotAnswering=null, SyncBroken=null }
            : new(Reference.Id,"unavailable",null,null,null,null));
        ApplySnapshot(physical); LastRefreshSucceeded = status is not null && string.IsNullOrWhiteSpace(failure);
        if (!string.IsNullOrWhiteSpace(failure)) {
            detail.Text = Text.L("windows.ddevPowerOff.failed",failure); state.Foreground = CardTheme.Amber;
            if (status is null) { start.IsEnabled = stop.IsEnabled = restart.IsEnabled = false; MarkPhoneUnavailable(); }
        }
        if (operation is not null) { cancel.Visibility = Visibility.Visible; RestoreActionVisibility(); }
        controller.NotifySidebarProjectPresentation(this);
    }
    private void ShowDDEVPowerOff()
    {
        if (ddevPowerOffToken is null) return;
        state.Text = Text.L("windows.ddevPowerOff.progress"); state.Foreground = CardTheme.Amber;
        stateDot.Fill = compactDot.Fill = CardTheme.Amber; detail.Text = ddevPowerOffProgress ?? Text.L("windows.waitOutcome");
        start.IsEnabled = stop.IsEnabled = restart.IsEnabled = site.IsEnabled = localEditor.IsEnabled = phone.IsEnabled = refreshButton.IsEnabled = openDocker.IsEnabled = false;
        phone.Visibility = Visibility.Collapsed;
        foreach (var button in projectLinks.Children.OfType<Button>().Concat(siteLinks.Children.OfType<Button>()).Where(button => button.Tag is true)) button.IsEnabled = false;
    }

    internal ProjectCard(DeckController controller, CardSettings settings, bool live = true, Func<string?>? phoneAddress = null, Action<string>? copyPhoneLink = null,
        Func<string?,CancellationToken,Task<WorkerResponse>>? statusReader = null, Func<string,CancellationToken,Action<string>,Task<WorkerResponse>>? actionRunner = null)
    {
        this.live = live; this.statusReader = statusReader; this.actionRunner = actionRunner;
        this.phoneAddress = phoneAddress ?? PhoneLink.CurrentAddress; this.copyPhoneLink = copyPhoneLink ?? Clipboard.SetText;
        this.controller = controller; this.settings = settings; Reference = settings.Project with { Title = settings.Title }; collapsed = settings.Collapsed;
        Title = "DevDeck · " + settings.Title;
        Width = CardTheme.Width; SizeToContent = SizeToContent.Height; Left = settings.X; Top = settings.Y;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = Brushes.Transparent; ShowInTaskbar = false; ShowActivated = false;
        Foreground = CardTheme.Ink; FontFamily = new FontFamily("Segoe UI");
        layout.Margin = new(14,12,14,12);
        for (var row = 0; row < 3; row++) layout.RowDefinitions.Add(new() { Height = GridLength.Auto });
        layout.ColumnDefinitions.Add(new()); layout.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        collapseButton = CardTheme.Button(Text.L("menu.card.collapse"), () => { ToggleCollapsed(); return Task.CompletedTask; }, "collapse", iconOnly:true);
        collapseButton.Margin = new(0); collapseButton.Background = Brushes.Transparent;
        DockPanel.SetDock(collapseButton,Dock.Right); header.Children.Add(collapseButton);
        settingsButton = CardTheme.Button(Text.L("menu.settings"), () => { controller.ShowSettings("project:" + Reference.Id); return Task.CompletedTask; }, "settings", iconOnly: true);
        settingsButton.Margin = new(0); settingsButton.Background = Brushes.Transparent;
        DockPanel.SetDock(settingsButton, Dock.Right); header.Children.Add(settingsButton);
        logButton = CardTheme.Button(Text.L("menu.card.showLog"), () => controller.ToggleLogsAsync(Reference), "log", iconOnly: true);
        logButton.Background = Brushes.Transparent; DockPanel.SetDock(logButton, Dock.Right); header.Children.Add(logButton);
        refreshButton = CardTheme.Button(Text.L("menu.refresh"), RefreshAsync);
        refreshButton.Content = timestamp; refreshButton.Padding = new(0); refreshButton.Margin = new(2,0,0,0);
        refreshButton.Background = Brushes.Transparent; DockPanel.SetDock(refreshButton, Dock.Right); header.Children.Add(refreshButton);
        brand.Child = BrandMarks.Create(BrandMarks.ProjectKind(Reference.Kind,Reference.Subtitle,Reference.StartCommand)); DockPanel.SetDock(brand, Dock.Left); header.Children.Add(brand);
        DockPanel.SetDock(compactDot, Dock.Left); header.Children.Add(compactDot);
        heading = CardTheme.Heading(settings.Title);
        var title = heading;
        title.MouseLeftButtonDown += (_, e) =>
        {
            if (e.ClickCount == 2) { ToggleCollapsed(); return; }
            if (e.LeftButton != MouseButtonState.Pressed || controller.Settings.Locked) return;
            DragMove(); controller.SavePosition(Reference.Id, Left, Top);
        };
        header.Children.Add(title); layout.Children.Add(header); Grid.SetColumnSpan(header,2);
        Grid.SetRow(body,1); Grid.SetColumnSpan(body,2); layout.Children.Add(body);
        var statusLine = new DockPanel(); DockPanel.SetDock(stateDot,Dock.Left); statusLine.Children.Add(stateDot); statusLine.Children.Add(state); body.Children.Add(statusLine);
        var branchButton = CardTheme.Button(Text.L("windows.repository"), () => { if (Latest?.RepositoryURL is { } url) OpenLink(url); return Task.CompletedTask; });
        var branchLine = new DockPanel(); var branchIcon = CardTheme.Icon("branch",CardTheme.Blue); DockPanel.SetDock(branchIcon,Dock.Left); branchLine.Children.Add(branchIcon); branch.Margin = new(6,0,0,0); branchLine.Children.Add(branch);
        branchButton.Content = branchLine; branchButton.Background = Brushes.Transparent; branchButton.HorizontalContentAlignment = HorizontalAlignment.Stretch; branchButton.Padding = new(0,3,0,3); branchButton.Margin = new(0); body.Children.Add(branchButton);
        var metadata = new DockPanel(); DockPanel.SetDock(versions,Dock.Right); metadata.Children.Add(versions); metadata.Children.Add(detail); body.Children.Add(metadata);
        versions.SetBinding(ToolTipProperty, new System.Windows.Data.Binding(nameof(TextBlock.Text)) { Source = versions });
        detail.SetBinding(ToolTipProperty, new System.Windows.Data.Binding(nameof(TextBlock.Text)) { Source = detail });
        ToolTip = Reference.Distribution + " · " + Reference.Path;
        var linkGroups = new WrapPanel(); linkGroups.Children.Add(projectLinks); linkGroups.Children.Add(siteLinks); body.Children.Add(linkGroups);
        site = CardTheme.Button(Text.L("card.localSite"), () => { OpenSite(); return Task.CompletedTask; }, "site"); site.IsEnabled = false;
        site.Foreground = CardTheme.Blue;
        localEditor = CardTheme.Button(Text.L("card.localPageBuilder"), () => { if (Latest?.LocalEditorURL is { } url) OpenLink(url); return Task.CompletedTask; });
        localEditor.Visibility = Visibility.Collapsed;
        phone = CardTheme.Button(Text.L("card.phone.title"), () => { ShowPhone(); return Task.CompletedTask; }, "qr", iconOnly: true); phone.IsEnabled = false; phone.Visibility = Visibility.Collapsed;
        phonePopup.PlacementTarget = phone;
        folder = CardTheme.Button(Text.L("project.folder"), () => { OpenFolder(); return Task.CompletedTask; }, "folder", iconOnly: true);
        terminal = CardTheme.Button(Text.L("card.action.terminal"), () => { OpenTerminal(); return Task.CompletedTask; }, "terminal", iconOnly: true);
        start = CardTheme.Button(Text.L("card.action.start"), () => PerformAsync("start"), "start");
        stop = CardTheme.Button(Text.L("card.action.stop"), () => PerformAsync("stop"), "stop");
        restart = CardTheme.Button(Text.L("card.action.restart"), () => PerformAsync("restart"), "refresh");
        cancel = CardTheme.Button(Text.L("button.cancel"), () => { operation?.Cancel(); return Task.CompletedTask; }, "cancel"); cancel.Visibility = Visibility.Collapsed;
        start.MinWidth = stop.MinWidth = 108;
        CardTheme.Emphasize(start, CardTheme.Green); CardTheme.Emphasize(stop, CardTheme.Red);
        start.IsEnabled = stop.IsEnabled = restart.IsEnabled = false;
        foreach (var button in new[] { start, stop, restart, cancel }) actions.Children.Add(button);
        actions.Children.Add(folder); actions.Children.Add(terminal);
        Grid.SetRow(actions,2); Grid.SetColumnSpan(actions,2); layout.Children.Add(actions);
        openDocker = CardTheme.Button(Text.L("windows.openDocker"), () => { DockerDesktop.Open(); return Task.CompletedTask; }, "start");
        openDocker.Visibility = Visibility.Collapsed; body.Children.Add(openDocker);
        stop.Visibility = Visibility.Collapsed;
        Content = CardTheme.Frame(layout); SetCollapsed(collapsed);
        compactMenu.Tag = "compact"; compactMenu.Click += (_,_) => ToggleCollapsed();
        ContextMenu = new ContextMenu();
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
        if (live) Loaded += (_, _) => { if (deckVisible) controller.ScheduleLocalRefresh(); };
        Closed += (_, _) => { closed = true; lifetime.Cancel(); operation?.Cancel(); phonePopup.IsOpen = false; if (ContextMenu is not null) ContextMenu.IsOpen = false; };
        Loaded += (_, _) => { if (deckVisible) DesktopRecovery.EnsureReachable(this); };
        if (!Reference.HasLocalFolder) { ApplySnapshot(new(Reference.Id,"unavailable",null,null,null,null)); LastRefreshSucceeded = true; }
        ReconcileLogPresentation();
    }

    private void PopulateContextMenu()
    {
        if (ContextMenu is not { } menu) return;
        menu.Items.Clear();
        menu.Items.Add(new MenuItem { Header=controller.Settings.Cards.FirstOrDefault(card => card.Project.Id == Reference.Id)?.Title ?? settings.Title, IsEnabled=false, Tag="header" });
        compactMenu.Header = Text.L(collapsed ? "menu.card.showWhole" : "menu.card.collapse"); compactMenu.IsEnabled = !closed;
        menu.Items.Add(compactMenu);
        void Item(string tag,string key,Func<Task> action,bool enabled=true) {
            var item = new MenuItem { Header=Text.L(key), Tag=tag, IsEnabled=enabled && !closed };
            item.Click += async (_,_) => await controller.RunMenuAsync(action);
            menu.Items.Add(item);
        }
        Item("logs",controller.IsShowingLogs(Reference.Id) ? "menu.card.hideLog" : "menu.card.showLog",() => controller.ToggleLogsAsync(Reference),Reference.HasLocalFolder && !collapsed);
        Item("hide","menu.card.hide",() => controller.SetCardVisibleAsync(Reference.Id,false));
        Item("settings","menu.card.settings",() => { controller.ShowSettings("project:" + Reference.Id); return Task.CompletedTask; });
        menu.Items.Add(new Separator());
        Item("folder","project.folder",() => { OpenFolder(); return Task.CompletedTask; },Reference.HasLocalFolder);
        Item("terminal","card.action.terminal",() => { OpenTerminal(); return Task.CompletedTask; },Reference.HasLocalFolder);
        Item("qr","card.phone.title",() => { ShowPhone(); return Task.CompletedTask; },cancel.Visibility != Visibility.Visible && ddevPowerOffToken is null);
        menu.Items.Add(new Separator());
        var locked = new MenuItem { Header=Text.L("menu.lock"), Tag="lock", IsCheckable=true, IsChecked=controller.Settings.Locked, IsEnabled=!closed };
        locked.Click += (_,_) => controller.SetLocked(!controller.Settings.Locked); menu.Items.Add(locked);
        Item("tidy","menu.tidy",() => controller.ArrangeAsync());
        Item("refresh","menu.refresh",controller.RefreshAllAsync);
    }

    internal void SetDeckVisible(bool value)
    {
        if (closed) return;
        var showing = value && (!deckVisible || !IsVisible);
        deckVisible = value;
        if (!value) {
            phonePopup.IsOpen = false;
            if (ContextMenu is not null) ContextMenu.IsOpen = false;
            if (IsVisible) Hide();
            return;
        }
        if (!IsVisible) Show();
        ApplyMode(controller.Settings.Floating);
        if (live && showing) controller.ScheduleLocalRefresh();
    }

    internal Task RefreshAsync() => RefreshAsync(null);

    internal Task RefreshAsync(string? cycle)
    {
        if (!CanRefresh) return Task.CompletedTask;
        return refresh is { IsCompleted: false } ? refresh : refresh = ReadStatusAsync(cycle);
    }

    private async Task ReadStatusAsync(string? cycle)
    {
        var generation = presentationGeneration;
        var context = controller.CaptureLocalAttention(Reference.Distribution);
        try
        {
            WorkerResponse response;
            if (statusReader is not null) response = await statusReader(cycle,lifetime.Token);
            else {
                var worker = await controller.GetWorkerAsync(Reference.Distribution);
                if (closed || !deckVisible || generation != presentationGeneration) return;
                response = await worker.CallAsync("project.status", Reference, refreshCycle:cycle, cancellation:lifetime.Token, activeProjectIDs:context.ActiveProjectIDs);
            }
            if (closed || generation != presentationGeneration) return;
            ApplyAttention(response.Attention,context);
            ApplySnapshot(response.Status ?? throw new WorkerException("invalidResponse", "Project status is missing."));
            LastRefreshSucceeded = true;
        }
        catch (OperationCanceledException) when (closed || lifetime.IsCancellationRequested) { }
        catch (Exception error) when (error is System.IO.IOException or InvalidOperationException)
        {
            if (closed || generation != presentationGeneration) return;
            if (error is WorkerException failure) ApplyAttention(failure.Attention,context);
            LastRefreshSucceeded = false; state.Text = Text.L(Latest is null ? "windows.unavailable" : "windows.refreshFailed"); state.Foreground = CardTheme.Amber;
            detail.Text = Text.Failure(error); site.IsEnabled = false; MarkPhoneUnavailable();
            start.IsEnabled = stop.IsEnabled = restart.IsEnabled = false;
        }
    }

    internal void ApplySnapshot(ProjectStatus value)
    {
            if (closed || value.ProjectID != Reference.Id || ddevPowerOffToken is not null) return;
            phoneSnapshotVerified = true;
            Latest = value;
            brand.Child = BrandMarks.Create(BrandMarks.ProjectKind(Reference.Kind,Reference.Subtitle ?? Latest.Framework,Reference.StartCommand));
            var stateKey = "card.state." + Latest.State;
            state.Text = Latest.State == "unavailable" && Reference.Kind == "arc" ? Text.L("arc.stack.unavailable") : Text.L(stateKey) == stateKey ? Latest.State : Text.L(stateKey);
            timestamp.Text = DateTime.Now.ToString("HH:mm:ss"); state.Foreground = CardTheme.Ink;
            stateDot.Fill = compactDot.Fill = Latest.NotAnswering is not null || Latest.State is "paused" or "starting" ? CardTheme.Amber : Latest.State == "running" ? CardTheme.Green : CardTheme.Quiet;
            branch.Text = Latest.Branch ?? "—";
            versions.Text = Reference.Kind == "local" ? Reference.StartCommand ?? Latest.EngineVersion ?? "" : Latest.VersionsLine ?? "";
            versions.ToolTip = versions.Text;
            versions.Visibility = string.IsNullOrWhiteSpace(versions.Text) ? Visibility.Collapsed : Visibility.Visible;
            detail.Text = string.Join(" · ", (Reference.Kind == "local" ? new[] { Reference.Subtitle ?? Latest.Framework, Reference.Path.TrimEnd('/').Split('/').Last() }
                : new[] { Latest.Framework, Latest.EngineVersion, Reference.Arc?.Organization, Reference.Kind == "ddev" ? Reference.Path.TrimEnd('/').Split('/').Last() : null }).Where(value => !string.IsNullOrWhiteSpace(value)));
            if (detail.Text.Length == 0) detail.Text = Reference.Path;
            if (Latest.NotAnswering is { } health) { if (Latest.State != "starting") state.Text = Text.L("windows.notAnswering"); detail.Text = health; }
            if (Latest.SyncBroken is { } sync) { state.Foreground = CardTheme.Amber; detail.Text = Text.L("attention.project.sync.subtitle", sync); }
            site.IsEnabled = Latest.State == "running" && Uri.TryCreate(Latest.SiteURL, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https";
            phone.IsEnabled = Latest.State == "running";
            phone.Visibility = !collapsed && phone.IsEnabled ? Visibility.Visible : Visibility.Collapsed;
            if (!phone.IsEnabled) phonePopup.IsOpen = false;
            else if (phonePopup.IsOpen) UpdatePhoneContent();
            start.IsEnabled = Reference.HasLocalFolder && Latest.State is not ("running" or "starting") && containerStartAllowed; stop.IsEnabled = Reference.HasLocalFolder && Latest.State is "running" or "starting" or "paused"; restart.IsEnabled = Reference.HasLocalFolder && containerStartAllowed;
            folder.IsEnabled = terminal.IsEnabled = logButton.IsEnabled = refreshButton.IsEnabled = Reference.HasLocalFolder;
            localEditor.Visibility = Reference.Kind == "arc" && Latest.LocalEditorURL is not null ? Visibility.Visible : Visibility.Collapsed;
            localEditor.IsEnabled = Latest.State == "running" && Latest.LocalEditorURL is not null;
            cancel.Visibility = Visibility.Collapsed;
            RestoreActionVisibility();
            site.Visibility = collapsed && Latest.State != "running" ? Visibility.Collapsed : Visibility.Visible;
            projectLinks.Children.Clear();
            siteLinks.Children.Clear();
            foreach (var item in ProjectLinks.Present(settings,Latest)) {
                var link = item.Link; var button = CardTheme.Button(link.Label, () => { OpenLink(link.Url); return Task.CompletedTask; });
                button.IsEnabled = !item.RequiresRunning || Latest.State == "running"; button.Tag = item.RequiresRunning;
                (link.EffectiveKind == "site" ? siteLinks : projectLinks).Children.Add(button);
            }
            if (!collapsed) { siteLinks.Children.Insert(0,site); siteLinks.Children.Add(localEditor); siteLinks.Children.Add(phone); }
            controller.NotifySidebarProjectPresentation(this);
    }
    internal void ApplyAttention(AttentionSnapshot? snapshot, LocalAttentionContext? context = null)
    {
        controller.ObserveAttention(snapshot,context);
        var needsDocker = Reference.Kind != "local" || Reference.RequiresDocker == true;
        containerStartAllowed = !needsDocker || snapshot?.ContainerStartAllowed != false;
        openDocker.Visibility = containerStartAllowed ? Visibility.Collapsed : Visibility.Visible;
    }

    private void RestoreActionVisibility()
    {
        cancel.MinWidth = collapsed ? 0 : 122;
        if (cancel.Visibility == Visibility.Visible) {
            start.Visibility = stop.Visibility = restart.Visibility = Visibility.Collapsed;
            return;
        }
        start.MinWidth = stop.MinWidth = collapsed ? 0 : Latest?.State == "paused" ? 80 : 108;
        start.Visibility = Latest?.State is "running" or "starting" ? Visibility.Collapsed : Visibility.Visible;
        stop.Visibility = Latest?.State is "running" or "starting" or "paused" ? Visibility.Visible : Visibility.Collapsed;
        restart.Visibility = Visibility.Visible;
        if (collapsed && Latest?.State is not ("running" or "paused" or "starting")) restart.Visibility = Visibility.Collapsed;
    }

    internal void SetCollapsed(bool value)
    {
        collapsed = value; body.Visibility = value ? Visibility.Collapsed : Visibility.Visible;
        CardTheme.CollapseControl(collapseButton,value);
        compactMenu.Header = Text.L(value ? "menu.card.showWhole" : "menu.card.collapse");
        heading.Text = value ? settings.Title : (Reference.Kind == "local" ? Text.L("project.section.project") : Reference.Kind).ToUpperInvariant() + " · " + settings.Title.ToUpperInvariant();
        heading.FontSize = value ? 14 : 11.5; heading.Foreground = value ? CardTheme.Ink : CardTheme.Secondary;
        heading.Margin = new(value ? 0 : 8,0,4,0); compactDot.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
        settingsButton.Visibility = refreshButton.Visibility = value ? Visibility.Collapsed : Visibility.Visible;
        if (logButton.Parent is Panel oldLog) oldLog.Children.Remove(logButton);
        if (site.Parent is Panel oldSite) oldSite.Children.Remove(site); if (phone.Parent is Panel oldPhone) oldPhone.Children.Remove(phone);
        foreach (var (button,label,icon) in new[] { (start,Text.L("card.action.start"),"start"), (stop,Text.L("card.action.stop"),"stop"), (restart,Text.L("card.action.restart"),"refresh"), (cancel,Text.L("button.cancel"),"cancel") }) CardTheme.Compact(button,label,icon,value);
        Grid.SetColumnSpan(header,value ? 1 : 2); Grid.SetRow(actions,value ? 0 : 2); Grid.SetColumn(actions,value ? 1 : 0); Grid.SetColumnSpan(actions,value ? 1 : 2);
        actions.Margin = new(0,value ? 0 : 12,0,0);
        folder.Visibility = value ? Visibility.Collapsed : Visibility.Visible;
        if (value) { logButton.Visibility = Visibility.Collapsed; phone.Visibility = Visibility.Collapsed; actions.Children.Add(logButton); actions.Children.Add(site); actions.Children.Add(phone); CardTheme.Compact(site,Text.L("card.localSite"),"site",true); }
        else { logButton.Visibility = phone.Visibility = site.Visibility = Visibility.Visible; header.Children.Insert(0,logButton); DockPanel.SetDock(logButton,Dock.Right); siteLinks.Children.Insert(0,site); if (localEditor.Parent is null) siteLinks.Children.Add(localEditor); siteLinks.Children.Add(phone); site.Width = double.NaN; site.MinWidth = 0; site.Content = Text.L("card.localSite"); }
        RestoreActionVisibility();
        site.Visibility = value && Latest?.State != "running" ? Visibility.Collapsed : Visibility.Visible;
        phone.Visibility = !value && phone.IsEnabled ? Visibility.Visible : Visibility.Collapsed;
        phonePopup.PlacementTarget = value ? layout : phone;
        if (ddevPowerOffToken is not null) ShowDDEVPowerOff();
    }
    private void ToggleCollapsed() { SetCollapsed(!collapsed); controller.SaveCollapsed(Reference.Id,collapsed); }

    internal void ShowOperation(string action)
    {
        if (closed) return;
        // Keep a long-running action compact; cancellation replaces idle lifecycle controls.
        start.IsEnabled = stop.IsEnabled = restart.IsEnabled = site.IsEnabled = localEditor.IsEnabled = phone.IsEnabled = false;
        phone.Visibility = Visibility.Collapsed;
        foreach (var button in projectLinks.Children.OfType<Button>().Concat(siteLinks.Children.OfType<Button>()).Where(button => button.Tag is true)) button.IsEnabled = false;
        phonePopup.IsOpen = false;
        cancel.Visibility = Visibility.Visible;
        RestoreActionVisibility();
        CardTheme.Emphasize(cancel, CardTheme.Amber);
        state.Text = action == "stop" ? Text.L("windows.stopping") : action == "restart" ? Text.L("windows.restarting") : Text.L("card.state.starting");
        state.Foreground = CardTheme.Amber; stateDot.Fill = compactDot.Fill = CardTheme.Amber; detail.Text = Text.L("windows.waitOutcome");
        controller.NotifySidebarProjectPresentation(this);
    }

    private async Task PerformAsync(string action)
    {
        if (closed || !deckVisible || operation is not null || ddevPowerOffToken is not null) return;
        if (refresh is { IsCompleted: false }) await refresh;
        if (closed || !deckVisible || operation is not null || ddevPowerOffToken is not null) return;
        operation = new CancellationTokenSource();
        ShowOperation(action);
        string? errorMessage = null;
        try {
            void Progress(string line) => Dispatcher.BeginInvoke(new Action(() => { if (!closed && operation is not null && ddevPowerOffToken is null) detail.Text = line; }));
            var result = actionRunner is null ? await controller.PerformAsync(Reference, action, operation.Token, Progress) : await actionRunner(action,operation.Token,Progress);
            if (!closed && ddevPowerOffToken is null && result.Status is { } status) { ApplySnapshot(status); LastRefreshSucceeded = true; }
        }
        catch (OperationCanceledException) { errorMessage = Text.L("windows.cancelled"); }
        catch (System.IO.IOException error) { errorMessage = Text.Failure(error); }
        finally { operation.Dispose(); operation = null; cancel.Visibility = Visibility.Collapsed; RestoreActionVisibility(); if (ddevPowerOffToken is not null) ShowDDEVPowerOff(); controller.NotifySidebarProjectPresentation(this); }
        if (closed) return;
        await RefreshAsync();
        if (errorMessage is not null && ddevPowerOffToken is null) detail.Text = errorMessage;
    }

    internal Task ShowLogsAsync() { controller.ShowLogs(Reference); return Task.CompletedTask; }
    internal void ReconcileLogPresentation()
    {
        if (closed) return;
        var showing = controller.IsShowingLogs(Reference.Id);
        var label = Text.L(showing ? "menu.card.hideLog" : "menu.card.showLog");
        logButton.ToolTip = label;
        System.Windows.Automation.AutomationProperties.SetName(logButton,label);
        if (showing) CardTheme.Emphasize(logButton,CardTheme.Blue);
        else {
            logButton.Foreground = CardTheme.Ink; logButton.FontWeight = FontWeights.Normal;
            logButton.Background = logButton.BorderBrush = Brushes.Transparent;
            if (logButton.Content is Panel panel && panel.Children.Count > 0 && panel.Children[0] is System.Windows.Shapes.Path icon)
                icon.Stroke = CardTheme.Ink;
        }
    }
    private void UpdatePhoneContent()
    {
        var link = CurrentPhoneLink;
        phonePopup.Child = new PhonePanel(link, copyPhoneLink, () => phonePopup.IsOpen = false,
            () => controller.ShowSettings("project:"+Reference.Id));
    }
    internal void ShowPhone()
    {
        if (closed || !deckVisible || cancel.Visibility == Visibility.Visible || ddevPowerOffToken is not null) return;
        UpdatePhoneContent(); phonePopup.IsOpen = true;
    }
    internal void MarkPhoneUnavailable()
    {
        phoneSnapshotVerified = false; phone.IsEnabled = false; phone.Visibility = Visibility.Collapsed; phonePopup.IsOpen = false;
    }

    internal void ApplyMode(bool value)
    {
        floating = value; Topmost = value;
        if (handle != 0)
        {
            WidgetWindow.ExcludeFromSwitcher(handle);
            ModeApplied = SetWindowPos(handle, value ? (nint)(-1) : (nint)1, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
        }
    }
    internal void Summon()
    {
        if (closed || !deckVisible) return;
        Show(); WindowState = WindowState.Normal;
        ApplyMode(controller.Settings.Floating);
        if (!controller.Settings.Floating && handle != 0)
        {
            SetWindowPos(handle, 0, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
            var retreat = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
            retreat.Tick += (_, _) => { retreat.Stop(); if (!closed) ApplyMode(controller.Settings.Floating); };
            retreat.Start();
        }
    }
    private void OpenSite()
    {
        if (Uri.TryCreate(Latest?.SiteURL, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https")
            OpenLink(uri.AbsoluteUri);
    }
    private void OpenLink(string url) => BrowserLaunch.Open(settings.Browser, settings.BrowserProfile, url);
    private void OpenFolder()
    {
        var path = "\\\\wsl.localhost\\" + Reference.Distribution + Reference.Path.Replace('/', '\\');
        var start = new ProcessStartInfo("explorer.exe") { UseShellExecute = false }; start.ArgumentList.Add(path); Process.Start(start);
    }
    private void OpenTerminal()
    {
        controller.OpenTerminal(Reference);
    }
    internal static Button MakeButton(string label, Func<Task> action)
        => CardTheme.Button(label, action);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(nint window, nint after, int x, int y, int cx, int cy, uint flags);
}
