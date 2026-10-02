using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Actual legacy account baselines and acceptance. Every dependency, file and window belongs to this fixture.
internal static class AccountCompletenessTests
{
    private const string Distribution = "Owned Legacy Linux";
    private const string Replacement = "Owned legacy replacement draft";
    private const string LocalID = "owned.legacy.local";
    private static readonly TimeSpan Deadline = TimeSpan.FromSeconds(5);

    // Exactly three qualified families; historical premise/body receipts are not passed-test counts.
    internal static async Task RunAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        try {
            Text.Use("en");
            await EndpointGreenAsync(application, checks, "github");
            await EndpointGreenAsync(application, checks, "gitlab");
            await ReplacementGreenAsync(application, checks);
        } finally { Text.Use(language); }
    }

    internal static async Task RunRedAsync(Application application, List<object> checks, string scenario)
    {
        var language = Text.Language;
        try {
            Text.Use("en");
            switch (scenario) {
                case "endpoint-github": await EndpointAsync(application, checks, "github"); break;
                case "endpoint-gitlab": await EndpointAsync(application, checks, "gitlab"); break;
                case "replacement-long-id": await ReplacementAsync(application, checks); break;
                case "replacement-followup": await RawEndpointReplacementAsync(application, "github", checks); break;
                default: throw new ArgumentException("Unknown account-completeness baseline.", nameof(scenario));
            }
        } finally { Text.Use(language); }
    }

    private static async Task EndpointGreenAsync(Application application, List<object> checks, string provider)
    {
        var endpoint = provider == "github" ? "https://api.github.com/" : "https://gitlab.example.test/team/";
        await using var owned = new Owned(application, provider, "owned.legacy." + provider, endpoint, replacementBody: false);
        await owned.ShowAsync();
        await owned.HoldActionsAsync();
        Require(owned.ActionsHeld, "Successful metadata qualification lacks a positively acquired controller gate.");
        owned.Form.TokenDraft = Replacement;
        var previousSettings = owned.Controller.Settings;
        var originalTarget = owned.Account.CredentialTarget;
        var currentForm = owned.Form;
        var label = Field<TextBox>(currentForm, "label");
        var address = Field<TextBox>(currentForm, "endpoint");
        var queries = owned.PresenceQueries;
        var generation = owned.Binding.OwnerGeneration();
        var revisions = new[] { Field<long>(currentForm, "organizationRevision"), Field<long>(currentForm, "repositoryRevision") };
        var firstLabel = "Owned renamed " + provider;
        label.Text = firstLabel;
        Require(currentForm.HasUncommittedChanges && BaseField<DispatcherTimer>(currentForm, "debounce").IsEnabled
            && address.Text == endpoint && currentForm.TokenDraft == Replacement
            && owned.Binding.OwnerCurrent() && owned.ActionsHeld,
            "The successful label-only draft did not retain the raw endpoint/password/current parent and held gate.");
        BaseField<DispatcherTimer>(currentForm, "debounce").Stop();
        // The old-red held-gate premise was captured. An admitted real SaveSettingsAsync must now be free to acquire it.
        owned.ReleaseActions();
        await currentForm.FlushAsync().WaitAsync(Deadline);
        await Turns();
        RequireSuccessfulMetadata(owned, previousSettings, firstLabel, endpoint, originalTarget, currentForm,
            generation, queries, expectedChanges: 1);
        Require(Field<long>(currentForm, "organizationRevision") == revisions[0]
            && Field<long>(currentForm, "repositoryRevision") == revisions[1],
            "Label-only save revised raw organization/repository editor state.");

        // The comparison must use the latest committed original, including after a prior successful save.
        address.Text = endpoint + " ";
        Require(currentForm.HasUncommittedChanges && address.Text != endpoint,
            "Edit/revert did not establish an explicit temporary endpoint edit.");
        address.Text = endpoint;
        var secondLabel = "Owned reverted " + provider;
        label.Text = secondLabel;
        BaseField<DispatcherTimer>(currentForm, "debounce").Stop();
        await currentForm.FlushAsync().WaitAsync(Deadline);
        await Turns();
        RequireSuccessfulMetadata(owned, previousSettings, secondLabel, endpoint, originalTarget, currentForm,
            generation, queries, expectedChanges: 2);

        // Compare rejection to the newly accepted post-save state, not the intentionally reset original observations.
        var accepted = owned.Capture();
        var changes = owned.ChangedCalls;
        address.Text = "https://different.example.test/changed-prefix";
        Require(currentForm.HasUncommittedChanges && address.Text != endpoint && currentForm.TokenDraft == Replacement,
            "Changed-host rejection lacks an actual edited target and retained replacement.");
        BaseField<DispatcherTimer>(currentForm, "debounce").Stop();
        await currentForm.FlushAsync().WaitAsync(Deadline);
        await Turns();
        owned.RequireUnchanged(accepted);
        Require(currentForm.HasUncommittedChanges && BaseField<bool>(currentForm, "saveFailed")
            && BaseField<TextBlock>(currentForm, "Message").Text == Text.L("windows.validationToken")
            && owned.ChangedCalls == changes && owned.CredentialChangedCalls == 0 && owned.PresenceCallbacks == 0
            && owned.ZeroExternalCounters && owned.PresenceQueries == queries
            && owned.Controller.Settings.AccountList.Single(account => account.Id == owned.Account.Id).CredentialTarget == originalTarget,
            "An explicitly different endpoint bypassed unchanged-target metadata admission or accessed credentials.");
        checks.Add(new { name = "completeness.accounts.endpoint." + provider,
            actualRawSlashMetadataCommit = true, exactCurrentOriginalEditRevert = true,
            rawArraysIdTargetPasswordAndSiblingPreserved = true,
            positiveGateReleasedBeforeSuccessfulFlush = true,
            expectedGenericSaveObservationResetAndRetainedOwner = true,
            changedHostStillRejectedWithoutCredentialAccess = true,
            cachedParentAndAvailabilityRetained = true });
    }

    private static void RequireSuccessfulMetadata(Owned owned, DeckSettings originalSettings, string label,
        string endpoint, string target, AccountSettingsForm form, long generation, int queries, int expectedChanges)
    {
        var current = owned.Controller.Settings.AccountList.Single(account => account.Id == owned.Account.Id);
        var persisted = owned.Store.Load();
        var accountFromDisk = persisted.AccountList.Single(account => account.Id == owned.Account.Id);
        var expectedSettings = originalSettings with {
            Accounts = originalSettings.AccountList.Select(account => account.Id == owned.Account.Id ? account with { Label = label } : account).ToArray()
        };
        Require(current.Label == label && accountFromDisk.Label == label
            && string.Equals(current.Endpoint, endpoint, StringComparison.Ordinal)
            && string.Equals(accountFromDisk.Endpoint, endpoint, StringComparison.Ordinal)
            && current.CredentialTarget == target && accountFromDisk.CredentialTarget == target
            && Json(current with { Label = owned.Account.Label }) == Json(owned.Account)
            && Json(accountFromDisk with { Label = owned.Account.Label }) == Json(owned.Account)
            && Json(owned.Controller.Settings) == Json(expectedSettings) && Json(persisted) == Json(expectedSettings),
            "Actual metadata persistence changed the raw endpoint/ID/target/scopes/flags or unrelated saved settings.");
        Require(ReferenceEquals(owned.Form, form) && ReferenceEquals(owned.Window.Page.Content, form)
            && owned.Window.IsVisible && !owned.Window.GeometryOwnerClosed
            && owned.Binding.OwnerCurrent() && owned.Binding.OwnerGeneration() == generation
            && owned.Window.SelectedPage == "account:" + owned.Account.Id
            && form.TokenDraft == Replacement && !form.HasUncommittedChanges
            && BaseField<TextBlock>(form, "Message").Text.Length == 0
            && owned.ChangedCalls == expectedChanges && owned.CredentialChangedCalls == 0
            && owned.PresenceCallbacks == 0 && owned.PresenceQueries == queries && owned.ZeroExternalCounters
            && new FileInfo(owned.Store.Path).Length > 0 && new FileInfo(owned.Store.Path + ".bak").Length > 0,
            "Successful quiet metadata save replaced its parent/form/draft/cache or invoked a credential dependency.");
        owned.RequireSuccessfulReconciliation();
    }

    private static async Task ReplacementGreenAsync(Application application, List<object> checks)
    {
        var byteLengths = new List<int>();
        foreach (var entry in new[] {
            (Provider: "github", ID: new string('a', 121), Bytes: 121),
            (Provider: "gitlab", ID: new string('é', 60) + "a", Bytes: 121),
            (Provider: "github", ID: new string('a', 128), Bytes: 128),
            (Provider: "gitlab", ID: new string('é', 64), Bytes: 128)
        }) {
            var endpoint = entry.Provider == "github" ? "https://api.github.com" : "https://gitlab.example.test/team";
            await using var owned = new Owned(application, entry.Provider, entry.ID, endpoint, replacementBody: true);
            Require(Encoding.UTF8.GetByteCount(owned.Account.Id) == entry.Bytes,
                "Maximum-ID success has the wrong admitted UTF8 account length.");
            owned.Account.Validate();
            await owned.ShowAsync();
            var previousSettings = owned.Controller.Settings;
            var generation = owned.Binding.OwnerGeneration();
            owned.Form.TokenDraft = Replacement;
            await owned.Form.VerifyTokenAsync().WaitAsync(Deadline);
            await Turns();
            var receiver = owned.Receiver;
            Require(receiver.Calls == 1 && receiver.Accepted == 1 && receiver.Rejected == 0
                && receiver.CardID == "verify" && receiver.CardBytes <= 128
                && receiver.ExactCapturedIdentity && receiver.ValidLifetime
                && owned.CredentialWrites == 1 && owned.CredentialDeletes == 0
                && owned.ChangedCalls == 1 && owned.CredentialChangedCalls == 1 && owned.PresenceCallbacks == 0
                && owned.StoredReads == 0 && owned.StoredAcquisitions == 0 && owned.ReplacementsOverridden == 0
                && owned.BrowserCalls == 0 && owned.PromptCalls == 0
                && owned.Form.TokenDraft.Length == 0 && BaseField<TextBlock>(owned.Form, "Message").Text == Text.L("token.works")
                && !owned.Form.HasUncommittedChanges && owned.Binding.OwnerCurrent()
                && owned.Binding.OwnerGeneration() == generation && ReferenceEquals(owned.Window.Page.Content, owned.Form)
                && Json(owned.Controller.Settings) == Json(previousSettings) && Json(owned.Store.Load()) == Json(previousSettings),
                "Actual nonempty replacement failed bounded request identity, verify/write/persist or raw saved-field invariants.");
            owned.RequireSuccessfulReconciliation();
            byteLengths.Add(entry.Bytes);
        }
        Require(byteLengths.SequenceEqual(new[] { 121, 121, 128, 128 }),
            "Maximum-ID qualification did not execute both ASCII and multibyte boundaries.");
        await RawEndpointReplacementAsync(application, "github");
        await RawEndpointReplacementAsync(application, "gitlab");
        await ReplacementEndpointLifetimeAsync(application);
        checks.Add(new { name = "completeness.accounts.replacement.longID",
            actualDefaultFormControllerPath = true, independentSerializedBoundedReceiver = true,
            asciiAndMultibyteAccountBytes = byteLengths, exactEphemeralCardID = true,
            oneVerifyThenWritePersistPerCase = true, rawIdentityAndProviderScopeProjectionPreserved = true,
            rawSlashMetadataThenExplicitNormalized128ByteReplacement = true,
            oldTargetDeletedOnlyAfterPersist = true, immediateStoredFollowUpUsesCommittedNormalizedTarget = true,
            committedEndpointEchoDoesNotAutosave = true, newerEndpointAbaAndClosedFormPreserved = true,
            expectedGenericSaveReconciliation = true, noRealProviderVaultWorker = true });
    }

    private static async Task RawEndpointReplacementAsync(Application application, string provider, List<object>? baseline = null)
    {
        var endpoint = provider == "github" ? "https://api.github.com/" : "https://gitlab.example.test/team/";
        var id = provider == "github" ? new string('a', 128) : new string('é', 64);
        await using var owned = new Owned(application, provider, id, endpoint, replacementBody: true, storedFollowUp: true);
        await owned.ShowAsync();
        Require(Encoding.UTF8.GetByteCount(owned.Account.Id) == 128 && endpoint.EndsWith("/", StringComparison.Ordinal),
            "The raw-endpoint replacement lacks the admitted128-byte account and slash identity.");
        var previous = owned.Controller.Settings;
        var rawTarget = owned.Account.CredentialTarget;
        var form = owned.Form; var generation = owned.Binding.OwnerGeneration(); var queries = owned.PresenceQueries;
        form.TokenDraft = Replacement;
        await owned.HoldActionsAsync();
        var label = "Owned metadata before replacement " + provider;
        Field<TextBox>(form, "label").Text = label;
        BaseField<DispatcherTimer>(form, "debounce").Stop();
        Require(owned.ActionsHeld && form.HasUncommittedChanges && Field<TextBox>(form, "endpoint").Text == endpoint,
            "The counterpart must first enter raw-preserving metadata with a positively held action gate.");
        owned.ReleaseActions();
        await form.FlushAsync().WaitAsync(Deadline); await Turns();
        RequireSuccessfulMetadata(owned, previous, label, endpoint, rawTarget, form, generation, queries, expectedChanges: 1);

        var metadata = owned.Controller.Settings;
        var expected = metadata.AccountList.Single(account => account.Id == id) with { Endpoint = endpoint.TrimEnd('/') };
        var expectedSettings = metadata with { Accounts = metadata.AccountList.Select(account => account.Id == id ? expected : account).ToArray() };
        owned.Receiver.ExpectedAccount = expected;
        owned.CredentialSteps.Clear();
        var editRevision = BaseField<long>(form, "editRevision"); var endpointRevision = Field<long>(form, "endpointRevision");
        await form.VerifyTokenAsync().WaitAsync(Deadline); await Turns();
        Require(owned.Receiver.Calls == 1 && owned.Receiver.Accepted == 1 && owned.Receiver.Rejected == 0
            && owned.Receiver.CardID == "verify" && owned.Receiver.CardBytes <= 128
            && owned.Receiver.ExactCapturedIdentity && owned.Receiver.ValidLifetime
            && Json(owned.Controller.Settings) == Json(expectedSettings) && Json(owned.Store.Load()) == Json(expectedSettings)
            && form.CommittedTokenAccount?.CredentialTarget == expected.CredentialTarget && expected.CredentialTarget != rawTarget
            && owned.CredentialWrites == 1 && owned.CredentialDeletes == 1
            && owned.ChangedCalls == 2 && owned.CredentialChangedCalls == 1 && owned.PresenceCallbacks == 0
            && owned.StoredReads == 0 && owned.StoredAcquisitions == 0 && owned.StoredVerifications == 0
            && owned.ReplacementsOverridden == 0 && owned.BrowserCalls == 0 && owned.PromptCalls == 0
            && owned.CredentialSteps.Select(step => step.Kind).SequenceEqual(new[] { "verify", "write", "persist", "changed", "delete" })
            && owned.CredentialSteps.Take(2).All(step => step.Target == expected.CredentialTarget
                && step.ModelEndpoint == endpoint && step.DiskEndpoint == endpoint)
            && owned.CredentialSteps.Skip(2).All(step => step.ModelEndpoint == expected.Endpoint && step.DiskEndpoint == expected.Endpoint)
            && owned.CredentialSteps.Last().Target == rawTarget
            && form.TokenDraft.Length == 0 && !form.HasUncommittedChanges
            && BaseField<long>(form, "editRevision") == editRevision && Field<long>(form, "endpointRevision") == endpointRevision
            && !BaseField<DispatcherTimer>(form, "debounce").IsEnabled
            && BaseField<TextBlock>(form, "Message").Text == Text.L("token.works")
            && Field<Button>(form, "verifyStored").IsEnabled && form.InitialTokenPresent
            && ReferenceEquals(owned.Window.Page.Content, form) && owned.Binding.OwnerCurrent()
            && owned.Binding.OwnerGeneration() == generation && owned.PresenceQueries == queries + 1,
            "Raw-endpoint explicit replacement did not normalize, verify/write/persist/cache before deleting only its old target.");
        owned.RequireSuccessfulReconciliation();
        var availability = Field<Dictionary<string, bool>>(owned.Window, "tokenAvailability");
        Require(availability.TryGetValue(expected.CredentialTarget, out var present) && present && !availability.ContainsKey(rawTarget),
            "Normalized replacement did not publish the new cached target or retained the removed raw target.");
        if (baseline is not null) baseline.Add(new { name = "completeness.accounts.replacement-followup.premises", premiseOnly = true,
            actual128ByteDefaultProducerAccepted = true, metadataKeptRawEndpoint = true,
            explicitReplacementNormalizedEndpoint = true, newWritePersistThenOldTargetDelete = true,
            currentCachedPresenceAndEnabledStoredButton = true, noStoredReadBeforeFollowUp = true });

        var beforeFollowUp = owned.Controller.Settings;
        var beforeRejectedFollowUp = owned.Capture();
        var writeCount = owned.CredentialWrites; var deleteCount = owned.CredentialDeletes;
        await form.VerifyStoredTokenAsync().WaitAsync(Deadline); await Turns();
        var result = Field<TextBlock>(form, "tokenResult").Text;
        var followUpSucceeded = owned.StoredReads == 1 && owned.StoredAcquisitions == 1 && owned.StoredVerifications == 1
            && owned.StoredIdentityExact && owned.StoredRouteExact && result == Text.L("token.works")
            && Field<TextBox>(form, "endpoint").Text == expected.Endpoint
            && Json(owned.Controller.Settings) == Json(beforeFollowUp) && Json(owned.Store.Load()) == Json(beforeFollowUp)
            && owned.CredentialWrites == writeCount && owned.CredentialDeletes == deleteCount
            && owned.ChangedCalls == 2 && owned.CredentialChangedCalls == 1 && owned.PresenceCallbacks == 1
            && owned.PresenceQueries == queries + 1 && owned.Binding.OwnerCurrent()
            && owned.Binding.OwnerGeneration() == generation && ReferenceEquals(owned.Window.Page.Content, form);
        if (baseline is not null && !followUpSucceeded) {
            owned.RequireUnchanged(beforeRejectedFollowUp);
            Require(Field<TextBox>(form, "endpoint").Text == endpoint
                && owned.StoredReads == 0 && owned.StoredAcquisitions == 0 && owned.StoredVerifications == 0
                && result == Text.Failure(new InvalidOperationException(Text.L("windows.tokenEndpointChanged")))
                && owned.CredentialWrites == writeCount && owned.CredentialDeletes == deleteCount
                && owned.ChangedCalls == 2 && owned.CredentialChangedCalls == 1 && owned.PresenceCallbacks == 0,
                "Raw-slash follow-up did not reach the expected exact-saved-endpoint field rejection.");
        }
        Require(followUpSucceeded,
            "Normalized legacy replacement cannot immediately verify its newly committed stored token.");
        owned.RequireSuccessfulReconciliation();
        var settled = owned.Capture();
        await Task.Delay(TimeSpan.FromMilliseconds(750)); await Turns();
        owned.RequireUnchanged(settled);
        Require(!form.HasUncommittedChanges && !BaseField<DispatcherTimer>(form, "debounce").IsEnabled
            && BaseField<long>(form, "editRevision") == editRevision && Field<long>(form, "endpointRevision") == endpointRevision
            && owned.ChangedCalls == 2 && owned.CredentialChangedCalls == 1 && owned.PresenceCallbacks == 1,
            "Committed endpoint echo scheduled an additional metadata save after ordinary debounce.");
    }

    private static async Task ReplacementEndpointLifetimeAsync(Application application)
    {
        foreach (var scenario in new[] { "newer-endpoint", "endpoint-aba", "closed-after-commit" }) {
            const string raw = "https://api.github.com/";
            await using var owned = new Owned(application, "github", new string('a', 128), raw, replacementBody: true);
            await owned.ShowAsync();
            var form = owned.Form; var input = Field<TextBox>(form, "endpoint");
            var previous = owned.Controller.Settings;
            var expected = owned.Account with { Endpoint = raw.TrimEnd('/') };
            var expectedSettings = previous with { Accounts = previous.AccountList.Select(account => account.Id == expected.Id ? expected : account).ToArray() };
            owned.Receiver.ExpectedAccount = expected;
            form.TokenDraft = Replacement;
            var reply = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var send = owned.Controller.RemoteRequestSender!;
            if (scenario == "closed-after-commit") owned.AfterOldCredentialDelete = form.Dispose;
            else owned.Controller.RemoteRequestSender = async (distribution, operation, request, cancellation) => {
                var response = await send(distribution, operation, request, cancellation);
                await reply.Task; return response;
            };
            Task? action = null;
            try {
                var draftText = raw; var revision = BaseField<long>(form, "editRevision");
                action = form.VerifyTokenAsync();
                if (scenario != "closed-after-commit") {
                    Require(!action.IsCompleted && owned.Receiver.Accepted == 1 && !form.IsEnabled
                        && owned.CredentialWrites == 0 && owned.CredentialDeletes == 0,
                        "Newer endpoint protection lacks a positively held actual replacement response.");
                    draftText = "https://newer.example.test/api";
                    input.Text = draftText;
                    if (scenario == "endpoint-aba") { draftText = raw; input.Text = draftText; }
                    BaseField<DispatcherTimer>(form, "debounce").Stop();
                    revision = BaseField<long>(form, "editRevision");
                    Require(form.HasUncommittedChanges && Field<long>(form, "endpointRevision") > 0,
                        "Newer endpoint protection did not create a real edited/ABA draft.");
                }
                reply.TrySetResult();
                await action.WaitAsync(Deadline); await Turns();
                Require(input.Text == draftText && BaseField<long>(form, "editRevision") == revision
                    && !BaseField<DispatcherTimer>(form, "debounce").IsEnabled
                    && owned.Receiver.Calls == 1 && owned.Receiver.Accepted == 1 && owned.Receiver.CardID == "verify"
                    && owned.Receiver.ExactCapturedIdentity && owned.CredentialWrites == 1 && owned.CredentialDeletes == 1
                    && owned.CredentialSteps.Select(step => step.Kind).SequenceEqual(new[] { "verify", "write", "persist", "changed", "delete" })
                    && Json(owned.Controller.Settings) == Json(expectedSettings) && Json(owned.Store.Load()) == Json(expectedSettings)
                    && (scenario == "closed-after-commit" ? form.FormDisposed && !owned.Binding.OwnerCurrent()
                        : form.HasUncommittedChanges && owned.Binding.OwnerCurrent())
                    && owned.StoredReads == 0 && owned.StoredAcquisitions == 0 && owned.StoredVerifications == 0,
                    "Success-only committed endpoint echo overwrote a newer/ABA draft or touched a closed form.");
                owned.RequireSuccessfulReconciliation();
            } finally {
                reply.TrySetResult();
                if (action is not null) await action.WaitAsync(Deadline);
            }
        }
    }

    private static async Task EndpointAsync(Application application, List<object> checks, string provider)
    {
        var endpoint = provider == "github" ? "https://api.github.com/" : "https://gitlab.example.test/team/";
        await using var owned = new Owned(application, provider, "owned.legacy." + provider, endpoint, replacementBody: false);
        await owned.ShowAsync();
        await owned.HoldActionsAsync();
        owned.Form.TokenDraft = Replacement;
        var label = Field<TextBox>(owned.Form, "label");
        var enteredEndpoint = Field<TextBox>(owned.Form, "endpoint");
        var before = owned.Capture();
        var revisions = new[] { Field<long>(owned.Form, "organizationRevision"), Field<long>(owned.Form, "repositoryRevision") };
        var originalTarget = owned.Account.CredentialTarget;
        var parentGeneration = owned.Binding.OwnerGeneration();
        var chosenLabel = "Owned renamed " + provider;
        label.Text = chosenLabel;
        Require(owned.Form.HasUncommittedChanges && BaseField<DispatcherTimer>(owned.Form, "debounce").IsEnabled,
            "The label edit did not enter the actual live quiet-autosave path.");
        Require(enteredEndpoint.Text == owned.Account.Endpoint && owned.Form.TokenDraft == Replacement
            && Field<ComboBox>(owned.Form, "provider").SelectedItem as string == provider
            && !Field<ComboBox>(owned.Form, "provider").IsEnabled
            && Field<BrowserPicker>(owned.Form, "browser").BrowserID == "chrome"
            && Field<BrowserPicker>(owned.Form, "browser").SelectedProfile == "Profile 2"
            && Field<long>(owned.Form, "organizationRevision") == revisions[0]
            && Field<long>(owned.Form, "repositoryRevision") == revisions[1]
            && owned.Binding.OwnerCurrent() && owned.Binding.OwnerGeneration() == parentGeneration,
            "Label-only metadata premise changed endpoint/provider/scopes/browser/password or its current owner.");
        BaseField<DispatcherTimer>(owned.Form, "debounce").Stop();
        checks.Add(new { name = "completeness.accounts.endpoint-" + provider + ".premises", premiseOnly = true,
            actualVisibleSettingsParentAndForm = true, rawSavedEndpointAndTarget = true,
            labelOnlyLiveAutosave = true, globalActionsHeld = true, nonemptyStoreBackupAndGlobals = true,
            hiddenCachedHwndAndUncancelledRead = true, fakeDependenciesOnly = true });

        // On the old body this finishes before Controller.actions: target admission rejects the slash-normalized draft.
        // This held-gate OLD-red timing premise must be changed before promotion to a successful-save suite.
        await owned.Form.FlushAsync().WaitAsync(Deadline);
        await Turns();
        var saved = owned.Controller.Settings.AccountList.Single(account => account.Id == owned.Account.Id);
        var oldRejected = BaseField<bool>(owned.Form, "saveFailed")
            && owned.Form.HasUncommittedChanges
            && BaseField<TextBlock>(owned.Form, "Message").Text == Text.L("windows.validationToken");
        Require(oldRejected, "The old raw-endpoint body did not reach the expected quiet credential-target rejection.");
        owned.RequireUnchanged(before);
        Require(saved.Label == owned.Account.Label && saved.Endpoint == endpoint
            && string.Equals(saved.CredentialTarget, originalTarget, StringComparison.Ordinal)
            && label.Text == chosenLabel && enteredEndpoint.Text == endpoint
            && owned.Form.TokenDraft == Replacement && owned.Form.InitialTokenPresent
            && owned.Binding.OwnerCurrent() && owned.Binding.OwnerGeneration() == parentGeneration
            && owned.ActionsHeld && owned.ZeroExternalCounters && owned.CallbackCalls == 0,
            "Rejected label-only save changed committed raw identity, password, callbacks, globals or the owned action gate.");
        checks.Add(new { name = "account.legacy.endpoint." + provider + ".actualBody",
            actualQuietFlushCompletedBeforeHeldControllerGate = true, rejectedByTokenIdentityGuard = oldRejected,
            ordinalSavedTargetRetained = true, storeAndBackupExact = true,
            unrelatedGlobalsAndFormRetained = true, zeroCredentialProviderBrowserOrWorkerAccess = true });
        Require(!oldRejected && saved.Label == chosenLabel && saved.Endpoint == endpoint
            && saved.CredentialTarget == originalTarget && !owned.Form.HasUncommittedChanges,
            "Legacy raw-endpoint " + (provider == "github" ? "GitHub" : "GitLab")
            + " label-only metadata save did not commit.");
    }

    private static async Task ReplacementAsync(Application application, List<object> checks)
    {
        // The receiver is independently reachable at the old prefix's final legal boundary.
        var outcomes = new List<bool>();
        foreach (var entry in new[] {
            (Provider: "github", ID: new string('a', 121), Bytes: 121, Label: "ascii121", Control: true),
            (Provider: "gitlab", ID: new string('é', 60) + "a", Bytes: 121, Label: "utf8_121", Control: true),
            (Provider: "github", ID: new string('a', 128), Bytes: 128, Label: "ascii128", Control: false),
            (Provider: "gitlab", ID: new string('é', 64), Bytes: 128, Label: "utf8_128", Control: false)
        }) {
            var endpoint = entry.Provider == "github" ? "https://api.github.com" : "https://gitlab.example.test/team";
            await using var owned = new Owned(application, entry.Provider, entry.ID, endpoint, replacementBody: true);
            Require(Encoding.UTF8.GetByteCount(owned.Account.Id) == entry.Bytes,
                "The replacement account ID lacks the intended exact UTF8 boundary.");
            owned.Account.Validate();
            await owned.ShowAsync();
            owned.Form.TokenDraft = Replacement;
            var before = owned.Capture();
            checks.Add(new { name = "account.legacy.replacement." + entry.Label + ".premise",
                admittedAccountBytes = entry.Bytes, actualVisibleCurrentParentForm = true,
                nonemptyReplacement = true, pendingUnrelatedReadAndGlobals = true, positiveOwnedStoreAndBackup = true });
            // No verifyCredential override: actual form SaveTokenAsync -> actual DeckController.VerifyTokenAsync.
            await owned.Form.VerifyTokenAsync().WaitAsync(Deadline);
            await Turns();
            var receiver = owned.Receiver;
            Require(receiver.Calls == 1 && receiver.ExactCapturedIdentity && receiver.ValidLifetime
                && owned.StoredReads == 0 && owned.StoredAcquisitions == 0
                && owned.BrowserCalls == 0 && owned.PromptCalls == 0
                && owned.Controller.Settings.AccountList.Single(account => account.Id == entry.ID).CredentialTarget == owned.Account.CredentialTarget,
                "Actual replacement did not reach exactly one independently admitted receiver with captured identity and lifetime.");
            if (entry.Control) {
                Require(receiver.Accepted == 1 && receiver.Rejected == 0 && receiver.CardBytes <= 128
                    && owned.CredentialWrites == 1 && owned.CredentialDeletes == 0
                    && owned.ChangedCalls == 1 && owned.CredentialChangedCalls == 1
                    && owned.PresenceCallbacks == 0 && owned.Form.TokenDraft.Length == 0
                    && BaseField<TextBlock>(owned.Form, "Message").Text == Text.L("token.works")
                    && Json(owned.Controller.Settings.AccountList.Single(account => account.Id == entry.ID)) == Json(owned.Account),
                    "The legal121-byte positive replacement control did not complete the actual verify/write/persist path.");
                // Successful SaveSettingsAsync intentionally reconciles and resets observations. Do not assert old globals here.
                owned.RequireIsolation();
                checks.Add(new { name = "account.legacy.replacement." + entry.Label + ".receiverControl",
                    validBoundaryReached = true, requestCardBytes = receiver.CardBytes,
                    actualVerifyWritePersist = true, exactCommittedIdentity = true,
                    successfulSaveReconciliationNotMisclassified = true });
            } else {
                var admitted = receiver.Accepted == 1 && receiver.Rejected == 0 && receiver.CardBytes <= 128;
                if (!admitted) {
                    Require(receiver.Rejected == 1 && receiver.Accepted == 0 && receiver.CardBytes > 128
                        && owned.CredentialWrites == 0 && owned.CredentialDeletes == 0
                        && owned.CallbackCalls == 0 && owned.Form.TokenDraft == Replacement
                        && BaseField<TextBlock>(owned.Form, "Message").Text == Text.Failure(BoundedReplacementReceiver.Rejection()),
                        "The long-ID producer failure did not produce the exact independent receiver rejection before any write/commit.");
                    owned.RequireUnchanged(before);
                } else {
                    Require(owned.CredentialWrites == 1 && owned.CredentialDeletes == 0 && owned.ChangedCalls == 1
                        && owned.CredentialChangedCalls == 1 && owned.Form.TokenDraft.Length == 0,
                        "An admitted maximum-ID replacement failed its actual persistence path.");
                    owned.RequireIsolation();
                }
                outcomes.Add(admitted);
                checks.Add(new { name = "account.legacy.replacement." + entry.Label + ".actualBody",
                    accountBytes = entry.Bytes, outgoingCardBytes = receiver.CardBytes,
                    independentlyAdmitted = admitted, actualReceiverRejections = receiver.Rejected,
                    exactCapturedIdentity = true, noStoredTokenRead = true,
                    rejectedStateAndBackupPreserved = !admitted });
            }
        }
        Require(outcomes.Count == 2, "The long replacement baseline did not execute both independently owned maximum-ID cases.");
        checks.Add(new { name = "completeness.accounts.replacement-long-id.premises", premiseOnly = true,
            positive121ByteControls = 2, actualMaximumAccountCases = 2, asciiAndMultibyte128 = true,
            independentlyReachableReceiver = true, actualDefaultFormControllerProducer = true,
            rejectedGlobalsAndBackupCheckedBeforeFixedBehaviorAssertion = true,
            noRealWorkersVaultProviderBrowserOrOsMutation = true });
        Require(outcomes.All(value => value),
            "Legacy nonempty replacement cannot verify all admitted128-byte account IDs.");
    }

    private sealed class BoundedReplacementReceiver(RemoteAccountSettings initialAccount)
    {
        internal RemoteAccountSettings ExpectedAccount = initialAccount;
        internal Action? AcceptedCallback;
        internal int Calls, Accepted, Rejected, CardBytes;
        internal string? CardID;
        internal bool ExactCapturedIdentity, ValidLifetime;
        internal static WorkerException Rejection() => new("invalidRemote", "Owned replacement request exceeds128 UTF8 card bytes.");
        internal Task<WorkerResponse> ReceiveAsync(string distribution, string operation, RemoteRequest outgoing, CancellationToken cancellation)
        {
            Calls++;
            // Serialize/deserialize at the fake worker boundary. Do not use producer prefix or planned helper in receiver admission.
            var received = JsonSerializer.Deserialize<RemoteRequest>(Json(outgoing), WorkerProtocol.Json)
                ?? throw new IOException("The independent owned replacement receiver did not receive a DTO.");
            ValidLifetime = cancellation.CanBeCanceled && !cancellation.IsCancellationRequested;
            var account = ExpectedAccount;
            var credential = received.Accounts.Single();
            ExactCapturedIdentity = distribution == Distribution && operation == "remote.verify"
                && received.Kind == (account.Provider == "gitlab" ? "mergeRequests" : "pullRequests")
                && credential.Id == account.Id && credential.Label == account.Label
                && string.Equals(credential.Endpoint, account.Endpoint, StringComparison.Ordinal)
                && credential.Token == Replacement
                && (account.Provider != "gitlab" || credential.Organizations.Length == 0 && credential.Repositories.Length == 0)
                && (account.Provider != "github" || credential.Organizations.SequenceEqual(account.Organizations)
                    && credential.Repositories.SequenceEqual(account.Repositories));
            Require(ExactCapturedIdentity && ValidLifetime,
                "The owned receiver got a foreign provider/account/endpoint/credential/route or invalid cancellation lifetime.");
            CardBytes = Encoding.UTF8.GetByteCount(received.CardID);
            CardID = received.CardID;
            if (received.CardID.Length == 0 || CardBytes > 128 || received.CardID.Any(char.IsControl)) {
                Rejected++; throw Rejection();
            }
            Accepted++;
            AcceptedCallback?.Invoke();
            return Task.FromResult(new WorkerResponse(1, "owned-legacy-verify", Distribution, null, null, null, null));
        }
    }

    private sealed class Owned : IAsyncDisposable
    {
        internal readonly SettingsStore Store;
        internal readonly DeckController Controller;
        internal readonly RemoteAccountSettings Account;
        internal readonly WorkerSettings Route = new(Distribution, "/owned/legacy-runtime", "en");
        internal readonly SettingsWindow Window;
        internal readonly ProjectCard LocalOwner;
        internal readonly BoundedReplacementReceiver Receiver;
        internal AccountSettingsForm Form { get; private set; } = null!;
        internal SettingsWindow.AccountFormBinding Binding { get; private set; } = null!;
        internal int PresenceQueries, StoredReads, StoredAcquisitions, ReplacementsOverridden, CredentialWrites, CredentialDeletes;
        internal int StoredVerifications;
        internal bool StoredIdentityExact, StoredRouteExact;
        internal Action? AfterOldCredentialDelete;
        internal readonly List<(string Kind, string Target, string ModelEndpoint, string DiskEndpoint)> CredentialSteps = [];
        internal int ChangedCalls, CredentialChangedCalls, PresenceCallbacks, BrowserCalls, PromptCalls, DiscoveryCalls;
        private readonly bool replacementBody;
        private readonly bool storedFollowUp;
        private readonly TaskCompletionSource<WorkerResponse> read = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private Task? pendingRead;
        private CancellationToken pendingReadToken;
        private bool gateHeld;
        internal bool ActionsHeld => gateHeld && Field<SemaphoreSlim>(Controller, "actions").CurrentCount == 0;
        internal int CallbackCalls => ChangedCalls + CredentialChangedCalls + PresenceCallbacks;
        internal bool ZeroExternalCounters => StoredReads == 0 && StoredAcquisitions == 0 && ReplacementsOverridden == 0
            && CredentialWrites == 0 && CredentialDeletes == 0 && BrowserCalls == 0 && PromptCalls == 0 && Receiver.Calls == 0;

        internal Owned(Application application, string provider, string id, string endpoint, bool replacementBody, bool storedFollowUp = false)
        {
            this.replacementBody = replacementBody;
            this.storedFollowUp = storedFollowUp;
            Store = new(Path.Combine(Path.GetTempPath(), "devdeck-account-legacy-" + Guid.NewGuid().ToString("N") + ".json"));
            var selected = new RemoteAccountSettings(id, "Owned legacy account", provider, endpoint,
                provider == "github" ? ["retained", "retained"] : Enumerable.Repeat("inactive raw", 65).Concat([null!, "has space", "has,comma"]).ToArray(),
                provider == "github" ? ["owned/repo", "owned/repo"] : ["legacy/inactive", null!, "has space", "has,comma"],
                Browser: "chrome", BrowserProfile: "Profile 2", NotifiesBlocked: true, NotifiesFailedRuns: true);
            var sibling = new RemoteAccountSettings("owned.legacy.sibling", "Owned sibling", "gitlab",
                "https://sibling.example.test/team", ["inactive"], [null!, "unused/repo"], Enabled: false, NotifiesFailedRuns: true);
            var local = new CardSettings(new(LocalID, Distribution, "local", "/owned/legacy-checkout",
                Title: "Owned retained card"), "Owned retained card", Enabled: false, X: 91, Y: 143, Collapsed: true);
            var remotes = RemoteCardCatalog.All.Select(descriptor => new RemoteCardSettings(descriptor.Id, descriptor.Kind,
                descriptor.Kind, Distribution, descriptor.Provider == provider ? [id] : descriptor.Provider == "gitlab" ? [sibling.Id] : [],
                Enabled: false, X: 210, Y: 177, Collapsed: true)).ToArray();
            var seed = new DeckSettings(1, [Route], [local], Accounts: [selected, sibling], RemoteCards: remotes,
                Language: "en", Notifications: true, SeenAlerts: ["owned.legacy.seen"], RefreshSeconds: 120);
            seed.Validate(); Store.Save(seed); Store.Save(seed);
            Controller = new(application, Store, live: false,
                settingsCheckWorkerFactory: _ => throw new IOException("Legacy fixture must not acquire a real settings worker."));
            Account = Controller.Settings.AccountList.Single(account => account.Id == id);
            Receiver = new(Account);
            Receiver.AcceptedCallback = () => RecordCredentialStep("verify", Receiver.ExpectedAccount);
            Controller.RemoteTokenReader = _ => { StoredReads++; throw new IOException("Legacy fixture must not read a remote token."); };
            Controller.RemoteRequestSender = Receiver.ReceiveAsync;
            LocalOwner = new(Controller, Controller.Settings.Cards.Single(), live: false, statusReader: (_, cancellation) => {
                pendingReadToken = cancellation; return read.Task;
            });
            Field<List<ProjectCard>>(Controller, "cards").Add(LocalOwner);
            Field<Dictionary<string, CardSettings>>(Controller, "localConfigurations")[LocalID] = Controller.Settings.Cards.Single();
            LocalOwner.ApplySnapshot(Status());
            new WindowInteropHelper(LocalOwner).EnsureHandle();
            SeedGlobals();
            Window = new(Controller, live: true, tokenAvailable: _ => { PresenceQueries++; return true; },
                accountFormFactory: CreateForm, runningBuildInfoProvider: () => RunningBuildInfo.Unknown);
            SetField(Controller, "settingsWindow", Window);
        }

        private AccountSettingsForm CreateForm(SettingsWindow.AccountFormBinding binding)
        {
            Binding = binding;
            Form = new(binding.Controller, binding.Account, binding.Live, id => {
                ChangedCalls++; RecordCredentialStep("changed", Form.CommittedTokenAccount!); binding.Changed(id);
            },
                binding.NewProvider, binding.Confirmation,
                credentialChanged: id => {
                    CredentialChangedCalls++; RecordCredentialStep("persist", Form.CommittedTokenAccount!); binding.CredentialChanged(id);
                },
                verifyCredential: replacementBody ? null : (_, _, _, _) => {
                    ReplacementsOverridden++; throw new IOException("Metadata fixture invoked replacement verification.");
                },
                credentialWriter: (account, value) => {
                    if (value is null) CredentialDeletes++; else CredentialWrites++;
                    RecordCredentialStep(value is null ? "delete" : "write", account);
                    if (value is null) AfterOldCredentialDelete?.Invoke();
                },
                discoverDistributions: _ => { DiscoveryCalls++; return Task.FromResult(new[] { Distribution }); },
                browserOpener: (_, _, _) => { BrowserCalls++; throw new IOException("Legacy fixture opened a browser."); },
                browserPickerFactory: (browser, profile) => new(browser, profile,
                    [new("chrome", "Owned Chrome", @"C:\Fixture\chrome.exe", true)],
                    _ => [new("Default", "Default"), new("Profile 2", "Owned profile")]),
                tokenPresent: binding.TokenPresent, ownerCurrent: binding.OwnerCurrent,
                storedCredentialReader: account => {
                    StoredReads++; if (!storedFollowUp) throw new IOException("Legacy fixture read a stored token.");
                    StoredIdentityExact = Json(account) == Json(Receiver.ExpectedAccount);
                    return Replacement;
                },
                acquireStoredVerifier: (route, _) => {
                    StoredAcquisitions++; if (!storedFollowUp) throw new IOException("Legacy fixture acquired a stored verifier.");
                    StoredRouteExact = route == Route;
                    return Task.FromResult(new StoredTokenVerifier(route, (account, value, cancellation) => {
                        StoredVerifications++; StoredIdentityExact &= Json(account) == Json(Receiver.ExpectedAccount)
                            && value == Replacement && cancellation.CanBeCanceled && !cancellation.IsCancellationRequested;
                        return Task.CompletedTask;
                    }));
                },
                storedPresenceChanged: (account, present) => { PresenceCallbacks++; binding.PresenceChanged(account, present); },
                enterpriseAddressPrompt: (_, _) => { PromptCalls++; throw new IOException("Legacy fixture opened an Enterprise prompt."); },
                ownerGeneration: binding.OwnerGeneration);
            return Form;
        }

        private void RecordCredentialStep(string kind, RemoteAccountSettings account) => CredentialSteps.Add((kind,
            account.CredentialTarget, Controller.Settings.AccountList.Single(value => value.Id == Account.Id).Endpoint,
            Store.Load().AccountList.Single(value => value.Id == Account.Id).Endpoint));

        internal async Task ShowAsync()
        {
            Window.Show(); Window.UpdateLayout(); await Turns();
            await Window.SelectPageAsync("account:" + Account.Id).WaitAsync(Deadline);
            Window.UpdateLayout(); await Turns();
            var label = Field<TextBox>(Form, "label");
            Require(Window.IsVisible && new WindowInteropHelper(Window).Handle != 0
                && Form.IsLoaded && Form.IsVisible && Form.IsEnabled && Form.ActualWidth > 0
                && label.IsVisible && label.ActualWidth > 0 && PresentationSource.FromVisual(Form) is not null
                && ReferenceEquals(Window.Page.Content, Form) && Binding.OwnerCurrent()
                && Binding.OwnerGeneration() > 0 && Window.SelectedPage == "account:" + Account.Id
                && Form.InitialTokenPresent && Form.CommittedTokenAccount?.CredentialTarget == Account.CredentialTarget
                && Field<TextBox>(Form, "endpoint").Text == Account.Endpoint
                && Field<ComboBox>(Form, "distribution").SelectedItem as string == Distribution
                && Field<BrowserPicker>(Form, "browser").BrowserID == "chrome"
                && Field<BrowserPicker>(Form, "browser").SelectedProfile == "Profile 2"
                && PresenceQueries == 2 && DiscoveryCalls == 1 && CallbackCalls == 0 && ZeroExternalCounters,
                "The actual owned saved account parent/form/identity/route/presence did not render before the legacy action.");
            pendingRead = LocalOwner.RefreshAsync();
            LocalOwner.SetDeckVisible(false); await Turns();
            Require(pendingRead is { IsCompleted: false } && pendingReadToken.CanBeCanceled
                && !pendingReadToken.IsCancellationRequested && LocalOwner.Latest?.State == "running"
                && !LocalOwner.IsVisible && new WindowInteropHelper(LocalOwner).Handle != 0,
                "The unrelated hidden cached HWND and pending uncancelled fake read must be positive prerequisites.");
            Require(Controller.Settings.AnnouncedAlerts.Length > 0 && Controller.LastCheckedAt is not null
                && Field<AttentionTracker>(Controller, "attention").SignalItems.Length > 0
                && Field<IList>(Controller, "pendingAlerts").Count > 0
                && ((IEnumerable)Field<object>(Controller, "deliveries")).Cast<object>().Any()
                && Field<object?>(Controller, "activeDelivery") is not null
                && Field<DeckAlert?>(Controller, "activeAlert") is not null
                && File.Exists(Store.Path) && new FileInfo(Store.Path).Length > 0
                && File.Exists(Store.Path + ".bak") && new FileInfo(Store.Path + ".bak").Length > 0,
                "Legacy preservation needs nonempty files/backup/Seen/clock/attention/pending/queued/active state.");
            RequireIsolation();
        }

        internal async Task HoldActionsAsync()
        {
            Require(await Field<SemaphoreSlim>(Controller, "actions").WaitAsync(Deadline),
                "The isolated metadata baseline could not acquire its own controller action gate.");
            gateHeld = true;
            Require(ActionsHeld, "The isolated metadata baseline did not positively hold the controller action gate.");
        }

        internal void ReleaseActions()
        {
            Require(ActionsHeld, "Successful metadata save did not own the positively held action gate.");
            gateHeld = false;
            Field<SemaphoreSlim>(Controller, "actions").Release();
            Require(Field<SemaphoreSlim>(Controller, "actions").CurrentCount == 1,
                "The owned action gate was not released before successful metadata admission.");
        }

        internal void RequireSuccessfulReconciliation()
        {
            Require(Controller.LastCheckedAt is null
                && Field<AttentionTracker>(Controller, "attention").SignalItems.Length == 0
                && Field<IList>(Controller, "pendingAlerts").Count == 0
                && !((IEnumerable)Field<object>(Controller, "deliveries")).Cast<object>().Any()
                && Field<object?>(Controller, "activeDelivery") is null
                && Field<DeckAlert?>(Controller, "activeAlert") is null
                && Controller.Settings.AnnouncedAlerts.SequenceEqual(new[] { "owned.legacy.seen" })
                && Field<NotificationLedger>(Controller, "notifications").Seen.SequenceEqual(new[] { "owned.legacy.seen" })
                && Controller.AllLocalViews.Single(card => card.Reference.Id == LocalID) == LocalOwner
                && !LocalOwner.SidebarOwnerClosed && !LocalOwner.IsVisible
                && new WindowInteropHelper(LocalOwner).Handle != 0 && LocalOwner.Latest?.State == "running"
                && pendingRead is { IsCompleted: false } && pendingReadToken.CanBeCanceled
                && !pendingReadToken.IsCancellationRequested,
                "Successful generic save did not perform its expected observer reset or retained unrelated-owner reconciliation.");
            RequireIsolation();
        }

        private void SeedGlobals()
        {
            Field<AttentionTracker>(Controller, "attention").Observe(new AttentionSnapshot("local:" + Distribution,
                [new("owned.legacy.attention", "owned.legacy.key", "waiting", "github", "Owned waiting work",
                    "Owned facts", 1000, new("none"), false, false)], []));
            var alert = new DeckAlert("owned.legacy.pending", "cantCheck", LocalID, "Owned pending", "Owned detail",
                "Owned body", "", new("menu"), true);
            var scopedType = typeof(DeckController).GetNestedType("ScopedAlert", BindingFlags.NonPublic)!;
            var scoped = Activator.CreateInstance(scopedType, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
                null, ["local:" + Distribution, alert], null)!;
            Field<IList>(Controller, "pendingAlerts").Add(scoped);
            var sources = Array.CreateInstance(scopedType, 1); sources.SetValue(scoped, 0);
            var deliveryType = typeof(DeckController).GetNestedType("Delivery", BindingFlags.NonPublic)!;
            var delivery = Activator.CreateInstance(deliveryType, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
                null, [sources, false], null)!;
            var queue = Field<object>(Controller, "deliveries"); queue.GetType().GetMethod("Enqueue")!.Invoke(queue, [delivery]);
            SetField(Controller, "activeDelivery", delivery); SetField(Controller, "activeAlert", alert);
            SetField(Controller, "lastCheckedAt", DateTimeOffset.FromUnixTimeSeconds(1000));
        }

        // In-memory snapshot only. No password/token/configuration content is emitted to the check report.
        internal string Capture() => Json(new {
            settings = Controller.Settings, file = Convert.ToHexString(File.ReadAllBytes(Store.Path)),
            backup = Convert.ToHexString(File.ReadAllBytes(Store.Path + ".bak")),
            clock = Controller.LastCheckedAt, signals = Field<AttentionTracker>(Controller, "attention").SignalItems,
            seen = Field<NotificationLedger>(Controller, "notifications").Seen,
            pending = Field<IList>(Controller, "pendingAlerts").Cast<object>().ToArray(),
            queue = ((IEnumerable)Field<object>(Controller, "deliveries")).Cast<object>().ToArray(),
            activeDelivery = Field<object?>(Controller, "activeDelivery"), activeAlert = Field<DeckAlert?>(Controller, "activeAlert"),
            timers = new[] { "localPolling", "sharedPolling", "notificationBatch", "notificationExpiry", "nextNotification" }
                .Select(name => Field<DispatcherTimer>(Controller, name).IsEnabled).ToArray(),
            localHwnd = new WindowInteropHelper(LocalOwner).Handle.ToInt64(), status = LocalOwner.Latest,
            hidden = !LocalOwner.IsVisible, configured = LocalOwner.Reference, password = Form.TokenDraft,
            parentHwnd = new WindowInteropHelper(Window).Handle.ToInt64(), selected = Window.SelectedPage,
            generation = Binding.OwnerGeneration(), current = Binding.OwnerCurrent(),
            presence = Field<Dictionary<string, bool>>(Window, "tokenAvailability").OrderBy(pair => pair.Key).ToArray(),
            presenceQueries = PresenceQueries, gateHeld
        });

        internal void RequireUnchanged(string before)
        {
            Require(Capture() == before && pendingRead is { IsCompleted: false } && !pendingReadToken.IsCancellationRequested,
                "Rejected legacy body changed owned model/backup/password/queue/clock/cache/current parent or pending owner.");
            RequireIsolation();
        }

        internal void RequireIsolation()
        {
            var managers = typeof(DeckController).GetFields(BindingFlags.Instance | BindingFlags.NonPublic)
                .Where(field => field.FieldType == typeof(WorkerManager)).Select(field => (WorkerManager)field.GetValue(Controller)!);
            Require(managers.All(manager => ((IDictionary)typeof(WorkerManager).GetField("workers", BindingFlags.Instance | BindingFlags.NonPublic)!
                    .GetValue(manager)!).Count == 0)
                && !Controller.LocalPollEnabled && !Controller.SharedPollEnabled
                && Field<object?>(Controller, "tray") is null
                && new[] { "localPolling", "sharedPolling", "notificationBatch", "notificationExpiry", "nextNotification" }
                    .All(name => !Field<DispatcherTimer>(Controller, name).IsEnabled),
                "The owned legacy fixture started a real worker, polling or shell notification.");
        }

        public async ValueTask DisposeAsync()
        {
            try {
                if (gateHeld) { gateHeld = false; Field<SemaphoreSlim>(Controller, "actions").Release(); }
                Form?.Dispose(); SetField(Window, "form", null); Window.Page.Content = null;
                if (!Window.GeometryOwnerClosed) await Window.CloseSettingsAsync().WaitAsync(Deadline);
            }
            finally {
                read.TrySetResult(new(1, "owned-legacy-status", Distribution, null, Status(), null, null));
                try { if (pendingRead is not null) await pendingRead.WaitAsync(Deadline); }
                finally {
                    try {
                        Controller.CloseViews();
                        foreach (var field in typeof(DeckController).GetFields(BindingFlags.Instance | BindingFlags.NonPublic)
                            .Where(field => field.FieldType == typeof(WorkerManager)))
                            await ((WorkerManager)field.GetValue(Controller)!).DisposeAsync().AsTask().WaitAsync(Deadline);
                    } finally {
                        foreach (var file in new[] { Store.Path, Store.Path + ".bak" })
                            if (File.Exists(file)) File.Delete(file);
                    }
                }
            }
        }
    }

    private static ProjectStatus Status() => new(LocalID, "running", "owned.branch", null, "Owned framework", null);
    private static string Json<T>(T value) => JsonSerializer.Serialize(value, WorkerProtocol.Json);
    private static async Task Turns() { for (var turn = 0; turn < 3; turn++) await Dispatcher.Yield(DispatcherPriority.Background); }
    private static void Require(bool condition, string message) { if (!condition) throw new IOException(message); }
    private static T Field<T>(object owner, string name) =>
        (T)owner.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(owner)!;
    private static void SetField(object owner, string name, object? value) =>
        owner.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(owner, value);
    private static T BaseField<T>(object owner, string name)
    {
        for (var type = owner.GetType(); type is not null; type = type.BaseType)
            if (type.GetField(name, BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly) is { } field)
                return (T)field.GetValue(owner)!;
        throw new IOException("Owned legacy field missing: " + name);
    }
}
