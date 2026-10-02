using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using System.Diagnostics;
using DevDeck.Windows.Core;
using Forms = System.Windows.Forms;

namespace DevDeck.Windows.App;

internal sealed partial class DeckController
{
    private readonly Application application;
    private readonly bool live;
    private readonly Action<string,string?,string> dashboardOpener;
    private readonly Func<string?> arrangementNameProvider;
    private readonly SettingsStore store;
    private readonly WorkerManager workers = new();
    private readonly WorkerManager settingsChecks;
    private readonly List<ProjectCard> cards = [];
    private readonly Dictionary<string, CardSettings> localConfigurations = new(StringComparer.Ordinal);
    private readonly Dictionary<string, RemoteCardSettings> remoteConfigurations = new(StringComparer.Ordinal);
    private readonly Dictionary<string, long> visibilityRevisions = new(StringComparer.Ordinal);
    private readonly HashSet<string> quietReveals = new(StringComparer.Ordinal);
    private readonly HashSet<string> replaceDistributions = new(StringComparer.Ordinal);
    private bool replaceAllViews;
    private readonly DispatcherTimer localPolling = new() { Interval = LocalRefreshBatch.Interval };
    private readonly LocalRefreshBatch localRefresh = new();
    private bool localRefreshScheduled;
    private readonly List<RemoteCard> remoteCards = [];
    private readonly Dictionary<string, LogWindow> logWindows = new(StringComparer.Ordinal);
    internal WindowsTokenStore Tokens { get; } = new();
    private readonly AttentionTracker attention = new();
    private DateTimeOffset? lastCheckedAt;
    internal DateTimeOffset? LastCheckedAt => lastCheckedAt;
    private TrayIcon? tray;
    private readonly NotificationLedger notifications;
    private readonly Dictionary<(string Distribution, bool Remote), WorkerClient> workerSessions = new();
    private sealed record ScopedAlert(string Scope, DeckAlert Alert);
    private sealed record Delivery(ScopedAlert[] Sources, bool Test = false);
    private readonly List<ScopedAlert> pendingAlerts = [];
    private readonly Queue<Delivery> deliveries = new();
    private Delivery? activeDelivery;
    private readonly DispatcherTimer notificationBatch = new() { Interval = TimeSpan.FromMilliseconds(400) };
    private readonly DispatcherTimer notificationExpiry = new() { Interval = TimeSpan.FromSeconds(40) };
    private readonly DispatcherTimer nextNotification = new() { Interval = TimeSpan.FromMilliseconds(600) };
    private DeckAlert? activeAlert;
    private bool closing;
    private bool shuttingDown;
    private SettingsWindow? settingsWindow;
    private readonly SemaphoreSlim actions = new(1);
    private DesktopShortcut? shortcut;
    internal DeckSettings Settings { get; private set; }
    internal WorkerManager Workers => workers;
    internal async Task<ProjectStatus> CheckProjectAsync(ProjectReference reference,CancellationToken cancellation)
    {
        var runtime=await EnsureWorkerAsync(reference.Distribution);
        cancellation.ThrowIfCancellationRequested();
        return (await (await settingsChecks.GetAsync(runtime)).CallAsync("project.check",reference,cancellation:cancellation)).Status
            ??throw new WorkerException("invalidResponse","Settings check is missing.");
    }
    internal SettingsWindow? SettingsView => settingsWindow;
    internal RemoteCard[] RemoteViews => remoteCards.Where(card => card.DeckVisible).ToArray();
    internal ProjectCard[] LocalViews => cards.Where(card => card.DeckVisible).ToArray();
    internal RemoteCard[] AllRemoteViews => remoteCards.ToArray();
    internal ProjectCard[] AllLocalViews => cards.ToArray();
    internal TimeSpan LocalPollInterval => localPolling.Interval;
    internal bool LocalPollEnabled => localPolling.IsEnabled;
    private static string StartupDirectory => Environment.GetFolderPath(Environment.SpecialFolder.Startup);
    internal bool StartsAtLogin => StartupShortcut.IsEnabled(StartupDirectory, store.Path);
    internal void SetStartAtLogin(bool enabled) => StartupShortcut.Set(StartupDirectory, Environment.ProcessPath!, store.Path, enabled);

    internal DeckController(Application application, SettingsStore store, bool live = true,
        Action<string,string?,string>? dashboardOpener = null, Func<string?>? arrangementNameProvider = null,
        Func<string[],bool>? powerOffConfirmation = null,
        Func<string,Task<IDDEVPowerOffEndpoint>>? powerOffEndpointFactory = null,
        Func<string,Task<IWorkInFlightEndpoint>>? checkoutEndpointFactory = null, Action<CheckoutTarget>? checkoutTerminalOpener = null,
        Action<DeckSettings>? settingsGeometryCommit = null,
        Func<WorkerSettings,WorkerClient>? settingsCheckWorkerFactory = null)
    {
        this.application = application; this.store = store; this.live = live;
        settingsChecks = new(settingsCheckWorkerFactory);
        this.settingsGeometryCommit = settingsGeometryCommit ?? store.Save;
        this.dashboardOpener = dashboardOpener ?? ((browser,profile,address) => BrowserLaunch.Open(browser,profile,address));
        this.arrangementNameProvider = arrangementNameProvider ?? (() => ArrangementNameDialog.Show(settingsWindow));
        this.powerOffConfirmation = powerOffConfirmation ?? (routes => DDEVPowerOffDialog.Confirm(routes, settingsWindow));
        this.powerOffEndpointFactory = powerOffEndpointFactory ?? CaptureDDEVPowerOffEndpointAsync;
        Settings = store.Load();
        Text.Use(Settings.Language);
        Settings = Settings with { Workers = Settings.Workers.Select(worker => worker with { Language = Text.Language }).ToArray() };
        var discovered = DiscoverCards(Settings);
        if (discovered != Settings) { store.Save(discovered); Settings = discovered; }
        notifications = new(Settings.AnnouncedAlerts);
        InitializeCheckouts(checkoutEndpointFactory, checkoutTerminalOpener);
        notificationBatch.Tick += (_, _) => FlushNotifications();
        notificationExpiry.Tick += (_, _) => AdvanceNotification();
        nextNotification.Tick += (_, _) => { nextNotification.Stop(); DeliverNotification(); };
        localPolling.Tick += async (_, _) => await RefreshLocalCardsAsync();
    }

    internal async Task StartAsync()
    {
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += DisplayChanged;
        if (Settings.Workers.Length > 0)
        {
            var installed = new List<WorkerSettings>();
            foreach (var worker in Settings.Workers)
            {
                try {
                    var archive = Path.Combine(AppContext.BaseDirectory, "workers", await RuntimeInstaller.PackageNameAsync(worker.Distribution));
                    if (!File.Exists(archive)) throw new IOException(Text.L("windows.workerPackageMissing"));
                    installed.Add((await RuntimeInstaller.InstallAsync(worker.Distribution, archive)) with { Language = Text.Language });
                }
                catch (Exception error) when (error is IOException or OperationCanceledException or System.ComponentModel.Win32Exception)
                { installed.Add(worker); } // An unavailable distro must not remove other cards.
            }
            Settings = Settings with { Workers = installed.ToArray() }; store.Save(Settings);
        }
        tray = new TrayIcon();
        shortcut = new DesktopShortcut(ShowCards);
        var menu = new Forms.ContextMenuStrip();
        menu.Opening += (_, _) => BuildMenu(menu);
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += ShowCards;
        tray.BalloonClicked += () => {
            var alert = activeAlert;
            AdvanceNotification();
            application.Dispatcher.BeginInvoke(new Action(async () => {
                if (!closing && alert is not null) await RunMenuAsync(() => ExecuteAttentionAsync(alert.Target));
            }));
        };
        tray.BalloonClosed += () => application.Dispatcher.BeginInvoke(new Action(AdvanceNotification));
        BuildMenu(menu);
        RebuildCards();
        if (cards.Count + remoteCards.Count + (WorkInFlightActive ? 1 : 0) == 0) ShowSettings();
    }

    internal async Task<WorkerResponse> PerformAsync(ProjectReference project, string action, CancellationToken cancellation, Action<string>? progress = null)
    {
        // Docker Desktop is shared by the distros, so project mutations are serialized across workers.
        await actions.WaitAsync(cancellation);
        try
        {
            var worker = await GetWorkerAsync(project.Distribution);
            var context = CaptureLocalAttention(project.Distribution);
            try {
                var response = await worker.CallAsync("project." + action, project, timeout: TimeSpan.FromMinutes(20), cancellation: cancellation, onProgress: progress, activeProjectIDs:context.ActiveProjectIDs);
                ObserveAttention(response.Attention,context); return response;
            } catch (WorkerException error) { ObserveAttention(error.Attention,context); throw; }
        }
        finally { actions.Release(); }
    }

    private void RebuildCards()
    {
        bool Same<T>(T left,T right) => JsonSerializer.Serialize(left,WorkerProtocol.Json) == JsonSerializer.Serialize(right,WorkerProtocol.Json);
        foreach (var card in cards.ToArray()) {
            var item=Settings.Cards.FirstOrDefault(item=>item.Project.Id==card.Reference.Id);
            var old=localConfigurations[card.Reference.Id];
            if(item is not null && !replaceAllViews && !replaceDistributions.Contains(item.Project.Distribution)
                && Same(old with{Enabled=false,X=0,Y=0,Collapsed=false},item with{Enabled=false,X=0,Y=0,Collapsed=false}))continue;
            card.Close();cards.Remove(card);localConfigurations.Remove(card.Reference.Id);
        }
        foreach(var card in remoteCards.ToArray()){
            var item=Settings.RemoteCardList.FirstOrDefault(item=>item.Id==card.CardID);
            var old=remoteConfigurations[card.CardID];
            if(item is not null && !replaceAllViews && !replaceDistributions.Contains(item.Distribution)
                && Same(old with{Enabled=false,X=0,Y=0,Collapsed=false},item with{Enabled=false,X=0,Y=0,Collapsed=false}))continue;
            card.Close();remoteCards.Remove(card);remoteConfigurations.Remove(card.CardID);
        }
        foreach(var item in Settings.Cards){
            var card=cards.FirstOrDefault(card=>card.Reference.Id==item.Project.Id);
            if(card is null){card=new ProjectCard(this,item,live);cards.Add(card);}
            localConfigurations[item.Project.Id]=item;
            card.Left=item.X;card.Top=item.Y;card.SetCollapsed(item.Collapsed);card.ApplyMode(Settings.Floating);
            card.SetDeckVisible(item.Enabled);
            NotifySidebarProjectPresentation(card);
        }
        foreach(var item in Settings.RemoteCardList){
            var card=remoteCards.FirstOrDefault(card=>card.CardID==item.Id);
            if(card is null){card=new RemoteCard(this,item,live);remoteCards.Add(card);}
            remoteConfigurations[item.Id]=item;
            card.Left=item.X;card.Top=item.Y;card.SetCollapsed(item.Collapsed);card.ApplyMode(Settings.Floating);
            card.SetDeckVisible(RemoteCardCatalog.Active(Settings,item));
        }
        ReconcileWorkInFlight();
        replaceAllViews=false;replaceDistributions.Clear();
        ScheduleLocalRefresh();
        ScheduleSharedRefresh();
    }

    internal void ScheduleLocalRefresh()
    {
        if (!live || closing || shuttingDown) return;
        if (!cards.Any(card=>card.DeckVisible && card.Reference.HasLocalFolder)) { localPolling.Stop(); return; }
        localPolling.Start();
        if (localRefreshScheduled) return;
        localRefreshScheduled = true;
        application.Dispatcher.BeginInvoke(new Action(async () => {
            localRefreshScheduled = false;
            if (!closing && !shuttingDown) await RefreshLocalCardsAsync();
        }), DispatcherPriority.Background);
    }

    private Task RefreshLocalCardsAsync() => localRefresh.RunAsync(cards.Where(card => card.CanRefresh)
        .Select(card => new Func<string,Task>(cycle => card.RefreshAsync(cycle))).ToArray());

    internal void ShowSettings(string? selection = null)
    {
        if (settingsWindow is null)
        {
            settingsWindow = new SettingsWindow(this, tokenAvailable: live ? null : _ => false);
            settingsWindow.Closed += (_, _) => settingsWindow = null;
        }
        settingsWindow.Show(); settingsWindow.Activate();
        if (selection is not null) settingsWindow.SelectPage(selection);
    }
    internal LogWindow ShowLogs(ProjectReference project)
    {
        if (!logWindows.TryGetValue(project.Id, out var window)) {
            window = new LogWindow(this, project, live); logWindows.Add(project.Id, window);
            window.Closed += (_, _) => logWindows.Remove(project.Id);
        }
        window.Show(); window.WindowState = WindowState.Normal; window.Activate();
        return window;
    }
    internal async Task<WorkerLogs?> ReadLogsAsync(ProjectReference project, CancellationToken cancellation)
    {
        if (closing || !await actions.WaitAsync(0, cancellation)) return null;
        try {
            if (closing) return null;
            return (await (await GetWorkerAsync(project.Distribution)).CallAsync("project.logs", project,
                timeout: TimeSpan.FromSeconds(30), cancellation: cancellation)).Logs;
        } finally { actions.Release(); }
    }
    internal bool IsShowingLogs(string id) => logWindows.TryGetValue(id,out var window) && window.IsVisible;
    internal Task ToggleLogsAsync(ProjectReference project)
    {
        if(logWindows.TryGetValue(project.Id,out var window) && window.IsVisible)window.Close();
        else ShowLogs(project);
        return Task.CompletedTask;
    }
    internal void SaveLogPlacement(LogWindowPlacement placement)
    {
        Settings = Settings with { LogWindows = Settings.LogWindowList.Where(item => item.CardID != placement.CardID).Append(placement).TakeLast(200).ToArray() };
        store.Save(Settings);
    }
    internal void OpenLinuxFile(string distribution, string path)
    {
        _ = WorkerClient.WslStart(distribution, "/tmp");
        if (!LinuxPath.IsAbsolute(path)) throw new ArgumentException("Invalid Linux file path.");
        var editor = new ProcessStartInfo("notepad.exe") { UseShellExecute = false };
        editor.ArgumentList.Add("\\\\wsl.localhost\\" + distribution + path.Replace('/', '\\')); Process.Start(editor);
    }
    internal void OpenTerminal(ProjectReference project, string? filePath = null, bool logs = false, string? containerName = null)
    {
        ProcessStartInfo Launch(bool prefer) => logs ? TerminalLaunch.CreateLogs(project, filePath, prefer, containerName) : TerminalLaunch.Create(project.Distribution, project.Path, prefer);
        try { Process.Start(Launch(true)); }
        catch (System.ComponentModel.Win32Exception) { Process.Start(Launch(false)); }
    }
    internal void ShowCards()
    {
        foreach(var card in LocalViews)card.Summon();
        foreach(var card in RemoteViews)card.Summon();
        if(WorkInFlightActive)workInFlightCard?.Summon();
        if(LocalViews.Length+RemoteViews.Length+(WorkInFlightActive?1:0)==0)ShowSettings();
    }
    private void DisplayChanged(object? sender, EventArgs args) => application.Dispatcher.BeginInvoke(new Action(() => {
        if (closing) return;
        foreach(var card in LocalViews)DesktopRecovery.EnsureReachable(card);
        foreach(var card in RemoteViews)DesktopRecovery.EnsureReachable(card);
        if(WorkInFlightActive && workInFlightCard is{} aggregate)DesktopRecovery.EnsureReachable(aggregate);
    }));
    internal Task RefreshAllAsync() => !live || closing || shuttingDown ? Task.CompletedTask
        : Task.WhenAll(RefreshLocalCardsAsync(), RefreshSharedAsync());
    internal void OpenPullsDashboard()
    {
        var account = Settings.AccountList.FirstOrDefault(account => account.Enabled && account.Provider == "github");
        dashboardOpener(account?.Browser ?? "system", account?.BrowserProfile, "https://github.com/pulls");
    }
    internal void SaveArrangement(string name)
    {
        var value = Settings.SaveArrangement(name);
        store.Save(value); Settings = value;
        settingsWindow?.ReconcileArrangements();
    }
    internal void ForgetArrangement(string name)
    {
        var value = Settings.ForgetArrangement(name);
        if (ReferenceEquals(value,Settings)) return;
        store.Save(value); Settings = value;
        settingsWindow?.ReconcileArrangements();
    }
    internal async Task ApplyArrangementAsync(string name)
    {
        var saved = Settings.ArrangementList.FirstOrDefault(item => string.Equals(item.Name,name,StringComparison.OrdinalIgnoreCase));
        if (saved is null) return;
        foreach (var placed in saved.Cards) {
            var local = Settings.Cards.FirstOrDefault(card => card.Project.Id == placed.Id);
            var remote = Settings.RemoteCardList.FirstOrDefault(card => card.Id == placed.Id);
            var aggregate = placed.Id == CheckoutCatalog.CardID && Settings.WorkInFlight is not null && WorkInFlightAvailable;
            if (local is null && remote is null && !aggregate) continue;
            // Keep the visibility transition scoped, and retain pending operations/owners.
            await SetCardVisibleAsync(placed.Id,placed.Enabled);
            SetCardCollapsed(placed.Id,placed.Collapsed);
            SavePosition(placed.Id,placed.X,placed.Y);
            Window? window = local is not null ? cards.FirstOrDefault(card => card.Reference.Id == placed.Id)
                : aggregate ? workInFlightCard : remoteCards.FirstOrDefault(card => card.CardID == placed.Id);
            if (window is not null) { window.Left = placed.X; window.Top = placed.Y; }
        }
        settingsWindow?.ReconcileArrangements();
    }
    internal void SetLocked(bool value){var changed=Settings with{Locked=value};store.Save(changed);Settings=changed;settingsWindow?.ReconcileDeckModes();}
    internal async Task ArrangeAsync(Rect? workArea = null)
    {
        await actions.WaitAsync();
        try {
            if (closing) return;
            // SizeToContent can finish its native resize after UpdateLayout. Let pending
            // render/WM_SIZE work settle before reading the window dimensions.
            await Dispatcher.Yield(DispatcherPriority.Background);
            if (closing) return;
            var catalogOrder=CardOrdering.IDs(Settings).Select((id,index)=>(id,index)).ToDictionary(item=>item.id,item=>item.index,StringComparer.Ordinal);
            var visible = remoteCards.Select(card => (Id: card.CardID, Window: (Window)card))
                .Concat(cards.Select(card => (Id: card.Reference.Id, Window: (Window)card)))
                .Concat(workInFlightCard is not null ? new[]{(Id: CheckoutCatalog.CardID, Window: (Window)workInFlightCard)} : [])
                .Where(item => item.Window.IsVisible)
                .OrderBy(item=>catalogOrder.GetValueOrDefault(item.Id,int.MaxValue)).ToArray();
            if (visible.Length == 0) return;
            foreach (var item in visible) item.Window.UpdateLayout();
            var anchor = visible.MinBy(item => item.Window.Top).Window;
            var area = workArea ?? DesktopRecovery.WorkArea(anchor);
            // Native bounds include pixel rounding of SizeToContent's fractional WPF height.
            var measured = visible.Select(item => { var size = DesktopRecovery.Size(item.Window); return new MeasuredCard(item.Id,size.Width,size.Height); }).ToArray();
            var dpi = System.Windows.Media.VisualTreeHelper.GetDpi(anchor);
            var placements = ColumnLayout.Tidy(measured, anchor.Left, anchor.Top, new(area.Left,area.Top,area.Width,area.Height))
                .Select(point => point with { X = Math.Round(point.X * dpi.DpiScaleX,MidpointRounding.AwayFromZero) / dpi.DpiScaleX,
                    Y = Math.Round(point.Y * dpi.DpiScaleY,MidpointRounding.AwayFromZero) / dpi.DpiScaleY })
                .ToDictionary(item => item.Id,StringComparer.Ordinal);
            var arranged = Settings with {
                Cards = Settings.Cards.Select(card => placements.TryGetValue(card.Project.Id,out var point) ? card with { X = point.X, Y = point.Y } : card).ToArray(),
                RemoteCards = Settings.RemoteCards is null ? null : Settings.RemoteCardList.Select(card => placements.TryGetValue(card.Id,out var point) ? card with { X = point.X, Y = point.Y } : card).ToArray(),
                WorkInFlight = Settings.WorkInFlight is{} aggregate && WorkInFlightAvailable && placements.TryGetValue(CheckoutCatalog.CardID,out var aggregatePoint)
                    ? aggregate with {X=aggregatePoint.X,Y=aggregatePoint.Y} : Settings.WorkInFlight
            };
            // Tidy only moves existing windows: keep snapshots, operations, lists and pollers intact.
            store.Save(arranged); Settings = arranged;
            foreach (var item in visible) { var point = placements[item.Id]; item.Window.Left = point.X; item.Window.Top = point.Y; }
        } finally { actions.Release(); }
    }
    internal void SetFloating(bool value)
    {
        var changed = Settings with { Floating = value }; store.Save(changed); Settings = changed;
        foreach (var card in cards) card.ApplyMode(value);
        foreach (var card in remoteCards) card.ApplyMode(value);
        workInFlightCard?.ApplyMode(value);
        settingsWindow?.ReconcileDeckModes();
    }

    internal void SavePosition(string id, double x, double y)
    {
        if(id==CheckoutCatalog.CardID && WorkInFlightAvailable && Settings.WorkInFlight is{} preference){
            var changed=Settings with{WorkInFlight=preference with{X=x,Y=y}};store.Save(changed);Settings=changed;return;
        }
        Settings = Settings with { Cards = Settings.Cards.Select(card => card.Project.Id == id ? card with { X = x, Y = y } : card).ToArray() };
        Settings = Settings with { RemoteCards = Settings.RemoteCardList.Select(card => card.Id == id ? card with { X = x, Y = y } : card).ToArray() };
        if(id==CheckoutCatalog.CardID && WorkInFlightAvailable && Settings.WorkInFlight is{} aggregate)Settings=Settings with{WorkInFlight=aggregate with{X=x,Y=y}};
        store.Save(Settings);
    }
    internal void SaveCollapsed(string id, bool collapsed)
    {
        if(id==CheckoutCatalog.CardID && WorkInFlightAvailable && Settings.WorkInFlight is{} preference){
            var changed=Settings with{WorkInFlight=preference with{Collapsed=collapsed}};store.Save(changed);Settings=changed;return;
        }
        Settings = Settings with {
            Cards = Settings.Cards.Select(card => card.Project.Id == id ? card with { Collapsed = collapsed } : card).ToArray(),
            RemoteCards = Settings.RemoteCardList.Select(card => card.Id == id ? card with { Collapsed = collapsed } : card).ToArray(),
            WorkInFlight = id==CheckoutCatalog.CardID && WorkInFlightAvailable && Settings.WorkInFlight is{} aggregate ? aggregate with{Collapsed=collapsed} : Settings.WorkInFlight
        }; store.Save(Settings);
    }
    internal bool SetCardCollapsed(string id, bool collapsed)
    {
        var remote = remoteCards.FirstOrDefault(card => card.CardID == id);
        if (collapsed && remote?.IsMutating == true) return false;
        SaveCollapsed(id, collapsed);
        cards.FirstOrDefault(card => card.Reference.Id == id)?.SetCollapsed(collapsed);
        remote?.SetCollapsed(collapsed);
        if(id==CheckoutCatalog.CardID && WorkInFlightAvailable)workInFlightCard?.SetCollapsed(collapsed);
        return true;
    }

    internal async Task<RemoteSnapshot> FetchRemoteAsync(RemoteCardSettings card, CancellationToken cancellation)
    {
        bool Active()=>Settings.RemoteCardList.FirstOrDefault(item=>item.Id==card.Id) is{} current && RemoteCardCatalog.Active(Settings,current);
        if(!Active())throw new OperationCanceledException(cancellation);
        var accounts = card.AccountIDs.Select(id => Settings.AccountList.Single(account => account.Id == id)).Where(account => account.Enabled)
            .Select(account => RemoteAccountApplicability.Credential(account,
                RemoteTokenReader is {} readToken ? readToken(account) : Tokens.Read(account))).ToArray();
        if (accounts.Length == 0) throw new IOException(Text.L("windows.validationAccount"));
        var worker = RemoteRequestSender is null ? await GetWorkerAsync(card.Distribution,remote:true) : null;
        cancellation.ThrowIfCancellationRequested();
        if(!Active())throw new OperationCanceledException(cancellation);
        try {
            var request = new RemoteRequest(card.Id,card.Kind,accounts);
            var response = RemoteRequestSender is {} send
                ? await send(card.Distribution,"remote.snapshot",request,cancellation)
                : await worker!.CallAsync("remote.snapshot", timeout: TimeSpan.FromMinutes(3), cancellation: cancellation, remote: request);
            ObserveAttention(response.Attention);
            return response.Remote ?? throw new IOException(Text.L("windows.remoteMissing"));
        } catch (WorkerException error) { ObserveAttention(error.Attention); throw; }
    }
    internal async Task VerifyTokenAsync(RemoteAccountSettings account, string token, string distribution, CancellationToken cancellation)
    {
        var request = new RemoteRequest("verify." + account.Id, account.Provider == "gitlab" ? "mergeRequests" : "pullRequests",
            [RemoteAccountApplicability.Credential(account, token)]);
        if (RemoteRequestSender is {} send) {
            cancellation.ThrowIfCancellationRequested();
            _ = await send(distribution,"remote.verify",request,cancellation);
            return;
        }
        var configuration = await EnsureWorkerAsync(distribution);
        var worker = await GetWorkerAsync(configuration.Distribution,remote:true);
        _ = await worker.CallAsync("remote.verify", timeout: TimeSpan.FromMinutes(3), cancellation: cancellation,
            remote: request);
    }
    internal void ObserveAttention(AttentionSnapshot? snapshot,LocalAttentionContext? context=null)
    {
        if (snapshot is null || closing) return;
        snapshot=MaskPendingInboxRead(snapshot);
        if(context is not null && (snapshot.Scope!="local:"+context.Distribution
            || context.Revision!=visibilityRevisions.GetValueOrDefault(context.Distribution)))return;
        if(live || !snapshot.Scope.StartsWith("synthetic:",StringComparison.Ordinal)){
            snapshot=AttentionVisibility.Filter(snapshot,Settings);
            if(snapshot is null)return;
        }
        // The validated read has completed. Event ages and draft settings checks are unrelated.
        lastCheckedAt = DateTimeOffset.UtcNow;
        attention.Observe(snapshot); UpdateAttentionIcon();
        if(snapshot.Scope.StartsWith("local:",StringComparison.Ordinal)){
            var distribution=snapshot.Scope[6..];
            var revealed=Settings.Cards.Where(card=>card.Project.Distribution==distribution && quietReveals.Contains(card.Project.Id))
                .Select(card=>card.Project.Id).ToHashSet(StringComparer.Ordinal);
            if(Settings.Notifications)notifications.Seed(snapshot.Alerts.Where(alert=>alert.Target.CardID is{} id && revealed.Contains(id)),Settings);
            quietReveals.ExceptWith(revealed);
        }
        pendingAlerts.AddRange(notifications.Observe(snapshot,Settings).Select(alert=>new ScopedAlert(snapshot.Scope,alert)));
        if (!Settings.AnnouncedAlerts.SequenceEqual(notifications.Seen)) {
            Settings = Settings with { SeenAlerts = notifications.Seen }; store.Save(Settings);
        }
        if (pendingAlerts.Count > 0) notificationBatch.Start();
    }
    private void UpdateAttentionIcon()
    {
        if (tray is null) return;
        var parts = new[] { ("waiting", "waiting"), ("needsFixing", "toFix"), ("stuck", "stuck") }
            .Select(tier => (key: tier.Item2, count: attention.SignalItems.Count(item => item.Tier == tier.Item1))).Where(part => part.count > 0)
            .Select(part => Text.LN("attention.summary." + part.key, part.count)).ToArray();
        tray.Text = Text.L("attention.tooltip", parts.Length == 0 ? Text.L("attention.summary.none") : string.Join(", ", parts));
        tray.SetAttention(attention.SignalItems.Select(item => item.Tier));
    }
    private void FlushNotifications()
    {
        notificationBatch.Stop();
        var fresh=pendingAlerts.DistinctBy(source=>source.Alert.Id).Where(Eligible).ToArray();
        pendingAlerts.Clear();
        if (!Settings.Notifications || fresh.Length == 0) return;
        if(fresh.Length>=NotificationLedger.SummaryThreshold)deliveries.Enqueue(new(fresh));
        else foreach(var source in fresh)deliveries.Enqueue(new([source]));
        while (deliveries.Count > NotificationLedger.Memory) deliveries.Dequeue();
        DeliverNotification();
    }
    private void DeliverNotification()
    {
        if (closing || !Settings.Notifications || activeAlert is not null || deliveries.Count == 0 || tray is null) return;
        var delivery=deliveries.Dequeue();
        var fresh=delivery.Test?delivery.Sources:delivery.Sources.Where(Eligible).ToArray();
        if(fresh.Length==0){nextNotification.Start();return;}
        activeDelivery=delivery with{Sources=fresh};
        activeAlert=fresh.Length>=NotificationLedger.SummaryThreshold?Summary(fresh.Select(source=>source.Alert).ToArray()):fresh[0].Alert;
        if(fresh.Length>1 && fresh.Length<NotificationLedger.SummaryThreshold){
            var remainder=deliveries.ToArray();deliveries.Clear();
            foreach(var source in fresh.Skip(1))deliveries.Enqueue(new([source]));
            foreach(var queued in remainder)deliveries.Enqueue(queued);
            activeDelivery=new([fresh[0]]);
        }
        var body = string.Join(Environment.NewLine, new[] { activeAlert.Subtitle, activeAlert.Body }.Where(value => !string.IsNullOrWhiteSpace(value)));
        if (!tray.ShowBalloon(activeAlert.Title, body, activeAlert.Quiet)) { activeAlert = null;activeDelivery=null; nextNotification.Start(); return; }
        notificationExpiry.Start();
    }
    private void AdvanceNotification()
    {
        if (activeAlert is null) return;
        notificationExpiry.Stop(); activeAlert = null;activeDelivery=null;
        if (!closing) nextNotification.Start();
    }
    private bool Eligible(ScopedAlert source)
    {
        var active=AttentionVisibility.Filter(new(source.Scope,[],[source.Alert]),Settings);
        return active?.Alerts.Any(alert=>alert.Id==source.Alert.Id)==true && NotificationLedger.Enabled(source.Alert,Settings);
    }
    private static DeckAlert Summary(DeckAlert[] fresh)=>new("summary","blocked","devdeck",string.Join(", ",new[]{
        ("reviewRequest","reviews"),("cantCheck","cantCheck"),("wentDown","wentDown"),("startFailed","startFailed"),("blocked","stuck"),("failedRun","failedRun")}
        .Select(kind=>(key:kind.Item2,count:fresh.Count(alert=>alert.Kind==kind.Item1))).Where(part=>part.count>0)
        .Select(part=>Text.LN("alert.summary."+part.key,part.count))),"",
        Text.L("alert.summary.body",Text.L("alert.summary.named.more",fresh[0].Subject,fresh[1].Subject,fresh.Length-2)),"",new("menu"),fresh.All(alert=>alert.Quiet));
    private void BuildMenu(Forms.ContextMenuStrip menu)
    {
        // A language save can rebuild the retained root while it is open. Close its
        // current chain first so all input/click subscriptions leave with the old items.
        if (menu.Visible) menu.Close(Forms.ToolStripDropDownCloseReason.AppClicked);
        foreach (Forms.ToolStripItem old in menu.Items.Cast<Forms.ToolStripItem>().ToArray()) DisposeMenuItem(old);
        var items = attention.SignalItems;
        var now = DateTimeOffset.UtcNow;
        if (items.Length == 0) menu.Items.Add(new TrayAttentionRow(Text.L("menu.calm"), Text.L("menu.checkedAt", AttentionDigest.Clock(lastCheckedAt ?? now))));
        foreach (var section in AttentionDigest.Sections(items)) {
            menu.Items.Add(new Forms.ToolStripMenuItem(Text.L("attention.tier." + section.Tier)) { Enabled = false });
            TrayAttentionRow Row(AttentionItem item) {
                var row = new TrayAttentionRow(item, now);
                row.Click += async (_, _) => { var choice=row.CurrentChoice; await RunMenuAsync(() => ExecuteAttentionChoiceAsync(item,choice)); };
                return row;
            }
            foreach (var item in section.Visible) menu.Items.Add(Row(item));
            if (section.OverflowTitle(Text.Resources) is { } title) {
                var more = new Forms.ToolStripMenuItem(title);
                foreach (var item in section.Overflow) more.DropDownItems.Add(Row(item));
                menu.Items.Add(more);
            }
        }
        if (items.Length > 0) menu.Items.Add(Text.L("windows.attentionAll", items.Length), null, (_, _) => new AttentionWindow(this, items).Show());
        menu.Items.Add(new Forms.ToolStripSeparator());
        AddCardMenu(menu);
        if (Settings.Cards.Any(card => card.Project.Kind == "ddev")) {
            var powerOff = new Forms.ToolStripMenuItem(Text.L("menu.ddev.powerOff")) {
                Tag="tray.ddevPowerOff", Enabled=!DDEVPowerOffBusy,
                ToolTipText=Text.L("menu.ddev.powerOff.tooltip") };
            powerOff.Click += async (_,_) => await RunMenuAsync(PowerOffDDEVAsync); menu.Items.Add(powerOff);
        }
        menu.Items.Add(new Forms.ToolStripSeparator());
        var pulls = new Forms.ToolStripMenuItem(Text.L("menu.openPulls")) { Tag="tray.openPulls" };
        pulls.Click += async (_,_) => await RunMenuAsync(() => { OpenPullsDashboard(); return Task.CompletedTask; }); menu.Items.Add(pulls);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(Text.L("windows.showCards") + (shortcut?.Registered == true ? " · Ctrl+Alt+Space" : ""), null, (_, _) => ShowCards());
        var arrangements = new Forms.ToolStripMenuItem(Text.L("menu.arrangements")) { Tag="tray.arrangements" };
        foreach (var saved in Settings.ArrangementList) {
            var row = new Forms.ToolStripMenuItem(saved.Name.Replace("&","&&",StringComparison.Ordinal)) {
                Tag="arrangement.apply:"+saved.Name, Checked=Settings.ArrangementMatches(saved.Name), AccessibleName=saved.Name };
            row.Click += async (_,_) => await RunMenuAsync(() => ApplyArrangementAsync(saved.Name)); arrangements.DropDownItems.Add(row);
        }
        if (Settings.ArrangementList.Length > 0) arrangements.DropDownItems.Add(new Forms.ToolStripSeparator());
        var save = new Forms.ToolStripMenuItem(Text.L("arrangements.save")) { Tag="arrangement.save" };
        save.Click += async (_,_) => await RunMenuAsync(() => {
            if (arrangementNameProvider() is { } name && !string.IsNullOrWhiteSpace(name)) SaveArrangement(name);
            return Task.CompletedTask;
        }); arrangements.DropDownItems.Add(save);
        if (Settings.ArrangementList.Length > 0) {
            var forget = new Forms.ToolStripMenuItem(Text.L("button.remove")) { Tag="arrangement.forgetMenu" };
            foreach (var saved in Settings.ArrangementList) {
                var row = new Forms.ToolStripMenuItem(Text.L("arrangements.forget",saved.Name).Replace("&","&&",StringComparison.Ordinal)) {
                    Tag="arrangement.forget:"+saved.Name, AccessibleName=Text.L("arrangements.forget",saved.Name) };
                row.Click += async (_,_) => await RunMenuAsync(() => { ForgetArrangement(saved.Name); return Task.CompletedTask; }); forget.DropDownItems.Add(row);
            }
            arrangements.DropDownItems.Add(forget);
        }
        menu.Items.Add(arrangements);
        var floating = new Forms.ToolStripMenuItem(Text.L("menu.place.floating")) { Checked = Settings.Floating };
        floating.Click += (_, _) => SetFloating(!Settings.Floating); menu.Items.Add(floating);
        var locked = new Forms.ToolStripMenuItem(Text.L("menu.lock")) { Checked = Settings.Locked };
        locked.Click += (_, _) => SetLocked(!Settings.Locked); menu.Items.Add(locked);
        menu.Items.Add(Text.L("menu.tidy"), null, async (_, _) => await RunMenuAsync(() => ArrangeAsync()));
        var refresh = new Forms.ToolStripMenuItem(Text.L("menu.refresh")) { Tag="tray.refresh" };
        refresh.Click += async (_,_) => await RunMenuAsync(RefreshAllAsync); menu.Items.Add(refresh);
        menu.Items.Add(Text.L("menu.settings"), null, (_, _) => ShowSettings());
        menu.Items.Add(Text.L("menu.quit"), null, async (_, _) => await CloseAsync());
        TrayAttentionModifiers.Attach(menu);
        TrayAttentionRow.SizeMenu(menu);
    }
    private static void DisposeMenuItem(Forms.ToolStripItem item)
    {
        // Dispose while still owned: WinForms releases ownership and marks the item disposed.
        // Detaching first skips that native lifecycle state. Descendants follow the same order.
        if (item is Forms.ToolStripDropDownItem dropdown && dropdown.HasDropDownItems) {
            foreach (var child in dropdown.DropDownItems.Cast<Forms.ToolStripItem>().ToArray()) {
                DisposeMenuItem(child);
            }
        }
        item.Dispose();
    }
    internal void AddCardMenu(Forms.ContextMenuStrip menu)
    {
        menu.Items.Add(new Forms.ToolStripMenuItem(Text.L("menu.cards")) { Enabled = false });
        foreach (var descriptor in RemoteCardCatalog.All) {
            var saved = RemoteCardCatalog.Resolve(Settings, descriptor.Kind);
            var row = new Forms.ToolStripMenuItem(Text.L(descriptor.TitleKey)) {
                Checked = saved?.Enabled == true && RemoteCardCatalog.Available(Settings, descriptor.Kind), Tag = descriptor.Kind,
                ToolTipText = RemoteCardCatalog.Available(Settings, descriptor.Kind) ? "" : Text.L("windows.validationAccount") };
            row.Click += async (_, _) => await RunMenuAsync(() => SetRemoteVisibleAsync(descriptor.Kind, !row.Checked));
            menu.Items.Add(row);
        }
        var work = new Forms.ToolStripMenuItem(Text.L("card.title.workInFlight")) { Tag=CheckoutCatalog.CardID, Checked=WorkInFlightActive,
            Enabled=WorkInFlightAvailable, ToolTipText=WorkInFlightAvailable ? "" : Text.L("windows.wif.conflict") };
        work.Click += async (_,_) => await RunMenuAsync(() => SetWIFVisibleAsync(!work.Checked)); menu.Items.Add(work);
        // Additional legacy/custom cards retain their own visibility and stable IDs.
        foreach (var card in CardOrdering.Remote(Settings.RemoteCardList).Where(card => RemoteCardCatalog.Resolve(Settings, card.Kind)?.Id != card.Id)) {
            var row = new Forms.ToolStripMenuItem(card.Title.Replace("&", "&&", StringComparison.Ordinal)) { Checked = card.Enabled, Tag = card.Id };
            row.Click += async (_, _) => await RunMenuAsync(() => SetCardVisibleAsync(card.Id,!row.Checked));
            menu.Items.Add(row);
        }
        foreach (var kind in new[] { "arc", "ddev", "local" }) {
            var projects = CardOrdering.Projects(Settings.Cards).Where(card => card.Project.Kind == kind).ToArray();
            if (projects.Length == 0) continue;
            var group = new Forms.ToolStripMenuItem(Text.L(kind == "local" ? "menu.group.projects" : "menu.group." + kind) + $" ({projects.Count(card => card.Enabled)}/{projects.Length})");
            foreach (var card in projects) {
                var row = new Forms.ToolStripMenuItem(card.Title.Replace("&", "&&", StringComparison.Ordinal)) { Checked = card.Enabled, Tag = card.Project.Id };
                row.Click += async (_, _) => await RunMenuAsync(() => SetCardVisibleAsync(card.Project.Id,!row.Checked));
                group.DropDownItems.Add(row);
            }
            menu.Items.Add(group);
        }
    }
    internal Task SetRemoteVisibleAsync(string kind, bool visible)
    {
        if (visible && !RemoteCardCatalog.Available(Settings, kind)) {
            var provider = RemoteCardCatalog.All.Single(item => item.Kind == kind).Provider;
            var account = Settings.AccountList.FirstOrDefault(item => item.Provider == provider);
            ShowSettings(account is null ? "new-account:" + provider : "account:" + account.Id);
            return Task.CompletedTask;
        }
        var existing=RemoteCardCatalog.Resolve(Settings,kind);
        if(existing is not null && (!visible || existing.AccountIDs.Length>0))return SetCardVisibleAsync(existing.Id,visible);
        var value=RemoteCardCatalog.SetEnabled(Settings,kind,visible,key=>Text.L(key),NewCardPlacement);
        var id=RemoteCardCatalog.Resolve(value,kind)!.Id;
        return CommitVisibilityAsync(value,id);
    }
    internal Task SetCardVisibleAsync(string id,bool visible)
    {
        if(closing||shuttingDown)return Task.CompletedTask;
        if(id==CheckoutCatalog.CardID && WorkInFlightAvailable)return SetWIFVisibleAsync(visible);
        var project=Settings.Cards.FirstOrDefault(card=>card.Project.Id==id);
        var remote=Settings.RemoteCardList.FirstOrDefault(card=>card.Id==id);
        if(project is null && remote is null)return Task.CompletedTask;
        if(project?.Enabled==visible || remote?.Enabled==visible){settingsWindow?.ReconcileCardVisibility(id);return Task.CompletedTask;}
        var value=Settings with{
            Cards=Settings.Cards.Select(card=>card.Project.Id==id?card with{Enabled=visible}:card).ToArray(),
            RemoteCards=Settings.RemoteCardList.Select(card=>card.Id==id?card with{Enabled=visible}:card).ToArray()
        };
        return CommitVisibilityAsync(value,id);
    }
    private Task CommitVisibilityAsync(DeckSettings value,string id)
    {
        var previous=Settings;
        store.Save(value);Settings=value;
        var project=value.Cards.FirstOrDefault(card=>card.Project.Id==id);
        var remote=value.RemoteCardList.FirstOrDefault(card=>card.Id==id);
        if(project is not null){
            visibilityRevisions[project.Project.Distribution]=visibilityRevisions.GetValueOrDefault(project.Project.Distribution)+1;
            if(project.Enabled)quietReveals.Add(id);
            else{quietReveals.Remove(id);PruneHiddenAttention(id,project.Project.Distribution);}
            var view=cards.FirstOrDefault(card=>card.Reference.Id==id);
            if(view is not null){localConfigurations[id]=project;view.SetDeckVisible(project.Enabled);}
            else RebuildCards();
        }else if(remote is not null){
            var active=RemoteCardCatalog.Active(value,remote);
            if(!active){attention.RemoveScope(id);notifications.ResetScope(id);PruneHiddenAttention(id,null);}
            var old=previous.RemoteCardList.FirstOrDefault(card=>card.Id==id);
            var view=remoteCards.FirstOrDefault(card=>card.CardID==id);
            if(view is not null && old is not null && old.AccountIDs.SequenceEqual(remote.AccountIDs)){
                remoteConfigurations[id]=remote;view.SetDeckVisible(active);
            }else RebuildCards();
        }
        settingsWindow?.ReconcileCardVisibility(id);UpdateAttentionIcon();ScheduleLocalRefresh();ScheduleSharedRefresh();
        return Task.CompletedTask;
    }
    private void PruneHiddenAttention(string id,string? distribution)
    {
        if(distribution is not null){
            var active=AttentionVisibility.ProjectIDs(Settings,distribution).ToHashSet(StringComparer.Ordinal);
            attention.PruneScope("local:"+distribution,item=>active.Count>0 && item.Mark!="docker"
                && (item.Action.CardID is not{ } cardID || active.Contains(cardID)));
        }
        bool Keep(ScopedAlert source)=>!AttentionVisibility.RemoveAfterHide(source.Scope,source.Alert,id,distribution);
        pendingAlerts.RemoveAll(source=>!Keep(source));
        var queued=deliveries.Select(delivery=>delivery with{Sources=delivery.Sources.Where(Keep).ToArray()})
            .Where(delivery=>delivery.Sources.Length>0).ToArray();
        deliveries.Clear();
        if(activeDelivery is{ } current && current.Sources.Any(source=>!Keep(source))){
            var retained=current with{Sources=current.Sources.Where(Keep).ToArray()};
            activeDelivery=null;activeAlert=null;notificationExpiry.Stop();tray?.HideBalloon();
            if(retained.Sources.Length>0)deliveries.Enqueue(retained);
        }
        foreach(var delivery in queued)deliveries.Enqueue(delivery);
        if(activeAlert is null && deliveries.Count>0)nextNotification.Start();
    }
    internal LocalAttentionContext CaptureLocalAttention(string distribution)=>new(distribution,
        visibilityRevisions.GetValueOrDefault(distribution),AttentionVisibility.ProjectIDs(Settings,distribution));
    private static DeckSettings DiscoverCards(DeckSettings value) => RemoteCardCatalog.Synchronize(value, key => Text.L(key), NewCardPlacement);
    private static (double X, double Y) NewCardPlacement(DeckSettings value)
    {
        var area = SystemParameters.WorkArea;
        var occupied = value.Cards.Select(card => new Rect(card.X, card.Y, CardTheme.Width, card.Collapsed ? 72 : 310))
            .Concat(value.RemoteCardList.Select(card => new Rect(card.X, card.Y, CardTheme.Width, card.Collapsed ? 72 : 310)))
            .Concat(value.WorkInFlight is{} aggregate ? new[]{new Rect(aggregate.X,aggregate.Y,CardTheme.Width,aggregate.Collapsed?76:310)} : []).ToArray();
        var best = new Point(area.Left + 24, area.Top + 24); var least = double.MaxValue;
        for (var y = area.Top + 24; y <= Math.Max(area.Top + 24, area.Bottom - 310); y += 24)
            for (var x = area.Left + 24; x <= Math.Max(area.Left + 24, area.Right - CardTheme.Width - 12); x += 24) {
                var candidate = new Rect(x, y, CardTheme.Width + 12, 322);
                var overlap = occupied.Sum(rect => { var intersection = Rect.Intersect(candidate, rect); return intersection.IsEmpty ? 0 : intersection.Width * intersection.Height; });
                if (overlap < least) { best = new(x, y); least = overlap; }
                if (overlap == 0) return (x, y);
            }
        return (best.X, best.Y);
    }
    internal async Task RunMenuAsync(Func<Task> action)
    {
        try { await action(); }
        catch (Exception error) when (error is IOException or InvalidOperationException or System.ComponentModel.Win32Exception) {
            MessageBox.Show(Text.Failure(error), "DevDeck", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }
    internal async Task ExecuteAttentionAsync(AttentionAction action)
    {
        switch (action.Kind) {
            case "open":
                var account = Settings.AccountList.FirstOrDefault(account => account.Id == action.AccountID && account.Enabled && account.Provider == action.Service);
                if (account is not null && action.Url is { } url) dashboardOpener(account.Browser, account.BrowserProfile, url);
                break;
            case "accountSettings":
                var editable = Settings.AccountList.FirstOrDefault(account => account.Id == action.AccountID && account.Provider == action.Service);
                if (editable is not null) { if(AttentionSettingsOpener is{} openSettings)openSettings("account:"+editable.Id);else ShowSettings("account:" + editable.Id); }
                break;
            case "showCard":
                var configured = Settings.Cards.FirstOrDefault(card=>card.Project.Id==action.CardID);
                if(configured is null)break;
                if(!configured.Enabled)await SetCardVisibleAsync(configured.Project.Id,true);
                var card = cards.FirstOrDefault(card => card.Reference.Id == action.CardID);
                if (card is not null) { card.Summon(); await card.ShowLogsAsync(); }
                break;
            case "startDocker": if(AttentionDockerOpener is{} openDocker)openDocker();else DockerDesktop.Open(); break;
            case "openTerminal":
                if(action.Checkout is{} target){OpenCheckoutTerminal(target);break;}
                var project = Settings.Cards.FirstOrDefault(card => card.Enabled && card.Project.Path == action.Path);
                if (project is not null) { if(AttentionTerminalOpener is{} openTerminal)openTerminal(project.Project);else Process.Start(TerminalLaunch.Create(project.Project.Distribution, project.Project.Path)); }
                break;
            case "menu": new AttentionWindow(this, attention.SignalItems).Show(); break;
            case "update": ShowSettings(); break;
        }
    }
    internal async Task<bool> DismissAttentionAsync(AttentionItem item)
    {
        if (closing || shuttingDown || !item.Dismissible || item.Action.Kind!="showCard") return false;
        var project = Settings.Cards.FirstOrDefault(card => card.Enabled && card.Project.Id == item.Action.CardID)?.Project;
        if (project is null) return false;
        WorkerClient? worker=null;
        if(AttentionDismissReady is{} ready)await ready(project.Distribution);
        else worker=await GetWorkerAsync(project.Distribution);
        var current=Settings.Cards.FirstOrDefault(card=>card.Enabled && card.Project.Id==project.Id);
        if(closing || shuttingDown || current is null || (current.Project with{Title=null})!=(project with{Title=null}))return false;
        var context=CaptureLocalAttention(project.Distribution);
        var response=AttentionDismissSender is{} send?await send(project,context.ActiveProjectIDs)
            :await worker!.CallAsync("attention.dismiss",project,activeProjectIDs:context.ActiveProjectIDs);
        ObserveAttention(response.Attention,context);
        return true;
    }
    internal async Task<WorkerClient> GetWorkerAsync(string distribution, bool remote = false)
    {
        var worker = await workers.GetAsync(Settings.Workers.Single(worker => worker.Distribution == distribution),remote);
        var key = (distribution,remote);
        if (!workerSessions.TryGetValue(key, out var previous) || previous != worker) {
            workerSessions[key] = worker;
            if (remote) {
                foreach (var card in Settings.RemoteCardList.Where(card => card.Distribution == distribution)) notifications.ResetScope(card.Id);
            } else notifications.ResetScope("local:" + distribution);
        }
        return worker;
    }
    internal async Task MarkInboxReadAsync(RemoteCardSettings card, string accountID, string[]? threadIDs, CancellationToken cancellation, double? lastReadAt = null, Action<string>? onProgress = null)
    {
        if (card.Kind != "inbox" || !card.AccountIDs.Contains(accountID)) throw new InvalidOperationException(Text.L("windows.threadAccount"));
        var account = Settings.AccountList.Single(account => account.Id == accountID && account.Enabled);
        var credential = RemoteAccountApplicability.Credential(account, Tokens.Read(account));
        await actions.WaitAsync(cancellation);
        try
        {
            var worker = await GetWorkerAsync(card.Distribution,remote:true);
            _ = await worker.CallAsync(lastReadAt is not null ? "remote.markAll" : threadIDs is null ? "remote.markRest" : "remote.markRead", timeout: TimeSpan.FromMinutes(10), cancellation: cancellation,
                onProgress: onProgress, remote: new(card.Id, "inbox", [credential], threadIDs, lastReadAt));
        }
        finally { actions.Release(); }
    }

    internal Task SaveSettingsAsync(DeckSettings value) => SaveSettingsAsync(_ => value);
    internal async Task SaveSettingsAsync(Func<DeckSettings, DeckSettings> update)
    {
        var previous = Settings;
        await actions.WaitAsync();
        try {
        if (closing) return;
        var value = SettingsGeometry.PreserveCurrent(Settings, DiscoverCards(update(Settings)));
        value = value with { Cards = value.Cards.Select(card => {
            var old = previous.Cards.FirstOrDefault(item => item.Project.Id == card.Project.Id);
            var current = Settings.Cards.FirstOrDefault(item => item.Project.Id == card.Project.Id);
            return old is null || current is null ? card : card with {
                X = card.X == old.X ? current.X : card.X, Y = card.Y == old.Y ? current.Y : card.Y,
                Collapsed = card.Collapsed == old.Collapsed ? current.Collapsed : card.Collapsed };
        }).ToArray(), RemoteCards = value.RemoteCardList.Select(card => {
            var old = previous.RemoteCardList.FirstOrDefault(item => item.Id == card.Id);
            var current = Settings.RemoteCardList.FirstOrDefault(item => item.Id == card.Id);
            return old is null || current is null ? card : card with {
                X = card.X == old.X ? current.X : card.X, Y = card.Y == old.Y ? current.Y : card.Y,
                Collapsed = card.Collapsed == old.Collapsed ? current.Collapsed : card.Collapsed };
        }).ToArray(), LogWindows = Settings.LogWindows,
            WorkInFlight = value.WorkInFlight is{} aggregate && Settings.WorkInFlight is{} currentAggregate
                ? aggregate with{Enabled=currentAggregate.Enabled,
                    X=aggregate.X==previous.WorkInFlight?.X?currentAggregate.X:aggregate.X,
                    Y=aggregate.Y==previous.WorkInFlight?.Y?currentAggregate.Y:aggregate.Y,
                    Collapsed=aggregate.Collapsed==previous.WorkInFlight?.Collapsed?currentAggregate.Collapsed:aggregate.Collapsed}
                : Settings.WorkInFlight ?? value.WorkInFlight };
        var languageChanged = Settings.Language != value.Language;
        Text.Use(value.Language);
        value = value with { Workers = value.Workers.Select(worker => worker with { Language = Text.Language }).ToArray(), SeenAlerts = notifications.Seen };
        var resetWorkers = Settings.Workers.Where(old => languageChanged || !value.Workers.Any(item => item == old)).Select(item => item.Distribution).ToArray();
        store.Save(value); Settings = value;
        InvalidateCheckoutMetadata(previous);
        attention.Reset(); lastCheckedAt = null; notifications.ResetObservations(); workerSessions.Clear();
        pendingAlerts.Clear(); deliveries.Clear(); activeAlert = null;activeDelivery=null; notificationBatch.Stop(); notificationExpiry.Stop(); nextNotification.Stop(); tray?.HideBalloon(); UpdateAttentionIcon();
        replaceAllViews=languageChanged;
        replaceDistributions.UnionWith(resetWorkers);
        foreach(var distribution in Settings.Workers.Select(worker=>worker.Distribution))
            visibilityRevisions[distribution]=visibilityRevisions.GetValueOrDefault(distribution)+1;
        foreach (var distribution in resetWorkers) { await workers.ResetAsync(distribution);await settingsChecks.ResetAsync(distribution);await checkoutWorkers.ResetAsync(distribution); }
        foreach (var pair in logWindows.ToArray()) {
            var current = Settings.Cards.FirstOrDefault(card => card.Project.Id == pair.Key);
            if (current is null || languageChanged) pair.Value.Close();
            else pair.Value.UpdateProject(current.Project with { Title = current.Title });
        }
        RebuildCards();
        if (languageChanged)
        {
            if (tray?.ContextMenuStrip is { } menu)
            {
                BuildMenu(menu);
            }
            if (settingsWindow is not null) { await settingsWindow.CloseSettingsAsync(); ShowSettings(); }
        }
        } finally { actions.Release(); }
    }
    internal void SaveNotificationPreferences(DeckSettings value)
    {
        var changedSettings = Settings with { Notifications = value.Notifications, Cards = Settings.Cards.Select(card => {
            var changed = value.Cards.FirstOrDefault(item => item.Project.Id == card.Project.Id);
            return changed is null ? card : card with { NotifiesWhenDown = changed.NotifiesWhenDown, NotifiesStartFailed = changed.NotifiesStartFailed };
        }).ToArray(), Accounts = Settings.AccountList.Select(account => {
            var changed = value.AccountList.FirstOrDefault(item => item.Id == account.Id);
            return changed is null ? account : account with { NotifiesReviewRequests = changed.NotifiesReviewRequests,
                NotifiesBlocked = changed.NotifiesBlocked, NotifiesFailedRuns = changed.NotifiesFailedRuns };
        }).ToArray() };
        store.Save(changedSettings); Settings = changedSettings; notifications.ResetObservations();
        pendingAlerts.Clear(); deliveries.Clear(); activeAlert = null;activeDelivery=null;
        notificationBatch.Stop(); notificationExpiry.Stop(); nextNotification.Stop(); tray?.HideBalloon();
    }
    internal void TestNotification()
    {
        if (!Settings.Notifications) return;
        deliveries.Enqueue(new([new("synthetic:test",new("test", "blocked", "devdeck", Text.L("notify.test.title"), Text.L("notify.test.subtitle"),
            Text.L("notify.test.body"), "", new("menu"), true))],Test:true));
        DeliverNotification();
    }

    internal async Task<WorkerSettings> EnsureWorkerAsync(string distribution)
    {
        if (Settings.Workers.FirstOrDefault(worker => worker.Distribution == distribution) is { } existing) return existing;
        var archive = Path.Combine(AppContext.BaseDirectory, "workers", await RuntimeInstaller.PackageNameAsync(distribution));
        if (!File.Exists(archive)) throw new IOException(Text.L("windows.workerPackageMissing"));
        var installed = (await RuntimeInstaller.InstallAsync(distribution, archive)) with { Language = Text.Language };
        _ = await workers.GetAsync(installed);
        Settings = Settings with { Workers = Settings.Workers.Append(installed).ToArray() };
        store.Save(Settings);
        return installed;
    }

    internal async Task CheckAsync(string report)
    {
        var results = new List<object>();
        var remoteResults = new List<object>();
        if (tray?.Added != true) throw new IOException("The native Windows tray icon is unavailable.");
        var powerOffRoutes=CaptureDDEVPowerOffRoutes();
        foreach(var route in powerOffRoutes)
            if(!(await GetWorkerAsync(route.Distribution)).Capabilities.Contains(PowerOffValidation.Capability,StringComparer.Ordinal))
                throw new IOException("Installed DDEV worker does not advertise the qualified poweroff transaction.");
        foreach (var card in LocalViews)
        {
            await card.RefreshAsync();
            if (card.Latest is null || !card.LastRefreshSucceeded) throw new IOException("A project card could not load its status.");
            if (!WidgetWindow.IsExcluded(card)) throw new IOException("A widget card is still eligible for Alt+Tab.");
            results.Add(new { cardID = card.Reference.Id, distribution = card.Reference.Distribution, status = card.Latest.State, versionsLine = card.Latest.VersionsLine,
                localEditorAvailable = card.Latest.LocalEditorURL is not null, checkSummaryAvailable = card.Latest.CheckSummary is not null, checkedAtAvailable = card.Latest.CheckedAt is not null,
                localFolderConfigured = card.Reference.HasLocalFolder, desktopModeApplied = card.ModeApplied, excludedFromSwitcher = true,
                phoneAvailable = card.CurrentPhoneLink.Address is not null, phoneIssue = card.CurrentPhoneLink.Issue.ToString() });
        }
        foreach (var card in RemoteViews) {
            await card.RefreshAsync();
            var snapshot = card.Latest ?? throw new IOException("A remote card could not load its snapshot.");
            if (!WidgetWindow.IsExcluded(card)) throw new IOException("A remote widget is still eligible for Alt+Tab.");
            remoteResults.Add(new { kind = snapshot.Kind, total = snapshot.Total, rows = snapshot.Rows.Length,
                failures = snapshot.Failures.Select(failure => failure.Kind).ToArray(), excludedFromSwitcher = true });
        }
        if (LocalViews.Length > 0 && (!localPolling.IsEnabled || localPolling.Interval != LocalRefreshBatch.Interval)) throw new IOException("Native local polling loop is unavailable.");
        foreach (var distribution in Settings.RemoteCardList.Where(card => RemoteCardCatalog.Active(Settings,card)).Select(card => card.Distribution).Distinct()) {
            if (ReferenceEquals(await GetWorkerAsync(distribution),await GetWorkerAsync(distribution,remote:true)))
                throw new IOException("Remote API can block the local worker transport.");
        }
        foreach(var runtime in Settings.Workers) {
            if(!(await GetWorkerAsync(runtime.Distribution,remote:true)).Capabilities.Contains("attention.inboxReadTarget",StringComparer.Ordinal))
                throw new IOException("Installed remote worker does not advertise source-bound Inbox read targets.");
            var checker=await settingsChecks.GetAsync(runtime);
            if(ReferenceEquals(checker,await GetWorkerAsync(runtime.Distribution))||ReferenceEquals(checker,await GetWorkerAsync(runtime.Distribution,remote:true)))
                throw new IOException("Settings check cancellation can interrupt another worker transport.");
            var checkout=await checkoutWorkers.GetAsync(runtime);
            if(!checkout.Capabilities.Contains(CheckoutValidation.Capability,StringComparer.Ordinal)
                ||ReferenceEquals(checkout,checker)||ReferenceEquals(checkout,await GetWorkerAsync(runtime.Distribution))||ReferenceEquals(checkout,await GetWorkerAsync(runtime.Distribution,remote:true)))
                throw new IOException("Installed checkout scanner capability or independent transport is unavailable.");
        }
        foreach(var card in Settings.Cards.Where(card=>card.Enabled&&card.Project.Kind=="arc")) {
            var answer=await CheckProjectAsync(card.Project,CancellationToken.None);
            if(answer.ProjectID!=card.Project.Id||answer.CheckSummary is null||answer.CheckedAt is null)throw new IOException("Original settings check is unavailable.");
        }
        await File.WriteAllTextAsync(report, JsonSerializer.Serialize(new { nativeWindows = true, cards = results, remoteCards = remoteResults, trayRegistered = true,
            localPollSeconds = localPolling.Interval.TotalSeconds, independentLocalRemoteChannels = true,independentSettingsChecks=true,
            attentionItems = attention.SignalItems.Length, attentionBadge = attention.BadgeCount,
            powerOffTransactionSupported=true,powerOffConfiguredDistributions=powerOffRoutes.Length,
            checkoutScannerSupported=true,checkoutConfiguredDistributions=Settings.Workers.Length,checkoutCommandsInvoked=WorkInFlightActive,
            independentCheckoutChannel=true,sharedRemoteRefreshOwned=true,
            inboxReadTargetSupported=true,inboxReadMutationInvoked=false,
            powerOffLifecycleInvoked=false,releaseQualified = false }, new JsonSerializerOptions { WriteIndented = true }));
    }

    internal async Task CloseAsync()
    {
        if (closing || shuttingDown) return;
        shuttingDown = true;
        if (settingsWindow is not null && !await settingsWindow.CloseSettingsAsync()) { shuttingDown=false;return; }
        closing = true;
        powerOffLifetime.Cancel();
        checkoutLifetime.Cancel(); sharedPolling.Stop();
        localPolling.Stop();
        notificationBatch.Stop(); notificationExpiry.Stop(); nextNotification.Stop();
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged -= DisplayChanged;
        foreach (var card in cards) card.Close();
        foreach (var card in remoteCards) card.Close();
        workInFlightCard?.Close();
        foreach (var window in logWindows.Values.ToArray()) window.Close();
        tray?.Dispose();
        shortcut?.Dispose();
        await settingsChecks.DisposeAsync();
        await checkoutWorkers.DisposeAsync();
        await workers.DisposeAsync();
        application.Shutdown();
    }
    internal void CloseViews()
    {
        localPolling.Stop();
        sharedPolling.Stop(); checkoutLifetime.Cancel();workInFlightCard?.Close();
        notificationBatch.Stop();notificationExpiry.Stop();nextNotification.Stop();
        foreach (var card in cards) card.Close(); foreach (var card in remoteCards) card.Close();
        foreach (var window in logWindows.Values.ToArray()) window.Close();
    }
}
