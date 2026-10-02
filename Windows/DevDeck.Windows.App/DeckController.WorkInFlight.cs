using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed partial class DeckController
{
    private readonly WorkerManager checkoutWorkers = new();
    private readonly CancellationTokenSource checkoutLifetime = new();
    private readonly DispatcherTimer sharedPolling = new();
    private readonly SharedDeckRefreshLoop sharedRefresh = new();
    private Func<string, Task<IWorkInFlightEndpoint>> checkoutEndpointFactory = null!;
    private Action<CheckoutTarget> checkoutTerminalOpener = null!;
    private WorkInFlightCard? workInFlightCard;
    private WorkInFlightSnapshot checkoutCache = new([], 0, null);
    private Task<WorkInFlightSnapshot>? checkoutRead;
    private long checkoutRevision;
    private bool sharedScheduled, sharedNeedsPass;
    private TimeSpan sharedDelay = TimeSpan.FromSeconds(120);
    internal WorkInFlightCard? WorkInFlightView => workInFlightCard;
    internal bool WorkInFlightAvailable => !Settings.Cards.Any(card => card.Project.Id == CheckoutCatalog.CardID)
        && !Settings.RemoteCardList.Any(card => card.Id == CheckoutCatalog.CardID);
    internal bool WorkInFlightActive => WorkInFlightAvailable && Settings.WorkInFlight?.Enabled == true;
    internal bool SharedPollEnabled => sharedPolling.IsEnabled;
    internal TimeSpan SharedPollInterval => sharedPolling.Interval;

    private void InitializeCheckouts(Func<string, Task<IWorkInFlightEndpoint>>? endpointFactory, Action<CheckoutTarget>? terminalOpener)
    {
        checkoutEndpointFactory = endpointFactory ?? CaptureCheckoutEndpointAsync;
        checkoutTerminalOpener = terminalOpener ?? (target => {
            try { System.Diagnostics.Process.Start(TerminalLaunch.Create(target.Distribution, target.Path)); }
            catch (System.ComponentModel.Win32Exception) { System.Diagnostics.Process.Start(TerminalLaunch.Create(target.Distribution, target.Path, false)); }
        });
        sharedPolling.Tick += async (_, _) => await RefreshSharedAsync();
    }

    private void ReconcileWorkInFlight()
    {
        if (replaceAllViews && workInFlightCard is not null) { workInFlightCard.Close(); workInFlightCard = null; }
        if (Settings.WorkInFlight is not { } preference || !WorkInFlightAvailable) {
            if (workInFlightCard is not null) { workInFlightCard.Close(); workInFlightCard = null; }
            return;
        }
        if(workInFlightCard is null){
            workInFlightCard=new(this,preference,live);
            var limitFailure=false;
            if(checkoutCache.CheckedAt is null){
                try{checkoutCache=checkoutCache with{SelectedCount=CheckoutCatalog.Select(Settings).Length,Checking=preference.Enabled};}
                catch(IOException){limitFailure=true;}
            }
            workInFlightCard.ApplySnapshot(checkoutCache);
            if(limitFailure)workInFlightCard.ApplyFailure(new IOException(Text.L("windows.wif.limit")));
        }
        workInFlightCard.Left = preference.X; workInFlightCard.Top = preference.Y;
        workInFlightCard.SetCollapsed(preference.Collapsed); workInFlightCard.ApplyMode(Settings.Floating);
        workInFlightCard.SetDeckVisible(preference.Enabled);
    }

    internal Task SetWIFVisibleAsync(bool enabled)
    {
        if (closing || shuttingDown) return Task.CompletedTask;
        if (enabled && !WorkInFlightAvailable) throw new InvalidOperationException(Text.L("windows.wif.conflict"));
        if (Settings.WorkInFlight?.Enabled == enabled || Settings.WorkInFlight is null && !enabled) {
            settingsWindow?.ReconcileCardVisibility(CheckoutCatalog.CardID); return Task.CompletedTask;
        }
        var changed = CheckoutCatalog.SetEnabled(Settings, enabled, NewCardPlacement);
        store.Save(changed); Settings = changed; checkoutRevision++;
        if (!enabled) { attention.RemoveScope(CheckoutCatalog.CardID); UpdateAttentionIcon(); }
        ReconcileWorkInFlight(); settingsWindow?.ReconcileCardVisibility(CheckoutCatalog.CardID);
        ScheduleSharedRefresh();
        return Task.CompletedTask;
    }

    internal void OpenWorkInFlightTerminal(CheckoutEntry entry) => OpenCheckoutTerminal(entry.Target);
    internal void OpenCheckoutTerminal(CheckoutTarget target)
    {
        if (!closing && WorkInFlightActive && CheckoutCatalog.CurrentTarget(Settings, target)) checkoutTerminalOpener(target);
    }

    private async Task<IWorkInFlightEndpoint> CaptureCheckoutEndpointAsync(string distribution)
    {
        var runtime = Settings.Workers.Single(worker => worker.Distribution == distribution);
        return new CheckoutEndpoint(await checkoutWorkers.GetAsync(runtime));
    }

    private sealed class CheckoutEndpoint(WorkerClient worker) : IWorkInFlightEndpoint
    {
        public string[] Capabilities => worker.Capabilities;
        public async Task<CheckoutResult> ReadAsync(CheckoutRequest request, CancellationToken cancellation) =>
            (await worker.CallAsync(CheckoutValidation.Capability, timeout: TimeSpan.FromSeconds(75),
                cancellation: cancellation, checkout: request)).Checkout ?? throw new WorkerException("invalidResponse", "Checkout result is missing.");
    }

    internal Task<WorkInFlightSnapshot> FetchWorkInFlightAsync(CancellationToken cancellation)
        => checkoutRead is { IsCompleted: false } ? checkoutRead : checkoutRead = ReadCheckoutsAsync(cancellation);

    private async Task<WorkInFlightSnapshot> ReadCheckoutsAsync(CancellationToken cancellation)
    {
        if (!WorkInFlightActive || closing) return checkoutCache;
        var selected = CheckoutCatalog.Select(Settings);
        var revision = checkoutRevision; var pass = Guid.NewGuid().ToString("N");
        var oldTime = checkoutCache.CheckedAt;
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellation, checkoutLifetime.Token);
        bool Current() => !closing && !shuttingDown && !checkoutLifetime.IsCancellationRequested && WorkInFlightActive && checkoutRevision == revision;
        var coordinator = new WorkInFlightScanCoordinator(checkoutEndpointFactory);
        workInFlightCard?.SetChecking();
        var result = await coordinator.RunAsync(selected, pass, Current, lifetime.Token, route => {
            KeepCurrent(route);
            if (Current()) workInFlightCard?.ApplySnapshot(checkoutCache with { Checking = true, CheckedAt = oldTime });
        });
        KeepCurrent(result.Entries);
        var complete = result.Completed && Current();
        checkoutCache = checkoutCache with { SelectedCount = CheckoutCatalog.Select(Settings).Length,
            CheckedAt = complete ? DateTimeOffset.UtcNow.ToUnixTimeSeconds() : oldTime, Checking = false, Stale = !complete };
        if (complete) {
            checkoutCache = checkoutCache with { Entries = result.Entries };
            var signals = result.Entries.SelectMany(entry => entry.Result.Signals.Select(item => CheckoutWords.Signal(item,entry.Reference,entry.State!,Text.Resources,entry.Result.CheckedAt))).ToArray();
            ObserveAttention(new(CheckoutCatalog.CardID, signals, []));
        }
        return checkoutCache;

        void KeepCurrent(CheckoutEntry[] completed)
        {
            var current = CheckoutCatalog.Select(Settings);
            bool Same(CheckoutReference left,CheckoutReference right)=>left.ProjectID==right.ProjectID && left.Distribution==right.Distribution && left.Path==right.Path;
            var incoming = completed.Where(entry => current.Any(reference => Same(reference,entry.Reference))).ToDictionary(entry => entry.Reference.ProjectID, StringComparer.Ordinal);
            var retained = checkoutCache.Entries.Where(entry => current.Any(reference => Same(reference,entry.Reference))).ToDictionary(entry => entry.Reference.ProjectID, StringComparer.Ordinal);
            foreach (var entry in incoming) retained[entry.Key] = entry.Value;
            checkoutCache = new(current.Where(reference => retained.ContainsKey(reference.ProjectID)).Select(reference => retained[reference.ProjectID] with{Reference=reference}).ToArray(), current.Length, oldTime, true, true);
        }
    }

    private bool SharedActive() => RemoteViews.Length > 0 || WorkInFlightActive;
    internal void ScheduleSharedRefresh()
    {
        if (!live || closing || shuttingDown) return;
        if (!SharedActive()) { sharedPolling.Stop(); return; }
        if (sharedRefresh.IsRunning) { sharedNeedsPass = true; return; }
        if (sharedScheduled) return;
        sharedScheduled = true;
        application.Dispatcher.BeginInvoke(new Action(async () => {
            sharedScheduled = false;
            if (!closing && !shuttingDown && SharedActive()) await RefreshSharedAsync();
        }), DispatcherPriority.Background);
    }

    private async Task RefreshSharedAsync()
    {
        if (!live || closing || shuttingDown) return;
        sharedPolling.Stop();
        var sources = SharedRefreshPolicy.SourceOrder(Settings).Select(saved => {
            var owner = remoteCards.FirstOrDefault(card => card.CardID == saved.Id);
            return new SharedRefreshSource(saved.Id,
                () => !closing && owner is not null && remoteCards.Contains(owner) && owner.DeckVisible && !owner.IsMutating,
                async () => { await owner!.RefreshAsync(); return new(owner.LastRefreshFailures, owner.LastServerHint); });
        }).ToArray();
        var outcome = await sharedRefresh.RunAsync(sources, Settings.RefreshSeconds,
            async () => { foreach (var window in logWindows.Values.ToArray()) if (WindowVisibility.CanRead(window)) await window.RefreshAsync(); },
            async () => { if (WorkInFlightActive && workInFlightCard is { CanRefresh: true } owner) await owner.RefreshAsync(); },
            () => !closing && !shuttingDown);
        sharedDelay = outcome.Delay;
        if (!closing && !shuttingDown && SharedActive()) {
            sharedPolling.Interval = sharedDelay; sharedPolling.Start();
            if (sharedNeedsPass) { sharedNeedsPass = false; ScheduleSharedRefresh(); }
        }
    }

    private void InvalidateCheckoutMetadata(DeckSettings previous)
    {
        bool same;try{same=CheckoutCatalog.Select(previous).SequenceEqual(CheckoutCatalog.Select(Settings));}catch(IOException){same=false;}
        if (same && previous.Workers.SequenceEqual(Settings.Workers) && previous.Language == Settings.Language) return;
        checkoutRevision++; workInFlightCard?.Invalidate();
        attention.RemoveScope(CheckoutCatalog.CardID);
        ScheduleSharedRefresh();
    }
}
