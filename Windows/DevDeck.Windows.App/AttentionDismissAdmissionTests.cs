using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// The real choice dispatcher waits at an owned acquisition seam; no worker is started.
internal static class AttentionDismissAdmissionTests
{
    private const string Distribution = "Owned Linux";
    private const string ProjectID = "owned.dismiss";

    internal static async Task RunRedAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        try { await HeldHideAsync(application, checks); }
        finally { Text.Use(language); }
    }

    internal static async Task RunAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        try {
            await HeldHideAsync(application, checks);
            await ChangedTargetAsync(application, checks);
            await ClosingAsync(application, checks);
            await CompatibleChangesAsync(application, checks);
            await FailedWriteAsync(application, checks);
        } finally { Text.Use(language); }
    }

    private static async Task HeldHideAsync(Application application, List<object> checks)
    {
        using var fixture = new Owned(application);
        var ready = Pending();
        fixture.Controller.AttentionDismissReady = distribution => {
            fixture.ReadyDistributions.Add(distribution); return ready.Task;
        };
        var operation = fixture.ChooseAsync();
        try {
            await Turns();
            Require(!operation.IsCompleted && fixture.ReadyDistributions.SequenceEqual(new[] { Distribution }) && fixture.SendCalls == 0,
                "Dismiss fixture did not hold actual production worker acquisition before the RPC.");
            var owner = fixture.Controller.AllLocalViews.Single(card => card.Reference.Id == ProjectID);
            var sibling = fixture.Controller.AllLocalViews.Single(card => card.Reference.Id == "owned.sibling");
            var ownerHandle = Handle(owner); var siblingHandle = Handle(sibling);
            await fixture.Controller.SetCardVisibleAsync(ProjectID, false);
            Require(!owner.DeckVisible && !owner.IsVisible && ReferenceEquals(owner, fixture.Controller.AllLocalViews.Single(card => card.Reference.Id == ProjectID))
                && Handle(owner) == ownerHandle && sibling.IsVisible && Handle(sibling) == siblingHandle,
                "Fast hide did not preserve the same synthetic owner and unrelated sibling while dismissal awaited acquisition.");
            ready.TrySetResult(true);
            var admitted = await operation;
            Require(!admitted && fixture.SendCalls == 0,
                "Dismiss admitted a project hidden during worker acquisition; admitted=" + admitted + ", RPCs=" + fixture.SendCalls + ".");
            fixture.RequireNoCompletedRead(); fixture.RequireSiblingScopes(); fixture.RequireNoWorkers();
            checks.Add(new { name = "attention.dismiss.heldFastHide", actualAcquisitionAwait = true,
                productionVisibilitySetter = true, retainedHwndAndSibling = true, noDismissRpcAfterHide = true, falseAdmission = true });
        } finally { ready.TrySetResult(true); await operation; }
    }

    private static async Task ChangedTargetAsync(Application application, List<object> checks)
    {
        var variants = new[] { "removed", "path", "distribution", "kind" };
        foreach (var variant in variants) {
            using var fixture = new Owned(application);
            var ready = Pending();
            fixture.Controller.AttentionDismissReady = distribution => {
                fixture.ReadyDistributions.Add(distribution); return ready.Task;
            };
            var operation = fixture.ChooseAsync();
            try {
                await Turns(); Require(!operation.IsCompleted && fixture.SendCalls == 0, "Changed-target fixture did not reach the real acquisition await.");
                fixture.Commit(fixture.Controller.Settings with {
                    Cards = fixture.Controller.Settings.Cards.Where(card => variant != "removed" || card.Project.Id != ProjectID)
                        .Select(card => card.Project.Id != ProjectID ? card : card with { Project = variant switch {
                            "path" => card.Project with { Path = "/owned/replacement" },
                            "distribution" => card.Project with { Distribution = "Other Linux" },
                            "kind" => card.Project with { Kind = "ddev" },
                            _ => card.Project
                        } }).ToArray()
                });
                ready.TrySetResult(true);
                Require(!await operation && fixture.SendCalls == 0, "Dismiss wrote the stale " + variant + " project after worker acquisition.");
                fixture.RequireNoCompletedRead(); fixture.RequireSiblingScopes(); fixture.RequireNoWorkers();
            } finally { ready.TrySetResult(true); await operation; }
        }
        checks.Add(new { name = "attention.dismiss.changedCurrentTuple", cases = variants, exactIdDistributionKindPath = true,
            revalidateAfterActualAwait = true, noRpcAndFalseAdmission = true, unrelatedScopesRetained = true });
    }

    private static async Task ClosingAsync(Application application, List<object> checks)
    {
        foreach (var field in new[] { "closing", "shuttingDown" }) {
            using (var fixture = new Owned(application)) {
                SetField(fixture.Controller, field, true);
                try {
                    Require(!await fixture.ChooseAsync() && fixture.ReadyDistributions.Count == 0 && fixture.SendCalls == 0,
                        "Initial " + field + " controller admitted dismiss or acquired a worker.");
                    fixture.RequireNoCompletedRead(); fixture.RequireSiblingScopes(); fixture.RequireNoWorkers();
                } finally { SetField(fixture.Controller, field, false); }
            }
            using (var fixture = new Owned(application)) {
                var ready = Pending();
                fixture.Controller.AttentionDismissReady = distribution => {
                    fixture.ReadyDistributions.Add(distribution); return ready.Task;
                };
                var operation = fixture.ChooseAsync();
                try {
                    await Turns(); Require(!operation.IsCompleted, "Closing fixture did not reach acquisition await.");
                    SetField(fixture.Controller, field, true); ready.TrySetResult(true);
                    Require(!await operation && fixture.SendCalls == 0, "Controller started closing during acquisition but still sent dismiss.");
                    fixture.RequireNoCompletedRead(); fixture.RequireSiblingScopes(); fixture.RequireNoWorkers();
                } finally { ready.TrySetResult(true); await operation; SetField(fixture.Controller, field, false); }
            }
        }
        checks.Add(new { name = "attention.dismiss.closingGuards", closingAndShuttingDown = true,
            beforeAndAfterAcquisition = true, noRpcAndNoCompletedRead = true, noActualShutdown = true });
    }

    private static async Task CompatibleChangesAsync(Application application, List<object> checks)
    {
        using var fixture = new Owned(application);
        var ready = Pending();
        fixture.Controller.AttentionDismissReady = distribution => {
            fixture.ReadyDistributions.Add(distribution); return ready.Task;
        };
        var operation = fixture.ChooseAsync();
        try {
            await Turns(); Require(!operation.IsCompleted, "Compatible-change fixture did not reach acquisition await.");
            fixture.Commit(fixture.Controller.Settings with { Cards = fixture.Controller.Settings.Cards.Select(card => card.Project.Id == ProjectID
                ? card with { Title = "Renamed current card", Project = card.Project with { Title = "Renamed display reference" }, X = 128, Y = 160, Collapsed = true } : card).ToArray() });
            ready.TrySetResult(true);
            Require(await operation && fixture.SendCalls == 1 && fixture.LastProject is { } project
                && project.Id == ProjectID && project.Distribution == Distribution && project.Kind == "local" && project.Path == "/owned/app"
                && fixture.LastActiveIDs!.SequenceEqual(new[] { ProjectID, "owned.sibling" }.Order(StringComparer.Ordinal)),
                "Unchanged physical target with display edits lost its dismiss, exact project tuple or current active-ID context.");
            Require(!fixture.Scope("local:" + Distribution).Any(item => item.Action.CardID == ProjectID)
                && fixture.Controller.LastCheckedAt > fixture.CheckedAt, "Completed valid dismiss did not observe its actual scoped response.");
            fixture.RequireSiblingScopes(); fixture.RequireNoWorkers();
            checks.Add(new { name = "attention.dismiss.compatibleDisplayChanges", titlePlacementCompactPreserveAdmission = true,
                exactProjectAndCurrentActiveIds = true, oneRpc = true, ownResponseObserved = true, siblingScopesAndPhysicalStatusRetained = true });
        } finally { ready.TrySetResult(true); await operation; }
    }

    private static async Task FailedWriteAsync(Application application, List<object> checks)
    {
        using var fixture = new Owned(application);
        fixture.SendFailure = new WorkerException("disconnected", "owned lost dismiss response");
        try {
            await fixture.ChooseAsync();
            throw new IOException("Lost dismiss response did not propagate its existing transport failure.");
        } catch (WorkerException error) when (error.Code == "disconnected") { }
        Require(fixture.SendCalls == 1 && fixture.Scope("local:" + Distribution).Any(item => item.Action.CardID == ProjectID),
            "Failed dismiss replayed a write or retired the original attention without a successful receipt.");
        fixture.RequireNoCompletedRead(); fixture.RequireSiblingScopes(); fixture.RequireNoWorkers();
        checks.Add(new { name = "attention.dismiss.lostResponse", oneAttemptNoReplay = true, originalFailurePropagates = true,
            noFalseCompletionClock = true, selectedAndSiblingScopesRetained = true });
    }

    private sealed class Owned : IDisposable
    {
        private readonly string path = Path.Combine(Path.GetTempPath(), "devdeck-attention-dismiss-" + Guid.NewGuid().ToString("N") + ".json");
        internal readonly SettingsStore Store;
        internal readonly DeckController Controller;
        internal readonly AttentionItem Selected = Item(ProjectID, dismissible: true);
        private readonly AttentionItem sameSibling = Item("owned.sibling", dismissible: false);
        private readonly AttentionItem otherSibling = Item("other.project", dismissible: false);
        private readonly Dictionary<string, ProjectStatus?> statuses;
        internal readonly DateTimeOffset? CheckedAt;
        internal readonly List<string> ReadyDistributions = [];
        internal int SendCalls;
        internal ProjectReference? LastProject;
        internal string[]? LastActiveIDs;
        internal Exception? SendFailure;

        internal Owned(Application application)
        {
            Store = new(path);
            Store.Save(new(1, [new(Distribution, "/owned/runtime"), new("Other Linux", "/owned/runtime")], [
                new(new(ProjectID, Distribution, "local", "/owned/app"), "Owned selected", X:64, Y:80),
                new(new("owned.sibling", Distribution, "local", "/owned/sibling"), "Owned sibling", X:520, Y:80),
                new(new("other.project", "Other Linux", "local", "/owned/other"), "Other distro", X:976, Y:80)
            ], Language:"en", Notifications:false));
            Controller = new(application, Store, live:false);
            typeof(DeckController).GetMethod("RebuildCards", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(Controller, null);
            foreach (var owner in Controller.AllLocalViews)
                owner.ApplySnapshot(new(owner.Reference.Id, "running", "owned-retained", null, null, null));
            statuses = Controller.AllLocalViews.ToDictionary(owner => owner.Reference.Id, owner => owner.Latest, StringComparer.Ordinal);
            Controller.ObserveAttention(new("local:" + Distribution, [Selected, sameSibling], []));
            Controller.ObserveAttention(new("local:Other Linux", [otherSibling], []));
            SetField(Controller, "lastCheckedAt", DateTimeOffset.FromUnixTimeSeconds(1000)); CheckedAt = Controller.LastCheckedAt;
            Controller.AttentionDismissReady = distribution => { ReadyDistributions.Add(distribution); return Task.CompletedTask; };
            Controller.AttentionDismissSender = (project, ids) => {
                SendCalls++; LastProject = project; LastActiveIDs = ids.ToArray();
                if (SendFailure is { } failure) return Task.FromException<WorkerResponse>(failure);
                return Task.FromResult(new WorkerResponse(1, "owned-dismiss", project.Distribution, null, null, null, null,
                    Attention:new("local:" + project.Distribution, [sameSibling], [])));
            };
            Controller.InboxTokenReader = _ => throw new IOException("Unexpected dismiss credential access.");
            Controller.InboxWriteSender = (_, _, _, _) => throw new IOException("Unexpected dismiss provider access.");
        }
        internal Task<bool> ChooseAsync() => Controller.ExecuteAttentionChoiceAsync(Selected, AttentionChoices.Alternate(Selected));
        internal void Commit(DeckSettings settings) { Store.Save(settings); typeof(DeckController).GetProperty("Settings", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(Controller, settings); }
        internal AttentionItem[] Scope(string scope) => Get<Dictionary<string, AttentionItem[]>>(Get<AttentionTracker>(Controller, "attention"), "signals")[scope];
        internal void RequireNoCompletedRead() => Require(Controller.LastCheckedAt == CheckedAt, "Rejected/failed dismiss advanced a successful-read clock.");
        internal void RequireSiblingScopes()
        {
            Require(Scope("local:" + Distribution).Contains(sameSibling) && Scope("local:Other Linux").SequenceEqual(new[] { otherSibling })
                && Controller.AllLocalViews.All(owner => ReferenceEquals(owner.Latest, statuses[owner.Reference.Id])),
                "Dismiss changed an unrelated scope or the retained physical project statuses.");
        }
        internal void RequireNoWorkers()
        {
            var managers = typeof(DeckController).GetFields(BindingFlags.Instance | BindingFlags.NonPublic).Where(field => field.FieldType == typeof(WorkerManager));
            var count = managers.Select(field => field.GetValue(Controller)).Sum(manager => ((IDictionary)typeof(WorkerManager)
                .GetField("workers", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(manager)!).Count);
            Require(count == 0 && !Controller.LocalPollEnabled && !Controller.SharedPollEnabled,
                "Synthetic dismiss fixture started a real worker or polling loop.");
        }
        public void Dispose()
        {
            Controller.CloseViews();
            foreach (var file in new[] { path, path + ".bak" }) if (File.Exists(file)) File.Delete(file);
        }
    }

    private static AttentionItem Item(string id, bool dismissible) => new("project:" + id + ":start", "project:" + id + ":start",
        "needsFixing", "project", "Owned " + id, "Original retained watch episode", 1000, new("showCard", CardID:id), true, dismissible);
    private static T Get<T>(object owner, string name) => (T)owner.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(owner)!;
    private static void SetField(object owner, string name, object value) => owner.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(owner, value);
    private static nint Handle(Window owner) => new WindowInteropHelper(owner).Handle;
    private static TaskCompletionSource<bool> Pending() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static async Task Turns() { for (var turn = 0; turn < 3; turn++) await Dispatcher.Yield(DispatcherPriority.Background); }
    private static void Require(bool value, string message) { if (!value) throw new IOException(message); }
}
