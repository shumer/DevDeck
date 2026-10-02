using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

// SET08 actual General baseline; only owned child metadata and isolated state.
// Run before provenance product wiring; retain these cases for its later acceptance.
// API: RunRedAsync(application, checks, "build" | "location"). Exactly two independent cases.
// Existing General and real child-local App metadata are the baseline; no future helper/seam.
// Expected IOException identifies only the missing fact, never a machine/user path or settings.
// The isolated CLI reports failures without opening a product MessageBox.
internal static class SettingsProvenanceTests
{
    private const string Distribution = "Owned Linux";
    private const string ProjectID = "owned.provenance.local";

    internal static async Task RunAsync(Application application, List<object> checks)
    {
        var language = Text.Language;
        try {
            await RunRedAsync(application, checks, "build");
            await RunRedAsync(application, checks, "location");
            foreach (var locale in new[] { "en", "ru", "de", "es", "fr", "it" }) {
                Text.Use(locale); await LocaleAsync(application, checks, locale);
            }
            Text.Use(language);
            VersionBounds(checks); PathBounds(checks); Startup(checks);
            await FallbacksAsync(application, checks);
            await ModuleIdentityAsync(application, checks);
            await LifetimeAsync(application, checks);
            await UpdaterAsync(application, checks);
            await MetadataPreservationAsync(application, checks);
        } finally { Text.Use(language); }
    }

    private static void VersionBounds(List<object> checks)
    {
        const string assembly = "1.2.3.4";
        var id = Guid.Parse("90225e84-d163-4460-a6b1-5a5e7c2185c8");
        var limit = new string('v', RunningBuildInfo.MaximumVersionLength);
        var good = new RunningBuildInfo(limit, assembly, id, @"C:\Fixture\app.exe", @"C:\Fixture\app.dll");
        Require(good.InformationalVersion == limit && good.VersionForUpdates == limit,
            "SET08 accepted version limit/raw updater value changed.");
        foreach (var invalid in new string?[] { null, "", "  ", limit + "v", "1.2\n3", "1.2\u007f3", "bad\ud800", "bad\udc00" }) {
            var fact = new RunningBuildInfo(invalid, assembly, id, @"C:\Fixture\app.exe", @"C:\Fixture\app.dll");
            Require(fact.InformationalVersion is null && fact.VersionForUpdates is null
                && fact.AssemblyVersion == assembly && fact.ModuleVersionID == id && fact.ExecutablePath == good.ExecutablePath
                && fact.ModulePath == good.ModulePath, "SET08 version failure invalidates independent facts or invents updater input.");
        }
        var reads = new int[5];
        var failed = RunningBuildInfo.Capture(
            () => { reads[0]++; throw new CustomAttributeFormatException("Owned unreadable version."); },
            () => { reads[1]++; return assembly; },
            () => { reads[2]++; return id; },
            () => { reads[3]++; throw new UnauthorizedAccessException("Owned inaccessible process path."); },
            () => { reads[4]++; return @"C:\Fixture\app.dll"; });
        Require(reads.All(count => count == 1) && failed.InformationalVersion is null && failed.ExecutablePath is null
            && failed.AssemblyVersion == assembly && failed.ModuleVersionID == id && failed.ModulePath == good.ModulePath,
            "SET08 independent unavailable metadata readers abort capture, retry or lose valid facts.");
        var unswallowed = false;
        try { _ = RunningBuildInfo.Capture(() => throw new ApplicationException("Owned unexpected reader failure."),
            () => assembly, () => id, () => "x", () => "y"); }
        catch (ApplicationException) { unswallowed = true; }
        Require(unswallowed, "SET08 capture swallowed an unexpected metadata failure.");
        checks.Add(new { name="settings.provenance.versionBounds", wholeFieldBounds=true, independentReaderFailure=true,
            accessDeniedIsOwnedInjectionNotOSFault=true, noAssemblyVersionUpdaterFallback=true });
    }

    private static void PathBounds(List<object> checks)
    {
        var path = @"C:\Fixture\" + new string('界', RunningBuildInfo.MaximumPathLength - @"C:\Fixture\".Length);
        var id = Guid.Parse("90225e84-d163-4460-a6b1-5a5e7c2185c8");
        var good = new RunningBuildInfo("1.2+owned", "1.2.0.0", id, path, "C:/Fixture/Модуль-🧭.dll");
        Require(good.ExecutablePath == path && good.ModulePath == "C:/Fixture/Модуль-🧭.dll",
            "SET08 bounded Unicode paths are truncated, canonicalized or rewritten.");
        foreach (var invalid in new string?[] { null, "", "  ", path + "界", "C:/bad\npath", "C:/bad\0path", "C:/bad\ud800", "C:/bad\udc00" }) {
            var fact = new RunningBuildInfo(good.InformationalVersion, good.AssemblyVersion, Guid.Empty, invalid, good.ModulePath);
            Require(fact.ExecutablePath is null && fact.ModulePath == good.ModulePath && fact.ModuleVersionID is null
                && fact.InformationalVersion == good.InformationalVersion && fact.VersionForUpdates == good.InformationalVersion,
                "SET08 malformed path/empty MVID changes independent metadata or manufactures a location.");
        }
        Require(new RunningBuildInfo("1.2", new string('a', 2049), id, "x", "y").AssemblyVersion is null,
            "SET08 assembly-version fallback bypasses its version bound.");
        checks.Add(new { name="settings.provenance.pathBounds", exactUnicodeAndLimit=true, malformedUTF16AndControlsUnknown=true,
            emptyGuidUnknown=true, noPathNormalizationOrFileExistence=true });
    }

    private static void Startup(List<object> checks)
    {
        var actual = RunningBuildInfo.Startup;
        var app = typeof(SettingsWindow).Assembly;
        Require(!ReferenceEquals(actual, RunningBuildInfo.Unknown)
            && actual.InformationalVersion == app.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
            && actual.ModuleVersionID == app.ManifestModule.ModuleVersionId && actual.ExecutablePath == Environment.ProcessPath
            && actual.ModulePath == app.Location,
            "SET08 startup facts were not captured from this loaded App/process before Application.");
        Require(!RunningBuildInfo.InitializeStartup() && ReferenceEquals(actual, RunningBuildInfo.Startup),
            "SET08 repeated initialization recaptured/replaced the startup record.");
        checks.Add(new { name="settings.provenance.startup", actualOwnedChildAppMetadata=true, startupCapturedOnce=true,
            repeatedInitializeDoesNotReplace=true, noPackageOrSignatureInference=true });
    }

    private static async Task LocaleAsync(Application application, List<object> checks, string language)
    {
        var facts = SettingsProvenanceSamples.Facts("long");
        foreach (var size in new[] { (Width:1020d, Height:720d, Font:13d), (Width:880d, Height:440d, Font:18d) }) {
            var calls = 0;
            await using var fixture = new Owned(application, info:() => { calls++; return facts; },
                width:size.Width, height:size.Height, font:size.Font);
            await fixture.ShowAsync(); var before = fixture.Capture();
            Require(Text.Language == language && calls == 1, "SET08 locale fixture reset language or recaptured facts.");
            var fields = BuildFields(fixture.Window);
            var expected = new[] { facts.InformationalVersion!, facts.ModuleVersionID!.Value.ToString("D"), facts.ExecutablePath!, facts.ModulePath! };
            var labels = new[] { "windows.runningVersion", "windows.runningBuildID", "windows.runningExecutable", "windows.runningModule" };
            for (var index = 0; index < fields.Length; index++) {
                var field = fields[index];
                Require(field.Text == expected[index] && field.IsReadOnly && field.FontSize == size.Font && field.TextWrapping == TextWrapping.Wrap
                    && field.MaxHeight <= 96 && AutomationProperties.GetName(field) == Text.L(labels[index]),
                    "SET08 locale loses exact readonly/wrapping/named facts.");
                await ReachAsync(fixture.Window, field);
                var peer = new TextBoxAutomationPeer(field);
                Require(peer.GetPattern(PatternInterface.Value) is IValueProvider value && value.IsReadOnly && value.Value == expected[index],
                    "SET08 long readonly field loses its full accessible value.");
            }
            var button = UpdateButton(fixture.Window); await ReachAsync(fixture.Window, button);
            Require(button.IsEnabled && AutomationProperties.GetName(button) == Text.L("button.checkNow"),
                "SET08 bottom update control is no longer reachable/named.");
            fixture.RequireUnchanged(before); Require(calls == 1, "SET08 field layout polled its metadata provider.");
        }
        checks.Add(new { name="settings.provenance.locale."+language, actualLoadedGeneral=true,
            defaultAndMinimum18DIP=true, fullReadonlyUnicodeValue=true, positiveFieldAndBottomButtonBounds=true });
    }

    private static async Task FallbacksAsync(Application application, List<object> checks)
    {
        foreach (var facts in new[] { RunningBuildInfo.Unknown, SettingsProvenanceSamples.Facts("assembly") }) {
            var calls = 0;
            await using var fixture = new Owned(application, info:() => facts, update:(_, _) => { calls++; return Task.FromResult<WindowsUpdate?>(null); });
            await fixture.ShowAsync(); var before = fixture.Capture();
            var fields = BuildFields(fixture.Window); var button = UpdateButton(fixture.Window);
            var expectedVersion = facts.AssemblyVersion is { } assembly ? Text.L("windows.assemblyVersion")+": "+assembly : Text.L("windows.buildInfoUnavailable");
            Require(fields[0].Text == expectedVersion && fields[3].Text == Text.L("windows.buildInfoUnavailable")
                && fields[1].Text == (facts.ModuleVersionID?.ToString("D") ?? Text.L("windows.buildInfoUnavailable"))
                && fields[2].Text == (facts.ExecutablePath ?? Text.L("windows.buildInfoUnavailable")) && !button.IsEnabled && calls == 0,
                "SET08 unknown/assembly fallback invalidates independent facts or enables a made-up updater version.");
            Require(((Panel)fixture.Window.Page.Content).Children.OfType<TextBlock>()
                .Any(note => note.Text == Text.L("windows.buildInfoUnavailable")),
                "SET08 missing informational version lacks actual update-unavailable feedback.");
            button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); await Turns();
            Require(calls == 0 && !button.IsEnabled, "SET08 synthetic disabled click called an updater or reenabled a missing-version button.");
            fixture.RequireUnchanged(before);
        }
        checks.Add(new { name="settings.provenance.fallbacks", independentlyUnavailable=true, explicitAssemblyDisplayOnly=true,
            actualDisabledCheckNowNoInvocation=true });
    }

    private static async Task ModuleIdentityAsync(Application application, List<object> checks)
    {
        var first = SettingsProvenanceSamples.Facts("hosted");
        var second = new RunningBuildInfo(first.InformationalVersion, first.AssemblyVersion,
            Guid.Parse("42b86c50-7542-4fde-b90e-84884864783e"), first.ExecutablePath, first.ModulePath);
        var displayed = new List<string>();
        foreach (var facts in new[] { first, second, first }) {
            await using var fixture = new Owned(application, info:() => facts);
            await fixture.ShowAsync(); var before = fixture.Capture(); var fields = BuildFields(fixture.Window);
            Require(fields[0].Text == first.InformationalVersion && fields[2].Text == @"C:\Fixture\dotnet\dotnet.exe"
                && fields[3].Text == @"C:\Fixture\Hosted\DevDeck.Windows.dll" && fields[2].Text != fields[3].Text,
                "SET08 hosted process/module paths are substituted or mislabeled as an apphost.");
            displayed.Add(fields[1].Text); fixture.RequireUnchanged(before);
        }
        Require(displayed[0] != displayed[1] && displayed[0] == displayed[2],
            "SET08 same version cannot distinguish App modules or stable module identity changes.");
        checks.Add(new { name="settings.provenance.moduleIdentity", sameVersionDifferentAppMVID=true,
            hostedExecutableAndModuleDistinct=true, repeatedModuleStable=true });
    }

    private static async Task LifetimeAsync(Application application, List<object> checks)
    {
        var directory = Path.Combine(Path.GetTempPath(), "devdeck-provenance-copy-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try {
            var modulePath = Path.Combine(directory, "DevDeck.Windows.dll");
            var executablePath = Path.Combine(directory, "DevDeck.Windows.exe");
            var sidecar = Path.Combine(directory, "windows-package.json");
            File.WriteAllText(modulePath, "Owned synthetic old module bytes.");
            File.WriteAllText(executablePath, "Owned synthetic executable bytes.");
            File.WriteAllText(sidecar, "{\"version\":\"99.0\",\"releaseQualified\":true}");
            var first = new RunningBuildInfo("1.2+owned-startup", "1.2.0.0", Guid.Parse("90225e84-d163-4460-a6b1-5a5e7c2185c8"), executablePath, modulePath);
            var later = new RunningBuildInfo("99.0+owned-newer", "99.0.0.0", Guid.NewGuid(), @"C:\Fixture\new.exe", @"C:\Fixture\new.dll");
            var offered = first; var calls = 0; var language = Text.Language;
            await using var fixture = new Owned(application, info:() => { calls++; return offered; });
            await fixture.ShowAsync(); var before = fixture.Capture(); var page = fixture.Window.Page.Content;
            var initial = BuildFields(fixture.Window);
            offered = later; File.WriteAllText(sidecar, new string('{', 8192)); File.Delete(modulePath); File.Delete(executablePath);
            fixture.Window.ReloadNavigation(); fixture.Window.ReconcileProjectSidebar(ProjectID); fixture.Window.Search.Text = "Owned";
            fixture.Window.Hide(); fixture.Window.Show(); await Turns();
            Require(ReferenceEquals(page, fixture.Window.Page.Content) && initial.SequenceEqual(BuildFields(fixture.Window)),
                "SET08 cached-only reconciliation replaced its running-copy controls.");
            await fixture.Window.SelectPageAsync("deck"); Text.Use(language=="fr" ? "it" : "fr");
            await fixture.Window.SelectPageAsync("general"); await Turns(); var fields = BuildFields(fixture.Window);
            Require(calls == 1 && fields[0].Text == first.InformationalVersion && fields[1].Text == first.ModuleVersionID?.ToString("D")
                && fields[2].Text == executablePath && fields[3].Text == modulePath,
                "SET08 revisit/re-show/localized formatting polled newer metadata or guessed a path after file removal.");
            fixture.RequireUnchanged(before); Text.Use(language);
            // Exercise the actual reusable sample routes, not parallel fixture windows.
            // These calls must not replace this retained controller's owner/read/state.
            await RequireSyntheticSampleAsync(Program.CreateSampleSettingsWindow(fixture.Controller), ownsController:false);
            fixture.RequireUnchanged(before);
            await RequireSyntheticSampleAsync(await SettingsGeometrySamples.CreateAsync(fixture.Controller,"general"), ownsController:false);
            fixture.RequireUnchanged(before);
            await RequireSyntheticSampleAsync(await SettingsSidebarSamples.WindowAsync(application,"empty"), ownsController:true);
            fixture.RequireUnchanged(before);
        } finally {
            foreach (var name in new[] { "windows-package.json", "DevDeck.Windows.dll", "DevDeck.Windows.exe" })
                File.Delete(Path.Combine(directory,name));
            Directory.Delete(directory);
        }
        checks.Add(new { name="settings.provenance.lifetime", providerOnce=true, listOnlyControlsRetained=true,
            ownedNewerMalformedSidecarIgnored=true, cachedPathsSurviveOwnedFileRemoval=true, localReformatNoRecapture=true,
            actualProgramGeometrySidebarSamplesUseFakeFacts=true, ownedSampleClosureAndCleanup=true });
    }

    private static async Task RequireSyntheticSampleAsync(SettingsWindow sample, bool ownsController)
    {
        var controller = Field<DeckController>(sample,"controller");
        var store = Field<SettingsStore>(controller,"store");
        var facts = SettingsProvenanceSamples.Facts("native");
        var captured = Field<RunningBuildInfo>(sample,"runningBuildInfo");
        var settings = JsonSerializer.Serialize(controller.Settings,WorkerProtocol.Json);
        var file = File.ReadAllBytes(store.Path);
        var backup = File.Exists(store.Path+".bak") ? File.ReadAllBytes(store.Path+".bak") : null;
        var closed = false;
        try {
            sample.Show(); sample.UpdateLayout(); await Turns();
            Require(sample.SelectedPage=="general" && sample.IsVisible && sample.IsLoaded && new WindowInteropHelper(sample).Handle!=0,
                "SET08 synthetic sample factory lacks an actual shown General/native-owner premise.");
            Require(!ReferenceEquals(captured,RunningBuildInfo.Startup) && captured==facts,
                "SET08 synthetic sample factory retained real startup metadata instead of explicit fake facts.");
            var fields=BuildFields(sample);
            var expected=new[] { facts.InformationalVersion!,facts.ModuleVersionID!.Value.ToString("D"),facts.ExecutablePath!,facts.ModulePath! };
            var labels=new[] { "windows.runningVersion","windows.runningBuildID","windows.runningExecutable","windows.runningModule" };
            for(var index=0;index<fields.Length;index++) {
                Require(fields[index].Text==expected[index] && fields[index].IsReadOnly
                    && AutomationProperties.GetName(fields[index])==Text.L(labels[index]),
                    "SET08 actual synthetic sample fields expose real paths or lose named readonly fake values.");
                await ReachAsync(sample,fields[index]);
            }
            sample.ReloadNavigation(); await sample.SelectPageAsync("general"); await Turns();
            Require(ReferenceEquals(captured,Field<RunningBuildInfo>(sample,"runningBuildInfo"))
                && expected.SequenceEqual(BuildFields(sample).Select(field=>field.Text)),
                "SET08 actual sample reformat recaptured the current process or changed its fake startup facts.");
            Require(settings==JsonSerializer.Serialize(controller.Settings,WorkerProtocol.Json)
                && file.SequenceEqual(File.ReadAllBytes(store.Path))
                && (backup is null ? !File.Exists(store.Path+".bak") : backup.SequenceEqual(File.ReadAllBytes(store.Path+".bak"))),
                "SET08 actual readonly sample writes its owned metadata/backup.");
        } finally {
            try { closed=await sample.CloseSettingsAsync().WaitAsync(TimeSpan.FromSeconds(5)); }
            finally {
                if(ownsController) {
                    controller.CloseViews();
                    foreach(var manager in typeof(DeckController).GetFields(BindingFlags.Instance|BindingFlags.NonPublic)
                        .Where(field=>field.FieldType==typeof(WorkerManager)).Select(field=>(WorkerManager)field.GetValue(controller)!))
                        await manager.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(5));
                }
            }
        }
        Require(closed && sample.GeometryOwnerClosed && !sample.IsVisible,
            "SET08 actual synthetic sample failed bounded owned-window closure.");
        if(ownsController) Require(!File.Exists(store.Path) && !File.Exists(store.Path+".bak"),
            "SET08 independent sidebar sample failed its actual owned-store cleanup.");
    }

    private static async Task UpdaterAsync(Application application, List<object> checks)
    {
        var facts = new RunningBuildInfo("0.0.0-windows-dev+exact-owned-suffix", "9.9.9.9", Guid.NewGuid(), "x", "y");
        await using (var inert = new Owned(application, info:() => facts)) {
            await inert.ShowAsync(); var retained = inert.Capture(); var page = inert.Window.Page.Content;
            var text = Descendants<TextBlock>(inert.Window.Page).Select(field => field.Text).ToArray();
            var control = UpdateButton(inert.Window);
            Require(control.IsEnabled, "SET08 known-version inert click lacks its positive enabled premise.");
            control.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); await Turns();
            Require(control.IsEnabled && ReferenceEquals(page,inert.Window.Page.Content)
                && text.SequenceEqual(Descendants<TextBlock>(inert.Window.Page).Select(field => field.Text)),
                "SET08 default live:false update click dispatched work or changed the owning result/page.");
            inert.RequireUnchanged(retained);
        }
        var requests = new List<(string Version,string Runtime)>();
        var receipt = new TaskCompletionSource<WindowsUpdate?>(TaskCreationOptions.RunContinuationsAsynchronously);
        await using var fixture = new Owned(application, info:() => facts, update:(version, runtime) => {
            requests.Add((version,runtime)); return receipt.Task;
        });
        await fixture.ShowAsync(); var before = fixture.Capture();
        var button = UpdateButton(fixture.Window); Require(button.IsEnabled && requests.Count == 0, "SET08 arrival triggered an update check.");
        try {
            button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); await Turns();
            Require(requests.Count == 1 && requests[0].Version == facts.InformationalVersion && requests[0].Runtime ==
                "win-"+System.Runtime.InteropServices.RuntimeInformation.OSArchitecture.ToString().ToLowerInvariant()
                && !button.IsEnabled, "SET08 actual update body substitutes version/runtime or fails its pending premise.");
            fixture.RequireUnchanged(before);
            receipt.SetResult(null);
            await UntilAsync(() => button.IsEnabled && TextFields(fixture.Window.Page).Any(field => field.Text == Text.L("windows.noUpdate")),
                "SET08 fake update completion lost its owning result.");
            Require(requests.Count == 1, "SET08 fake update completion replayed a request.");
            fixture.RequireUnchanged(before);
        } finally { receipt.TrySetResult(null); await Turns(); }
        checks.Add(new { name="settings.provenance.updater", actualCheckNowBody=true, rawInfoAndActualRuntime=true,
            defaultLiveFalseClickInert=true, noAutomaticRequestOrHTTPBrowser=true, resultOwnedAndGateIndependent=true });
    }

    private static async Task MetadataPreservationAsync(Application application, List<object> checks)
    {
        var calls = 0;
        await using var fixture = new Owned(application, info:() => { calls++; return SettingsProvenanceSamples.Facts("native"); });
        await fixture.ShowAsync(); var before = fixture.Capture();
        var field = BuildFields(fixture.Window)[2]; await FocusAsync(fixture.Window, field);
        field.Select(3, 7); var page = fixture.Window.Page.Content;
        fixture.Window.ReloadNavigation(); fixture.Window.ReconcileProjectSidebar(ProjectID); await Turns();
        Require(ReferenceEquals(page, fixture.Window.Page.Content) && ReferenceEquals(field, BuildFields(fixture.Window)[2])
            && field.IsKeyboardFocused && field.SelectionStart == 3 && field.SelectionLength == 7,
            "SET08 cached running-copy presentation loses page, focus, selectable path or caret.");
        await fixture.Window.SelectPageAsync("account:owned.provenance.account");
        var form = (AccountSettingsForm)fixture.Window.Page.Content;
        form.TokenDraft = "Owned unsaved replacement"; Field<TextBox>(form,"label").Text = "Owned unsaved label";
        var message = (TextBlock)typeof(SettingsForm).GetField("Message",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(form)!;
        message.Text = "Owned retained metadata error";
        var epoch = Field<long>(fixture.Window,"tokenOwnerGeneration");
        fixture.Window.ReloadNavigation(); fixture.Window.ReconcileProjectSidebar(ProjectID); await Turns();
        Require(ReferenceEquals(form, fixture.Window.Page.Content) && form.TokenDraft == "Owned unsaved replacement"
            && Field<TextBox>(form,"label").Text == "Owned unsaved label" && message.Text == "Owned retained metadata error"
            && Field<long>(fixture.Window,"tokenOwnerGeneration") == epoch && calls == 1,
            "SET08 cached metadata changes a retained account draft/password/error/epoch or recaptures facts.");
        fixture.RequireUnchanged(before);
        checks.Add(new { name="settings.provenance.metadataPreservation", positiveGlobalsHiddenHwndReadGatePreserved=true,
            selectedReadonlyPathFocusCaret=true, retainedAccountDraftPasswordErrorEpoch=true, noMetadataOrCredentialWrites=true });
    }

    private static TextBox[] BuildFields(SettingsWindow window)
    {
        var identities = new[] { "version", "buildID", "executable", "module" };
        return identities.Select(identity => Descendants<TextBox>(window.Page).Single(field =>
            AutomationProperties.GetAutomationId(field) == "settings.runningBuild."+identity)).ToArray();
    }
    private static Button UpdateButton(SettingsWindow window) => Descendants<Button>(window.Page)
        .Single(button => AutomationProperties.GetAutomationId(button) == "settings.checkUpdate");
    private static async Task ReachAsync(SettingsWindow window, FrameworkElement element)
    {
        await Turns(); element.BringIntoView(); window.UpdateLayout(); await Turns();
        var bounds = element.TransformToAncestor(window.Page).TransformBounds(new Rect(new Point(), element.RenderSize));
        Require(element.IsLoaded && element.IsVisible && element.ActualWidth > 0 && element.ActualHeight > 0
            && PresentationSource.FromVisual(element) is not null && window.Page.ViewportWidth > 0 && window.Page.ViewportHeight > 0
            && bounds.Left >= -.6 && bounds.Right <= window.Page.ViewportWidth+.6
            && bounds.Top >= -.6 && bounds.Bottom <= window.Page.ViewportHeight+.6,
            "SET08 named field/control has no positive rendered/reachable viewport bounds.");
    }
    private static async Task FocusAsync(SettingsWindow window, TextBox field)
    {
        await ReachAsync(window,field); window.Activate(); await Turns(); Keyboard.Focus(field); await Turns();
        Require(field.IsKeyboardFocused, "SET08 owned selectable path did not obtain keyboard focus.");
    }
    private static async Task UntilAsync(Func<bool> ready, string failure)
    {
        var deadline = DateTime.UtcNow.AddSeconds(3);
        while (!ready() && DateTime.UtcNow < deadline) { await Turns(); await Task.Delay(10); }
        Require(ready(),failure);
    }

    internal static async Task RunRedAsync(Application application, List<object> checks, string scenario)
    {
        if (scenario is not ("build" or "location"))
            throw new ArgumentException("Unknown provenance baseline case.", nameof(scenario));

        // Read the App loaded in THIS owned qualification child, never Core, a fixture DTO,
        // another process, a package sidecar, repository VERSION or a DLL reopened from disk.
        var appAssembly = typeof(SettingsWindow).Assembly;
        var version = appAssembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        var moduleID = appAssembly.ManifestModule.ModuleVersionId;
        var processPath = Environment.ProcessPath;
        Require(!string.IsNullOrEmpty(version) && moduleID != Guid.Empty && !string.IsNullOrEmpty(processPath),
            "SET08 baseline requires the owned child's loaded App version/module and process path.");

        await using var fixture = new Owned(application);
        await fixture.ShowAsync();
        var before = fixture.Capture();
        await fixture.Window.SelectPageAsync("general");
        fixture.Window.UpdateLayout();
        await Turns();
        // Explicit navigation normally reconstructs a builtin page; preserve its globals,
        // then require this newly selected actual page to survive the readonly inspection.
        var originalPage = fixture.Window.Page.Content;

        Require(fixture.Window.SelectedPage == "general"
            && fixture.Window.Page.Content is FrameworkElement panel && panel.IsLoaded && panel.IsVisible
            && panel.ActualWidth > 0 && panel.ActualHeight > 0 && PresentationSource.FromVisual(panel) is not null
            && fixture.Window.Page.ViewportWidth > 0 && fixture.Window.Page.ViewportHeight > 0,
            "SET08 baseline did not retain a real rendered General page.");
        var controls = Descendants<Control>(fixture.Window.Page).Where(control =>
            control.IsVisible && control.ActualWidth > 0 && control.ActualHeight > 0
            && AutomationProperties.GetName(control).Length > 0
            && control is ComboBox or CheckBox or Button).ToArray();
        Require(controls.Length > 0 && new WindowInteropHelper(fixture.Window).Handle != 0,
            "SET08 baseline lacks positive named General controls or its owned native HWND.");
        var text = TextFields(fixture.Window.Page).ToArray();
        Require(text.Any(field => field.Text == "DevDeck " + version),
            "SET08 baseline lost the existing exact loaded informational-version presentation.");

        var expected = scenario == "build" ? moduleID.ToString("D") : processPath!;
        var match = text.FirstOrDefault(field => field.Text.Contains(expected, StringComparison.Ordinal));
        var displayed = match.Element is not null;
        if (displayed) {
            match.Element!.BringIntoView(); fixture.Window.UpdateLayout(); await Turns();
            var bounds = match.Element.TransformToAncestor(fixture.Window.Page)
                .TransformBounds(new Rect(new Point(), match.Element.RenderSize));
            Require(match.Element.IsLoaded && match.Element.IsVisible && match.Element.ActualWidth > 0
                && match.Element.ActualHeight > 0 && PresentationSource.FromVisual(match.Element) is not null
                && bounds.Left >= -.6 && bounds.Right <= fixture.Window.Page.ViewportWidth + .6
                && bounds.Top >= -.6 && bounds.Bottom <= fixture.Window.Page.ViewportHeight + .6,
                "SET08 current-copy text has no usable rendered/reachable General bounds.");
        }

        // These strict positive preservation assertions run BEFORE the expected product red.
        // A broken premise/lifetime/state assertion must not be counted as the missing-fact red.
        fixture.RequireUnchanged(before);
        Require(ReferenceEquals(originalPage, fixture.Window.Page.Content),
            "SET08 readonly General inspection reconstructed its page.");
        Require(displayed, scenario == "build"
            ? "SET08 build: General does not display the current loaded App module ID."
            : "SET08 location: General does not display this process's executable location.");
        checks.Add(new {
            name = "settings.provenance.baseline." + scenario, actualGeneralBody = true,
            existingLoadedVersionPreserved = true, ownedChildMetadata = true,
            positiveNamedControlsAndHwnd = true, positiveGlobalsPreservedBeforeAssertion = true,
            noProviderVaultBrowserStartupOrUpdateAction = true
        });
    }

    private sealed class Owned : IAsyncDisposable
    {
        internal readonly SettingsStore Store;
        internal readonly DeckController Controller;
        internal readonly SettingsWindow Window;
        private readonly ProjectCard local;
        private readonly TaskCompletionSource<WorkerResponse> read = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly SemaphoreSlim actions;
        private Task? pendingRead;
        private CancellationToken readToken;
        private ProjectStatus? retainedSnapshot;
        private int tokenQueries, readCalls;
        private bool actionGateHeld;

        internal Owned(Application application, Func<RunningBuildInfo>? info=null,
            Func<string,string,Task<WindowsUpdate?>>? update=null, double width=1020, double height=720, double font=13)
        {
            Store = new(Path.Combine(Path.GetTempPath(), "devdeck-provenance-baseline-" + Guid.NewGuid().ToString("N") + ".json"));
            var localSettings = new CardSettings(new(ProjectID, Distribution, "local", "/owned/provenance-checkout"),
                "Owned retained project", Enabled:false, X:64, Y:80);
            var account = new RemoteAccountSettings("owned.provenance.account", "Owned provenance account", "github",
                "https://api.github.com", [], [], Enabled:false);
            var seed = new DeckSettings(1, [new(Distribution, "/owned/provenance-runtime", Text.Language)], [localSettings],
                Accounts:[account], RemoteCards:RemoteCardCatalog.All.Select(item =>
                    new RemoteCardSettings(item.Id, item.Kind, item.Kind, Distribution, [], Enabled:false)).ToArray(),
                Language:Text.Language, Notifications:true, SeenAlerts:["owned.provenance.seen"]);
            Store.Save(seed); Store.Save(seed); // Real nonempty preexisting owned backup.
            Controller = new(application, Store, live:false,
                dashboardOpener:(_, _, _) => throw new IOException("Owned provenance fixture must not open a browser."),
                arrangementNameProvider:() => null,
                settingsCheckWorkerFactory:_ => throw new IOException("Owned provenance fixture must not acquire a worker."));
            local = new(Controller, Controller.Settings.Cards.Single(), live:false,
                phoneAddress:() => null, copyPhoneLink:_ => throw new IOException("Owned provenance fixture must not copy a link."),
                statusReader:(_, cancellation) => { readCalls++; readToken = cancellation; return read.Task; },
                actionRunner:(_, _, _) => throw new IOException("Owned provenance fixture must not run a project action."));
            Field<List<ProjectCard>>(Controller, "cards").Add(local);
            Field<Dictionary<string, CardSettings>>(Controller, "localConfigurations")[ProjectID] = localSettings;
            local.ApplySnapshot(Status()); new WindowInteropHelper(local).EnsureHandle();
            Window = new(Controller, live:false, tokenAvailable:_ => { tokenQueries++; return false; },
                accountFormFactory:CreateAccountForm, runningBuildInfoProvider:info, updateChecker:update) {
                Width=width,Height=height,FontSize=font
            };
            SetField(Controller, "settingsWindow", Window);
            actions = Field<SemaphoreSlim>(Controller, "actions");
            SeedGlobals();
        }

        private static AccountSettingsForm CreateAccountForm(SettingsWindow.AccountFormBinding binding) => new(
            binding.Controller,binding.Account,binding.Live,binding.Changed,binding.NewProvider,
            confirmation:binding.Confirmation, credentialChanged:binding.CredentialChanged,
            credentialWriter:(_,_) => throw new IOException("Owned provenance fixture must not write a credential."),
            verifyCredential:(_,_,_,_) => throw new IOException("Owned provenance fixture must not verify a credential."),
            discoverDistributions:_ => Task.FromResult(new[] { Distribution }),
            browserOpener:(_,_,_) => throw new IOException("Owned provenance fixture must not open a browser."),
            browserPickerFactory:(id,profile) => new(id,profile,[],_ => []),
            tokenPresent:binding.TokenPresent, ownerCurrent:binding.OwnerCurrent, ownerGeneration:binding.OwnerGeneration,
            storedPresenceChanged:binding.PresenceChanged,
            storedCredentialReader:_ => throw new IOException("Owned provenance fixture must not read a credential."),
            acquireStoredVerifier:(_,_) => throw new IOException("Owned provenance fixture must not acquire a worker."));

        internal async Task ShowAsync()
        {
            Require(await actions.WaitAsync(TimeSpan.FromSeconds(5)), "Owned provenance action gate could not be held.");
            actionGateHeld = true;
            Window.Show(); Window.UpdateLayout(); await Turns();
            Require(Window.IsVisible && Window.IsLoaded && Window.IsEnabled && Window.SelectedPage == "general",
                "Owned provenance General window failed to load visibly.");
            pendingRead = local.RefreshAsync(); local.SetDeckVisible(false); await Turns();
            retainedSnapshot = local.Latest;
            Require(pendingRead is { IsCompleted:false } && readCalls == 1 && readToken.CanBeCanceled
                && !readToken.IsCancellationRequested && !local.IsVisible && !local.DeckVisible
                && local.Latest?.State == "running" && new WindowInteropHelper(local).Handle != 0,
                "Owned provenance fixture lacks its positive hidden cached HWND and pending injected status reader.");
            Require(Field<AttentionTracker>(Controller, "attention").SignalItems.Length > 0
                && Field<AttentionTracker>(Controller, "attention").Items.Length > 0
                && Field<NotificationLedger>(Controller, "notifications").Seen.Length > 0
                && Field<IList>(Controller, "pendingAlerts").Count > 0
                && ((IEnumerable)Field<object>(Controller, "deliveries")).Cast<object>().Any()
                && Field<object?>(Controller, "activeDelivery") is not null
                && Controller.LastCheckedAt is not null && actions.CurrentCount == 0
                && File.Exists(Store.Path + ".bak") && new FileInfo(Store.Path + ".bak").Length > 0,
                "Owned provenance fixture lacks positive retained attention/Seen/queue/clock/gate/backup state.");
            Require(tokenQueries == 1, "Owned provenance token-availability fake was not cached once.");
            RequireIsolation();
        }

        private void SeedGlobals()
        {
            var tracker = Field<AttentionTracker>(Controller, "attention");
            tracker.Observe(new AttentionSnapshot("local:" + Distribution,
                [new("owned.provenance.signal", "owned.provenance.key", "waiting", "github", "Owned waiting work",
                    "Owned retained facts", 1000, new("none"), false, false)], []));
            tracker.Observe(new RemoteSnapshot("owned.provenance.legacy", "pullRequests", 1, 0, null, [], [], false,
                Attention:[new("owned.provenance.legacy.item", "owned.provenance.legacy.key", "owned.provenance.account",
                    "review", "Owned legacy attention", null)]));
            var alert = new DeckAlert("owned.provenance.pending", "cantCheck", ProjectID, "Owned pending",
                "Owned detail", "Owned body", "", new("menu"), true);
            Field<NotificationLedger>(Controller, "notifications").Observe(new("synthetic:provenance", [], [alert]), Controller.Settings);
            var scopedType = typeof(DeckController).GetNestedType("ScopedAlert", BindingFlags.NonPublic)!;
            var scoped = Activator.CreateInstance(scopedType, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
                null, ["local:" + Distribution, alert], null)!;
            Field<IList>(Controller, "pendingAlerts").Add(scoped);
            var sources = Array.CreateInstance(scopedType, 1); sources.SetValue(scoped, 0);
            var deliveryType = typeof(DeckController).GetNestedType("Delivery", BindingFlags.NonPublic)!;
            var delivery = Activator.CreateInstance(deliveryType, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
                null, [sources, false], null)!;
            Field<object>(Controller, "deliveries").GetType().GetMethod("Enqueue")!.Invoke(Field<object>(Controller, "deliveries"), [delivery]);
            SetField(Controller, "activeDelivery", delivery); SetField(Controller, "activeAlert", alert);
            SetField(Controller, "lastCheckedAt", DateTimeOffset.FromUnixTimeSeconds(1000));
        }

        internal string Capture() => JsonSerializer.Serialize(new {
            settings = Controller.Settings, file = Convert.ToHexString(File.ReadAllBytes(Store.Path)),
            backup = Convert.ToHexString(File.ReadAllBytes(Store.Path + ".bak")), clock = Controller.LastCheckedAt,
            signals = Field<Dictionary<string, AttentionItem[]>>(Field<AttentionTracker>(Controller, "attention"), "signals"),
            legacy = Field<AttentionTracker>(Controller, "attention").Items,
            announced = Field<HashSet<string>>(Field<AttentionTracker>(Controller, "attention"), "announced").OrderBy(value => value).ToArray(),
            seen = Field<NotificationLedger>(Controller, "notifications").Seen,
            observed = Field<HashSet<string>>(Field<NotificationLedger>(Controller, "notifications"), "observed").OrderBy(value => value).ToArray(),
            pending = Field<IList>(Controller, "pendingAlerts").Cast<object>().ToArray(),
            queue = ((IEnumerable)Field<object>(Controller, "deliveries")).Cast<object>().ToArray(),
            activeDelivery = Field<object?>(Controller, "activeDelivery"), activeAlert = Field<DeckAlert?>(Controller, "activeAlert"),
            timers = new[] { "localPolling", "sharedPolling", "notificationBatch", "notificationExpiry", "nextNotification" }
                .Select(name => Field<DispatcherTimer>(Controller, name).IsEnabled).ToArray(),
            hwnd = new WindowInteropHelper(local).Handle.ToInt64(), snapshot = local.Latest, reference = local.Reference,
            hidden = !local.IsVisible && !local.DeckVisible, tokenQueries, readCalls, gateCount = actions.CurrentCount
        }, WorkerProtocol.Json);

        internal void RequireUnchanged(string before)
        {
            Require(Capture() == before && pendingRead is { IsCompleted:false } && !readToken.IsCancellationRequested
                && ReferenceEquals(Controller.SettingsView, Window) && ReferenceEquals(local.Latest, retainedSnapshot)
                && Controller.AllLocalViews.Length == 1 && ReferenceEquals(Controller.AllLocalViews[0], local)
                && actions.CurrentCount == 0,
                "SET08 General inspection changed owned persistence/backup/attention/Seen/queue/clock/hidden owner/read/gate/cache.");
            RequireIsolation();
        }

        private void RequireIsolation()
        {
            var managers = typeof(DeckController).GetFields(BindingFlags.Instance | BindingFlags.NonPublic)
                .Where(field => field.FieldType == typeof(WorkerManager));
            var count = managers.Sum(field => ((IDictionary)typeof(WorkerManager)
                .GetField("workers", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(field.GetValue(Controller))!).Count);
            Require(count == 0 && !Controller.LocalPollEnabled && !Controller.SharedPollEnabled
                && Field<object?>(Controller, "tray") is null,
                "Owned provenance inspection started a worker, polling loop or actual notification tray.");
        }

        public async ValueTask DisposeAsync()
        {
            if (actionGateHeld) { actionGateHeld = false; actions.Release(); }
            read.TrySetResult(new(1, "owned-provenance-status", Distribution, null, Status(), null, null));
            try {
                if (pendingRead is not null) await pendingRead.WaitAsync(TimeSpan.FromSeconds(5));
                await Window.CloseSettingsAsync().WaitAsync(TimeSpan.FromSeconds(5));
            }
            finally {
                SetField(Controller, "settingsWindow", null); Controller.CloseViews();
                foreach (var manager in typeof(DeckController).GetFields(BindingFlags.Instance | BindingFlags.NonPublic)
                    .Where(field => field.FieldType == typeof(WorkerManager)).Select(field => (WorkerManager)field.GetValue(Controller)!))
                    await manager.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(5));
                foreach (var file in new[] { Store.Path, Store.Path + ".bak" }) if (File.Exists(file)) File.Delete(file);
            }
        }
    }

    private static ProjectStatus Status() => new(ProjectID, "running", "owned.branch", null, "Owned framework", null);
    private readonly record struct TextField(FrameworkElement? Element, string Text);
    private static IEnumerable<TextField> TextFields(DependencyObject root) => Descendants<FrameworkElement>(root)
        .Where(element => element.IsVisible && element.ActualWidth > 0 && element.ActualHeight > 0)
        .Select(element => element switch {
            TextBlock text => new TextField(text, text.Text),
            TextBox text => new TextField(text, text.Text),
            _ => default
        }).Where(field => field.Element is not null);
    private static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
    {
        if (root is T item) yield return item;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
            foreach (var nested in Descendants<T>(VisualTreeHelper.GetChild(root, index))) yield return nested;
    }
    private static T Field<T>(object owner, string name) => (T)owner.GetType()
        .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(owner)!;
    private static void SetField(object owner, string name, object? value) => owner.GetType()
        .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(owner, value);
    private static async Task Turns() { for (var turn = 0; turn < 3; turn++) await Dispatcher.Yield(DispatcherPriority.Background); }
    private static void Require(bool value, string message) { if (!value) throw new IOException(message); }
}
