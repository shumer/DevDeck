using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Runtime.InteropServices;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal static class WindowChecks
{
    internal static async Task RunSettingsNavigationAsync(Application application, List<object> checks)
    {
        var path=Path.Combine(Path.GetTempPath(),"devdeck-sidebar-legacy-"+Guid.NewGuid().ToString("N")+".json");
        var controller=SampleDeck.Controller(application,path);
        try { await CheckSettingsNavigationAsync(application,controller,checks); }
        finally { controller.CloseViews(); foreach(var file in new[]{path,path+".bak"}) if(File.Exists(file)) File.Delete(file); }
    }
    internal static async Task RunAsync(Application application, string report)
    {
        var sampleSettingsPath = Path.Combine(Path.GetTempPath(), "devdeck-column-ui-" + Guid.NewGuid().ToString("N") + ".json");
        var controller = SampleDeck.Controller(application,sampleSettingsPath);
        var checks = new List<object>();
        using var checkProgress = new NativeCheckProgress(report, () => checks.Count);
        await checkProgress.RunAsync("AccountProviderTests.RunAsync", () => AccountProviderTests.RunAsync(application,checks));
        await checkProgress.RunAsync("SettingsGeometryTests.RunAsync", () => SettingsGeometryTests.RunAsync(application,checks));
        await checkProgress.RunAsync("SettingsSidebarTests.RunAsync", () => SettingsSidebarTests.RunAsync(application,checks));
        await checkProgress.RunAsync("SettingsSidebarPublicationTests.RunAsync", () => SettingsSidebarPublicationTests.RunAsync(application,checks));
        await checkProgress.RunAsync("AttentionActivationTests.ShowCardAsync", () => AttentionActivationTests.ShowCardAsync(application,checks));
        await checkProgress.RunAsync("TrayAttentionActionsChecks.RunAsync", () => TrayAttentionActionsChecks.RunAsync(application,checks));
        await checkProgress.RunAsync("TrayAttentionModifierTests.RunAsync", () => TrayAttentionModifierTests.RunAsync(application,checks));
        await checkProgress.RunAsync("TrayAttentionMenuRebuildTests.RunAsync", () => TrayAttentionMenuRebuildTests.RunAsync(application,checks));
        await checkProgress.RunAsync("AttentionReadLifetimeTests.RunAsync", () => AttentionReadLifetimeTests.RunAsync(application,checks));
        await checkProgress.RunAsync("AttentionPrimaryDispatchTests.RunAsync", () => AttentionPrimaryDispatchTests.RunAsync(application,checks));
        await checkProgress.RunAsync("AttentionDismissAdmissionTests.RunAsync", () => AttentionDismissAdmissionTests.RunAsync(application,checks));
        await checkProgress.RunAsync("WorkInFlightPresenceTests.RunAsync", () => WorkInFlightPresenceTests.RunAsync(application, checks));
        await checkProgress.RunAsync("WorkInFlightCoordinatorTests.RunAsync", () => WorkInFlightCoordinatorTests.RunAsync(application, checks));
        await checkProgress.RunAsync("SharedDeckRefreshTests.RunAsync", () => SharedDeckRefreshTests.RunAsync(application, checks));
        await checkProgress.RunAsync("WorkInFlightViewTests.RunAsync", () => WorkInFlightViewTests.RunAsync(application,checks));
        controller.ScheduleLocalRefresh();
        if (controller.LocalPollInterval.TotalSeconds != 10 || controller.LocalPollEnabled) throw new IOException("Local poll cadence or synthetic no-worker guard changed.");
        checks.Add(new { name = "localPoll.cadence", seconds = 10, syntheticDeckDoesNotFetch = true });
        var guardedPoll = new ProjectCard(controller,controller.Settings.Cards[0],live:false);
        try {
            guardedPoll.Show();
            if (!guardedPoll.CanRefresh) throw new IOException("Active idle local card excluded from polling.");
            guardedPoll.ShowOperation("start");
            if (guardedPoll.CanRefresh) throw new IOException("Polling can repaint a busy local operation.");
            guardedPoll.ApplySnapshot(new(guardedPoll.Reference.Id,"stopped",null,null,null,null));
            if (!guardedPoll.CanRefresh) throw new IOException("Finished operation did not resume polling.");
        } finally { guardedPoll.Close(); }
        if (guardedPoll.CanRefresh) throw new IOException("Closed local card still polls.");
        checks.Add(new { name = "localPoll.guards", skipsBusyAndClosed = true, resumesIdle = true });
        await checkProgress.RunAsync("TrayCommandPresenceTests.RunAsync", () => TrayCommandPresenceTests.RunAsync(application, checks));
        await checkProgress.RunAsync("TrayCommandActionTests.RunAsync", () => TrayCommandActionTests.RunAsync(application, checks));
        await checkProgress.RunAsync("NativeArrangementTests.RunAsync", () => NativeArrangementTests.RunAsync(application, checks));
        await checkProgress.RunAsync("ArrangementNameDialogTests.RunAsync", () => ArrangementNameDialogTests.RunAsync(application, checks));
        await checkProgress.RunAsync("DDEVPowerOffCoordinatorTests.RunAsync", () => DDEVPowerOffCoordinatorTests.RunAsync(application, checks));
        await checkProgress.RunAsync("DDEVPowerOffViewTests.RunAsync", () => DDEVPowerOffViewTests.RunAsync(application, checks));
        await checkProgress.RunAsync("NativeVisibilityTests.RunAsync", () => NativeVisibilityTests.RunAsync(application, checks));
        await checkProgress.RunAsync("VisibilitySettingsTests.RunAsync", () => VisibilitySettingsTests.RunAsync(application, checks));
        await checkProgress.RunAsync("VisibilityAttentionTests.RunAsync", () => VisibilityAttentionTests.RunAsync(application, checks));
        await checkProgress.RunAsync("CatalogOrderTests.RunAsync", () => CatalogOrderTests.RunAsync(application, checks));
        await checkProgress.RunAsync("TrayAttentionTests.RunAsync", () => TrayAttentionTests.RunAsync(application, checks));
        await checkProgress.RunAsync("SettingsCheckTests.RunAsync", () => SettingsCheckTests.RunAsync(application, controller, checks));
        using (var scope = new WindowScope(new ProjectCard(controller,controller.Settings.Cards[0] with {
            Project = controller.Settings.Cards[0].Project with { Kind = "ddev" }, Collapsed = false },live:false))) {
            var card = (ProjectCard)scope.Window; card.Show();
            card.ApplySnapshot(new(card.Reference.Id,"running",null,"https://example.ddev.site",null,null));
            card.ContextMenu!.RaiseEvent(new RoutedEventArgs(ContextMenu.OpenedEvent));
            var qr = card.ContextMenu.Items.OfType<MenuItem>().Single(item => item.Header.ToString() == Text.L("card.phone.title"));
            if (!qr.IsEnabled) throw new IOException("Running routed DDEV leaves the phone QR menu inactive instead of explaining availability.");
            checks.Add(new { name = "phone.routedMenuGuidance", runningDdevMenuActive = true, noNetworkMutation = true });
        }
        foreach (var language in DevDeck.Windows.Core.Localization.Languages) {
            NativeCheckProgress.Current?.Mark("legacy.translated." + language);
            Text.Use(language);
            foreach (var kind in new[] { "ddev","arc","local" }) {
                var fixture = controller.Settings.Cards[0] with {
                    Project = controller.Settings.Cards[0].Project with { Kind = kind }, Collapsed = false, PhoneURL = null };
                string? copied = null;
                using var scope = new WindowScope(new ProjectCard(controller,fixture,live:false,phoneAddress:() => "192.168.1.8",copyPhoneLink:value => copied=value));
                var card = (ProjectCard)scope.Window; card.Show();
                Button PhoneButton() => Buttons(card).Single(button => AutomationProperties.GetName(button) == Text.L("card.phone.title"));
                MenuItem PhoneMenu() {
                    card.ContextMenu!.RaiseEvent(new RoutedEventArgs(ContextMenu.OpenedEvent));
                    return card.ContextMenu.Items.OfType<MenuItem>().Single(item => item.Header.ToString() == Text.L("card.phone.title"));
                }
                var snapshot = new ProjectStatus(card.Reference.Id,"running",null,"http://localhost:8112/front?preview=1#top",null,null);
                card.ApplySnapshot(snapshot); card.UpdateLayout();
                if (!PhoneButton().IsVisible || !PhoneButton().IsEnabled || !PhoneMenu().IsEnabled) throw new IOException("Running loopback QR controls are not available: "+language+"/"+kind);
                card.ShowPhone();
                if (!card.PhoneOpen || card.PhoneContent?.Link is not { Issue:PhoneLinkIssue.None,Address:{ } loopback } || loopback.AbsoluteUri != "http://192.168.1.8:8112/front?preview=1#top" || !Descendants<Image>(card.PhoneContent!).Any()) throw new IOException("Loopback QR popup lost the reachable address or encoded image.");
                card.PhoneContent!.CopyLink();
                if (copied != loopback.AbsoluteUri || card.PhoneOpen) throw new IOException("Copy did not preserve the exact QR URL and dismiss the popup.");
                checks.Add(new { name=language+"."+kind+".phone.loopbackCopy", syntheticLan=true, portPathQueryFragmentRetained=true, encodedImage=true, fakeClipboard=true, copyDismisses=true });
                snapshot = snapshot with { SiteURL="http://192.168.1.8:8112/front?direct=1" };
                card.ApplySnapshot(snapshot); card.ShowPhone();
                if (!card.PhoneOpen || card.PhoneContent?.Link is not { Issue:PhoneLinkIssue.None,Address:{ } lan } || lan.AbsoluteUri != snapshot.SiteURL) throw new IOException("A site already using this physical LAN address cannot open its QR.");
                card.PhoneContent!.CopyLink(); if (card.PhoneOpen || copied != snapshot.SiteURL) throw new IOException("Direct LAN link copy changed the URL or left the popup open.");
                checks.Add(new { name=language+"."+kind+".phone.directLan", samePhysicalAddressAccepted=true, exactURLCopied=true });
                card.SetCollapsed(true); card.UpdateLayout();
                if (PhoneButton().IsVisible || !PhoneMenu().IsEnabled) throw new IOException("Compact mode exposes the full QR icon or disables its context menu.");
                PhoneMenu().RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
                if (!card.PhoneOpen || card.PhoneContent?.Link.Address?.AbsoluteUri != snapshot.SiteURL || card.ActualHeight > 76) throw new IOException("Compact QR menu does not open the existing local URL or expands the card.");
                checks.Add(new { name=language+"."+kind+".phone.compactMenu", iconHidden=true, actualMenuClick=true, popupOpens=true, compactHeightRetained=true });
                snapshot = snapshot with { SiteURL="http://localhost:9223/new/path?fresh=2" };
                card.ApplySnapshot(snapshot);
                if (!card.PhoneOpen || card.PhoneContent?.Link.Address?.AbsoluteUri != "http://192.168.1.8:9223/new/path?fresh=2") throw new IOException("An open QR retains a stale URL after a new project snapshot.");
                checks.Add(new { name=language+"."+kind+".phone.latestAddress", openPopupRefreshes=true, newPortPathQuery=true });
                card.PhoneContent!.CopyLink(); card.SetCollapsed(false); card.UpdateLayout(); PhoneMenu().RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
                if (!card.PhoneOpen || !PhoneButton().IsVisible || card.PhoneContent?.Link.Address?.AbsoluteUri != copied) throw new IOException("QR cannot reopen cleanly after Copy and a compact/full transition.");
                card.PhoneContent!.CopyLink();
                checks.Add(new { name=language+"."+kind+".phone.copyReopen", copyDismisses=true, menuReopens=true, fullIconRestored=true });
            }
            var ddevPhone = controller.Settings.Cards[0] with {
                Project=controller.Settings.Cards[0].Project with { Kind="ddev" }, Collapsed=false,PhoneURL=null };
            string? lanAddress = "192.168.1.8";
            using (var scope = new WindowScope(new ProjectCard(controller,ddevPhone,live:false,phoneAddress:() => lanAddress,copyPhoneLink:_ => throw new IOException("Unavailable QR copied a link.")))) {
                var card=(ProjectCard)scope.Window; card.Show();
                Button PhoneButton() => Buttons(card).Single(button => AutomationProperties.GetName(button) == Text.L("card.phone.title"));
                MenuItem PhoneMenu() {
                    card.ContextMenu!.RaiseEvent(new RoutedEventArgs(ContextMenu.OpenedEvent));
                    return card.ContextMenu.Items.OfType<MenuItem>().Single(item => item.Header.ToString() == Text.L("card.phone.title"));
                }
                var snapshot = new ProjectStatus(card.Reference.Id,"running",null,"http://localhost:8112/front",null,null);
                card.ApplySnapshot(snapshot); card.ShowPhone();
                card.ApplySnapshot(snapshot with { SiteURL="https://example.ddev.site" }); card.UpdateLayout();
                if (!PhoneButton().IsVisible || !PhoneButton().IsEnabled || !PhoneMenu().IsEnabled || !card.PhoneOpen || card.PhoneContent?.Link is not { Address:null,Issue:PhoneLinkIssue.RoutedHost } || Descendants<Image>(card.PhoneContent!).Any() || Buttons(card.PhoneContent!).Any(button => button.IsEnabled && AutomationProperties.GetName(button)==Text.L("windows.copyLink"))) throw new IOException("Routed DDEV URL leaves an inactive QR or fabricates a usable phone address.");
                checks.Add(new { name=language+".phone.routedGuidance", runningIconAndMenuActive=true, availablePopupBecomesGuidance=true, noFakeQRCode=true, copyUnavailable=true });
                lanAddress=null; card.ApplySnapshot(snapshot); card.ShowPhone();
                if (!card.PhoneOpen || card.PhoneContent?.Link is not { Address:null,Issue:PhoneLinkIssue.NoLAN } || Descendants<Image>(card.PhoneContent!).Any()) throw new IOException("No LAN address silently disables QR instead of giving guidance.");
                checks.Add(new { name=language+".phone.noLanGuidance", deterministicNoNetwork=true, popupExplainsAvailability=true, noQRCode=true });
                lanAddress="192.168.1.8"; card.ApplySnapshot(snapshot); card.ShowPhone(); card.MarkPhoneUnavailable(); card.UpdateLayout();
                if (card.PhoneOpen || PhoneButton().IsVisible || !PhoneMenu().IsEnabled) throw new IOException("Failed status refresh retains the old QR icon/popup or blocks failure guidance.");
                PhoneMenu().RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
                if (!card.PhoneOpen || card.PhoneContent?.Link is not { Address:null,Issue:PhoneLinkIssue.Unavailable } || Descendants<Image>(card.PhoneContent!).Any()) throw new IOException("Failed refresh lets the QR menu regenerate a stale running URL.");
                card.ApplySnapshot(snapshot);
                if (!card.PhoneOpen || card.PhoneContent?.Link is not { Issue:PhoneLinkIssue.None,Address:{ } recovered } || recovered.AbsoluteUri != "http://192.168.1.8:8112/front") throw new IOException("A fresh verified snapshot does not recover QR after status failure.");
                checks.Add(new { name=language+".phone.failedRefresh", oldQRCodeDiscarded=true, menuExplainsUnavailable=true, noStaleLink=true, freshSnapshotRestores=true });
                card.ApplySnapshot(snapshot with { State="stopped" }); card.UpdateLayout();
                if (card.PhoneOpen || PhoneButton().IsVisible || !PhoneMenu().IsEnabled) throw new IOException("Stopped card exposes the QR icon, retains an old QR, or blocks availability guidance.");
                PhoneMenu().RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
                if (!card.PhoneOpen || card.PhoneContent?.Link is not { Address:null,Issue:PhoneLinkIssue.NotRunning }) throw new IOException("Stopped QR menu does not explain that the local project must run.");
                checks.Add(new { name=language+".phone.stoppedGuidance", iconHidden=true, oldPopupClosed=true, menuCanExplain=true });
                lanAddress="192.168.1.8"; card.ApplySnapshot(snapshot); card.ShowPhone(); card.ShowOperation("restart"); card.UpdateLayout();
                if (card.PhoneOpen || PhoneButton().IsVisible || PhoneMenu().IsEnabled) throw new IOException("Busy card retains or exposes phone QR controls.");
                card.SetCollapsed(true); card.SetCollapsed(false); card.UpdateLayout();
                if (card.PhoneOpen || PhoneButton().IsVisible || PhoneMenu().IsEnabled) throw new IOException("Busy compact/full transition restores QR controls.");
                checks.Add(new { name=language+".phone.busyControls", popupClosed=true, iconHidden=true, menuDisabled=true, modeTransitionsRetainBusy=true });
            }
            using (var scope = new WindowScope(new ProjectCard(controller,ddevPhone with { PhoneURL="https://phone.example.com/front?preview=1" },live:false,phoneAddress:() => null,copyPhoneLink:_ => { }))) {
                var card=(ProjectCard)scope.Window; card.Show(); card.ApplySnapshot(new(card.Reference.Id,"running",null,"https://example.ddev.site",null,null)); card.ShowPhone();
                if (!card.PhoneOpen || card.PhoneContent?.Link is not { Issue:PhoneLinkIssue.None,Address:{ } explicitURL } || explicitURL.AbsoluteUri != "https://phone.example.com/front?preview=1") throw new IOException("An explicit phone URL still requires a loopback site or physical LAN address.");
                card.PhoneContent!.CopyLink(); if (card.PhoneOpen) throw new IOException("Explicit QR Copy did not dismiss.");
                checks.Add(new { name=language+".phone.explicitURL", routedDdevSupportedByChosenURL=true, noLanRequired=true, copyDismisses=true });
            }
            foreach (var kind in new[] { "ddev","arc","local" }) {
                var fixture=ddevPhone with { Project=ddevPhone.Project with { Kind=kind,StartCommand=kind=="local" ? "npm run dev" : null }, PhoneURL="https://phone.example.com/old" };
                using var form=new ProjectSettingsForm(controller,fixture,live:false,_ => { });
                using var scope=new WindowScope(new Window { Content=form,Width=1000,Height=1000 }); scope.Window.Show(); scope.Window.UpdateLayout();
                var field=Descendants<TextBox>(form).Single(input => AutomationProperties.GetName(input)==Text.L("windows.phoneURL"));
                if (!field.IsVisible || field.Text!=fixture.PhoneURL) throw new IOException("Project settings hides or loses the existing phone URL.");
                field.Text="https://phone.example.com/new?preview=2"; var draft=form.CreateDraft();
                if (draft.PhoneURL!=field.Text || draft.Project.Id!=fixture.Project.Id || draft.X!=fixture.X || draft.Y!=fixture.Y || draft.Collapsed!=fixture.Collapsed) throw new IOException("Phone URL settings do not preserve the URL and card identity/placement.");
                foreach (var invalid in new[] { "http://localhost:8112/front","https://example.ddev.site","http://preview.localhost:8112/","https://user:secret@phone.example.com","file:///tmp/x","https://phone.example.com/"+new string('Ж',1100),"https://phone.example.com/path\nnext" }) {
                    field.Text=invalid;
                    try { _=form.CreateDraft(); throw new IOException("Invalid explicit phone URL accepted: "+kind); } catch (InvalidOperationException error) when (error.Message==Text.L("windows.validationPhoneURL")) { }
                }
                field.Text=""; if (form.CreateDraft().PhoneURL is not null) throw new IOException("Clearing explicit phone URL does not restore automatic discovery.");
                checks.Add(new { name=language+"."+kind+".phone.settings", visiblePerKind=true, chosenURLRetained=true, identityPlacementRetained=true, unsafeLocalAndOversizedURLsRejected=true, emptyRestoresAutomatic=true });
            }
            var generic = new CardSettings(new("project.detect","Ubuntu-24.04","local","/tmp/synthetic","npm run old",HealthURL:"",Subtitle:"",OpenURL:"http://localhost:4112/front"),"Chosen name",X:91,Y:117);
            var pending = new TaskCompletionSource<ProjectSuggestion?>(); var calls = 0;
            using (var form = new ProjectSettingsForm(controller,generic,live:false,_ => { },reference => {
                if (reference.Path != "/tmp/synthetic" || reference.Kind != "local" || reference.StartCommand is not null) throw new IOException("Detect sent executable configuration rather than a folder reference.");
                calls++; return pending.Task;
            })) {
                using var scope = new WindowScope(new Window { Content = new ScrollViewer { Content=form },Width=1000,Height=900 }); scope.Window.Show(); scope.Window.UpdateLayout();
                TextBox Named(string key) => Descendants<TextBox>(form).Single(field => AutomationProperties.GetName(field) == Text.L(key));
                if (!Buttons(form).Any(button => button.IsVisible && AutomationProperties.GetName(button) == Text.L("button.detect"))) throw new IOException("Generic Detect button is not visible.");
                var detection = form.DetectAsync();
                Named("project.caption").Text = "Chosen caption"; Named("project.checkURL").Text = "http://localhost:8111/health";
                pending.SetResult(new("bun · next + nest","bun run dev","",true,true,"http://localhost:3000")); await detection;
                var draft = form.CreateDraft();
                if (calls != 1 || draft.Project.Id != generic.Project.Id || draft.Title != generic.Title || draft.X != generic.X || draft.Y != generic.Y || draft.Project.Subtitle != "Chosen caption" || draft.Project.HealthURL != "http://localhost:8111/health" || draft.Project.OpenURL != "http://localhost:4112/front" || draft.Project.StartCommand != "bun run dev" || draft.Project.HoldsProcess != true || draft.Project.RequiresDocker != true) throw new IOException("Detect overwrote selected fields or lost inferred commands/modes.");
                checks.Add(new { name=language+".local.detectPreservesEdits", productionAsyncFlow=true, identityAndPlacement=true, distinctURLs=true });
                Named("project.caption").Text = ""; Named("project.checkURL").Text = ""; form.ApplySuggestion(new("bun · next + nest","bun run dev","",true,true,"http://localhost:3000"));
                var filled = form.CreateDraft(); if (filled.Project.Subtitle != "bun · next + nest" || filled.Project.HealthURL != "http://localhost:3000" || filled.Project.OpenURL != generic.Project.OpenURL) throw new IOException("Empty caption/health were not filled or frontend changed.");
                if (form.TestLinkTarget() != "http://localhost:4112/front" || Descendants<TextBlock>(form).Any(label => label.IsVisible && label.Text == Text.L("windows.linkTemplateHint"))) throw new IOException("Generic browser Test lost frontend or shows another integration's hint.");
                Named("project.caption").Text = new string('Ж',257);
                try { _ = form.CreateDraft(); throw new IOException("Overlong caption accepted."); } catch (InvalidOperationException error) when (error.Message == Text.L("windows.validationCaption")) { }
                Named("project.caption").Text = "bun · next + nest"; Named("project.openURL").Text = "https://user:password@example.com";
                try { _ = form.CreateDraft(); throw new IOException("Credential-bearing opening URL accepted."); } catch (InvalidOperationException error) when (error.Message == Text.L("windows.validationOpenURL")) { }
                checks.Add(new { name=language+".local.detectFillsEmpty", captionAndHealth=true, openURLPreserved=true });
            }
            using (var scope = new WindowScope(new ProjectCard(controller,generic with { Project=generic.Project with { Subtitle="bun · next + nest",StartCommand="bun run dev" } },live:false))) {
                var card = (ProjectCard)scope.Window; card.Show(); card.ApplySnapshot(new(generic.Project.Id,"running",null,"http://localhost:4112/front",null,null)); card.UpdateLayout();
                if (!Descendants<TextBlock>(card).Any(label => label.IsVisible && label.Text == "bun run dev") || !Descendants<TextBlock>(card).Any(label => label.IsVisible && label.Text == "bun · next + nest · synthetic")) throw new IOException("Generic caption/checkout and command metadata are missing or combined.");
                card.SetCollapsed(true); card.UpdateLayout(); if (Descendants<TextBlock>(card).Any(label => label.IsVisible && label.Text == "bun run dev")) throw new IOException("Compact generic card exposes command metadata.");
                card.SetCollapsed(false); card.UpdateLayout(); if (!Descendants<TextBlock>(card).Any(label => label.IsVisible && label.Text == "bun run dev")) throw new IOException("Generic command metadata does not return on expansion.");
                checks.Add(new { name=language+".local.captionCommand", distinctMetadata=true, compactRestores=true });
            }
            pending = new();
            using (var form = new ProjectSettingsForm(controller,generic,live:false,_ => { },_ => pending.Task)) {
                using var scope = new WindowScope(new Window { Content=form,Width=1000,Height=900 }); scope.Window.Show();
                var detection = form.DetectAsync(); Descendants<TextBox>(form).Single(field => AutomationProperties.GetName(field) == Text.L("windows.linuxFolder")).Text = "/tmp/other";
                pending.SetResult(new("vite","npm run dev","",true,false,"http://localhost:5173")); await detection;
                if (form.CreateDraft().Project.StartCommand != "npm run old") throw new IOException("A stale Detect result was applied to a different folder.");
                checks.Add(new { name=language+".local.detectStaleFolder", ignored=true });
            }
            Text.Use(language);
            foreach (var kind in new[] { "ddev","arc","local" }) foreach (var action in new[] { "start","stop","restart" }) {
                using var scope = new WindowScope(new ProjectCard(controller,controller.Settings.Cards[0] with {
                    Project = controller.Settings.Cards[0].Project with { Kind = kind }, Collapsed = true },live:false));
                var project = (ProjectCard)scope.Window; project.Show();
                var snapshot = new ProjectStatus(project.Reference.Id,action == "start" ? "stopped" : "running","feature/compact","http://localhost:8080","fixture framework",null);
                project.ApplySnapshot(snapshot); project.ShowOperation(action); project.UpdateLayout();
                Button Named(string key) => Buttons(project).Single(button => AutomationProperties.GetName(button) == Text.L(key));
                var cancellation = Named("button.cancel");
                void Busy(bool compact) {
                    if (!cancellation.IsVisible || !cancellation.IsEnabled || project.CanRefresh ||
                        new[] { Named("card.action.start"), Named("card.action.stop"), Named("card.action.restart") }.Any(button => button.IsVisible) ||
                        Named("card.localSite").IsEnabled || !Named("card.action.terminal").IsVisible)
                        throw new IOException("Busy controls were lost when changing compact mode: "+language+"/"+kind+"/"+action);
                    if (compact && (Math.Abs(cancellation.ActualWidth-30) > 0.1 || Math.Abs(cancellation.ActualHeight-32) > 0.1 || project.ActualHeight > 76))
                        throw new IOException("Compact operation cancellation exceeds icon dimensions: "+language+"/"+kind+"/"+action);
                    if (!compact && (cancellation.ActualWidth < 122 || !Descendants<TextBlock>(cancellation).Any(block => block.Text == Text.L("button.cancel"))))
                        throw new IOException("Full operation lost its cancellation label.");
                }
                Busy(true);
                var progress = Descendants<TextBlock>(project).Single(block => block.Text == Text.L("windows.waitOutcome"));
                progress.Text = "Synthetic operation progress";
                for (var repeat = 0; repeat < 2; repeat++) {
                    project.SetCollapsed(false); project.UpdateLayout(); Busy(false);
                    if (progress.Text != "Synthetic operation progress") throw new IOException("Expanding reset operation progress.");
                    project.SetCollapsed(true); project.UpdateLayout(); Busy(true);
                }
                project.ApplySnapshot(snapshot with { State = action == "stop" ? "stopped" : "running" }); project.UpdateLayout();
                if (cancellation.IsVisible || !project.CanRefresh || project.ActualHeight > 76 ||
                    !Buttons(project).Any(button => button.IsVisible && button.IsEnabled && AutomationProperties.GetName(button) == Text.L(action == "stop" ? "card.action.start" : "card.action.stop")))
                    throw new IOException("Finishing operation did not restore compact idle controls.");
                project.ShowOperation(action); project.UpdateLayout(); Busy(true);
                checks.Add(new { name = language+"."+kind+".compactOperation."+action, width = 30, height = 32,
                    busyTransitions = true, progressRetained = true, idleControlsRestored = true, repeatedOperation = true });
            }
        }
        Text.Use("en");
        foreach (var language in DevDeck.Windows.Core.Localization.Languages) {
            NativeCheckProgress.Current?.Mark("legacy.translated." + language);
            Text.Use(language);
            var hosted = new CardSettings(new("arc.project.synthetic","","arc","",Arc:new("sandbox.example","news")),"Example hosted",X:70,Y:90,Collapsed:false,Links:ProjectLinks.Defaults("arc"));
            using (var scope = new WindowScope(new ProjectCard(controller,hosted,live:false))) {
                var project = (ProjectCard)scope.Window; project.Show(); project.UpdateLayout();
                var names = Buttons(project).Where(button => button.IsVisible && button.IsEnabled).Select(button => AutomationProperties.GetName(button)).ToArray();
                if (!names.Contains("PageBuilder") || !names.Contains("Composer") || !names.Contains("Deployer") || names.Contains("Site Service") || names.Contains(Text.L("card.action.terminal")) || project.CanRefresh)
                    throw new IOException("Hosted Arc links or unavailable local controls regressed.");
                project.SetCollapsed(true); project.UpdateLayout(); if (project.ActualHeight > 76) throw new IOException("Hosted Arc compact height changed.");
                project.SetCollapsed(false); project.UpdateLayout();
                checks.Add(new { name=language+".arc.hosted", noWorkerReads=true, hostedTools=true, localControlsDisabled=true });
            }
            using (var form = new ProjectSettingsForm(controller,hosted,live:false,_ => { })) {
                using var scope = new WindowScope(new Window { Content=form,Width=900,Height=850 }); scope.Window.Show(); scope.Window.UpdateLayout();
                Descendants<TextBox>(form).Single(field => AutomationProperties.GetName(field) == Text.L("project.arc.organisation")).Text = "example";
                Descendants<TextBox>(form).Single(field => AutomationProperties.GetName(field) == Text.L("project.startCommand")).Text = "npm run owned-start";
                Descendants<TextBox>(form).Single(field => AutomationProperties.GetName(field) == Text.L("project.stopCommand")).Text = "npm run owned-stop";
                Descendants<TextBox>(form).Single(field => AutomationProperties.GetName(field) == Text.L("project.openURL")).Text = "http://localhost:8112/front?_website=news";
                Descendants<TextBox>(form).Single(field => AutomationProperties.GetName(field) == Text.L("project.checkURL")).Text = "/health";
                var editor = Descendants<ProjectLinkEditor>(form).Single(); editor.AddLink(new("Custom","https://{org}.example/{site}",false,"site"));
                var custom = editor.Rows.Single(row => row.Label.Text == "Custom"); custom.Label.Text = "Renamed"; custom.Kind.SelectedValue="tool";
                var draft = form.CreateDraft();
                if (draft.Project.Id != hosted.Project.Id || draft.X != hosted.X || draft.Y != hosted.Y || draft.Project.Arc is not { Organization:"example",HealthPath:"/health",LocalURL:"http://localhost:8112/front?_website=news" } || draft.Project.StartCommand != "npm run owned-start" || draft.Project.StopCommand != "npm run owned-stop" ||
                    draft.LinkList.Single(link => link.Label == "Renamed") is not { Enabled:false,Kind:"tool",Url:"https://{org}.example/{site}" }) throw new IOException("Arc form lost configured identity or typed custom metadata.");
                editor.RemoveLink(custom.Label); if (form.CreateDraft().LinkList.Any(link => link.Label == "Renamed")) throw new IOException("Custom link removal failed.");
                Descendants<TextBox>(form).Single(field => AutomationProperties.GetName(field) == Text.L("windows.linuxFolder")).Text="/tmp/checkout";
                Descendants<ComboBox>(form).Single(field => AutomationProperties.GetName(field) == Text.L("windows.distribution")).SelectedItem="Ubuntu-24.04";
                var attached = form.CreateDraft(); if (attached.Project.Id != hosted.Project.Id || !attached.Project.HasLocalFolder) throw new IOException("Attaching checkout renamed hosted project.");
                checks.Add(new { name=language+".arc.settings", typedRows=true, stableAttachment=true, disabledMetadataRetained=true });
            }
            foreach (var kind in new[] { "arc","ddev" }) {
                var reference = new ProjectReference(kind+".project.typed","Ubuntu-24.04",kind,"/tmp/example",Arc:kind=="arc" ? new("sandbox.example","news") : null);
                var settings = new CardSettings(reference,"Example",Links:kind=="arc" ? ProjectLinks.Defaults("arc") : [new("Admin","{site}/user/login",Kind:"tool"),new("PROD","https://example.com",Kind:"site")]);
                using var scope = new WindowScope(new ProjectCard(controller,settings,live:false)); var project=(ProjectCard)scope.Window; project.Show();
                foreach (var state in new[] { "running","stopped" }) {
                    project.ApplySnapshot(new(reference.Id,state,"feature/typed","http://localhost:8112/front?_website=news",null,null,LocalEditorURL:kind=="arc" ? "http://localhost:8112/pagebuilder/experiences/_default/pages/" : null)); project.UpdateLayout();
                    if (state=="stopped" && Buttons(project).Any(button => button.IsVisible && AutomationProperties.GetName(button)==Text.L("card.phone.title"))) throw new IOException("Stopped local project still exposes a phone QR button.");
                    var tool=Buttons(project).Single(button => AutomationProperties.GetName(button)==(kind=="arc" ? "PageBuilder" : "Admin"));
                    if (tool.IsEnabled != (kind=="arc" || state=="running")) throw new IOException("Hosted/local link gating differs from runtime.");
                    if (kind=="arc") {
                        var editorButton=Buttons(project).Single(button => AutomationProperties.GetName(button)==Text.L("card.localPageBuilder"));
                        if (!editorButton.IsVisible || editorButton.IsEnabled != (state=="running") || editorButton.Parent == tool.Parent) throw new IOException("Local PageBuilder group or availability incorrect.");
                    } else {
                        var site=Buttons(project).Single(button => AutomationProperties.GetName(button)=="PROD"); if (!site.IsEnabled || site.Parent == tool.Parent) throw new IOException("Hosted DDEV environment disabled or grouped as a tool.");
                    }
                }
                project.SetCollapsed(true); project.ApplySnapshot(project.Latest! with { State="running" }); project.SetCollapsed(false); project.UpdateLayout();
                if (kind=="arc" && !Buttons(project).Any(button => button.IsVisible && button.IsEnabled && AutomationProperties.GetName(button)==Text.L("card.localPageBuilder"))) throw new IOException("Compact status update lost local PageBuilder on expansion.");
                project.ShowOperation("start"); project.SetCollapsed(true); project.UpdateLayout(); project.SetCollapsed(false); project.UpdateLayout();
                if (Buttons(project).Any(button => button.IsVisible && AutomationProperties.GetName(button)==Text.L("card.phone.title"))) throw new IOException("Busy project exposes a phone QR button after expansion.");
                var hostedTool=Buttons(project).Single(button => AutomationProperties.GetName(button)==(kind=="arc" ? "PageBuilder" : "PROD")); if (!hostedTool.IsEnabled) throw new IOException("Operation disabled a hosted link.");
                checks.Add(new { name=language+"."+kind+".typedLinkGroups", runningStopped=true, operationRetainsHosted=true, distinctGroups=true });
            }
        }
        Text.Use("en");
        await checkProgress.RunAsync("legacy.settingsNavigation", () => CheckSettingsNavigationAsync(application, controller, checks));
        foreach (var kind in new[] { "ddev","arc","github","gitlab","node","next","nest","bun","docker","make","other","general","deck","cards","notifications" }) {
            var mark = BrandMarks.Create(kind,24,tile:true); mark.Measure(new(48,48)); mark.Arrange(new Rect(0,0,48,48));
            checks.Add(new { name = "brand." + kind, vectorRenders = true });
        }
        using (var tray = new TrayIcon()) {
            if (!tray.Added || TrayIcon.NativeDataSize != (nint.Size == 8 ? 976 : 956)) throw new IOException("Native tray registration or structure layout failed.");
            var clicked = 0; var ended = 0;
            tray.BalloonClicked += () => clicked++; tray.BalloonClosed += () => ended++;
            _ = SendMessage(tray.Handle, 0x8000 + 42, 0, (1 << 16) | 0x405);
            _ = SendMessage(tray.Handle, 0x8000 + 42, 0, (1 << 16) | 0x404);
            if (clicked != 1 || ended != 1) throw new IOException("Native tray callback decoding failed.");
            checks.Add(new { name = "native.tray", registered = true, callbackTargets = true, notificationsSent = false });
            foreach (var (tiers, expected) in new (string[], DeckTrayState)[] {
                ([], DeckTrayState.Calm), (["goodToKnow"], DeckTrayState.Calm), (["stuck"], DeckTrayState.Stuck),
                (["needsFixing", "stuck"], DeckTrayState.NeedsFixing), (["waiting", "needsFixing", "stuck"], DeckTrayState.Waiting),
                (["goodToKnow", "waiting"], DeckTrayState.Waiting) }) {
                tray.SetAttention(tiers);
                if (tray.ArtworkState != expected) throw new IOException("Tray attention priority disagrees with the Mac digest.");
                var stable = tray.Icon.Handle; tray.SetAttention(tiers);
                if (tray.Icon.Handle != stable) throw new IOException("An unchanged tray state allocated another icon.");
                checks.Add(new { name = "tray.tier." + string.Join("+",tiers), state = expected.ToString(), cachedHandle = true });
            }
            foreach (var light in new[] { true, false }) foreach (var edge in DeckTrayArtwork.Sizes) {
                var tint = DeckTrayArtwork.Ink(light); tray.ApplyAppearance(tint, edge);
                foreach (var state in Enum.GetValues<DeckTrayState>()) {
                    using var bitmap = DeckTrayArtwork.Render(edge, state, tint);
                    var transparent = 0; var opaque = 0; var red = 0;
                    for (var y = 0; y < edge; y++) for (var x = 0; x < edge; x++) {
                        var pixel = bitmap.GetPixel(x,y);
                        if (pixel.A == 0) transparent++; if (pixel.A > 200) opaque++;
                        if (pixel.A > 100 && pixel.R > 180 && pixel.R > pixel.G * 2 && pixel.R > pixel.B * 2) red++;
                    }
                    var tier = state switch { DeckTrayState.Waiting => "waiting", DeckTrayState.NeedsFixing => "needsFixing", DeckTrayState.Stuck => "stuck", _ => "goodToKnow" };
                    tray.SetAttention([tier]);
                    if (tray.Icon.Size != new System.Drawing.Size(edge,edge) || transparent < edge * edge / 5 || opaque < edge * edge / 6
                        || (red > 0) != (state == DeckTrayState.Waiting)) throw new IOException("Tray artwork lost its size, transparency, stack or exclusive red badge.");
                    checks.Add(new { name = "tray.artwork." + (light ? "light" : "dark") + "." + edge + "." + state, transparent, opaque, red });
                }
            }
            using (var glyph = DeckTrayArtwork.Render(48,DeckTrayState.Calm,DeckTrayArtwork.Ink(false)))
            using (var ring = DeckTrayArtwork.Render(48,DeckTrayState.Stuck,DeckTrayArtwork.Ink(false)))
            using (var dot = DeckTrayArtwork.Render(48,DeckTrayState.NeedsFixing,DeckTrayArtwork.Ink(false))) {
                var holes = 0;
                for (var y = 24; y < 37; y++) for (var x = 12; x < 37; x++) if (glyph.GetPixel(x,y).A < 20) holes++;
                if (holes < 20 || ring.GetPixel(40,13).A > 80 || dot.GetPixel(40,13).A < 200) throw new IOException("Tray DD cutouts or ring/dot distinction disappeared.");
                checks.Add(new { name = "tray.letteringAndShapes", transparentLetterPixels = holes, ringHasHole = true, dotSolid = true });
            }
            tray.SetAttention(["stuck"]);
            _ = SendMessage(tray.Handle, (int)tray.TaskbarCreatedMessage, 0, 0);
            if (!tray.Added || tray.ArtworkState != DeckTrayState.Stuck || tray.Icon.Handle == 0) throw new IOException("Taskbar recreation lost the branded attention state.");
            checks.Add(new { name = "tray.taskbarCreated", syntheticMessage = true, statePreserved = true, explorerRestarted = false });
        }
        var resources = GetGuiResources(System.Diagnostics.Process.GetCurrentProcess().Handle,1);
        for (var cycle = 0; cycle < 12; cycle++) {
            using var tray = new TrayIcon(); tray.ApplyAppearance(DeckTrayArtwork.Ink(cycle % 2 == 0),32);
            tray.SetAttention(["waiting"]); tray.Dispose(); tray.Dispose();
        }
        var retainedResources = (int)GetGuiResources(System.Diagnostics.Process.GetCurrentProcess().Handle,1) - (int)resources;
        if (retainedResources > 8) throw new IOException("Tray replacement/disposal leaked native USER resources.");
        checks.Add(new { name = "tray.ownedDisposal", cycles = 12, retainedResources });
        using var local = new WindowScope(new ProjectCard(controller, new(new("ddev.project.sample", "Ubuntu-24.04", "ddev", "/home/user/example"), "Example shop"), live: false));
        using var remote = new WindowScope(new RemoteCard(controller, new("github.pr.sample", "GitHub pull requests", "pullRequests", "Ubuntu-24.04", ["sample"]), live: false));
        void Check(Window window, string name, bool floating)
        {
            var style = WidgetWindow.ReadStyle(window);
            if (!WidgetWindow.IsExcluded(window) || (style & 0x80000) == 0 || ((style & 8) != 0) != floating)
                throw new IOException("Native widget window regression: " + name);
            checks.Add(new { name, excludedFromSwitcher = true, transparentStylePreserved = true, floating });
        }
        foreach (var scope in new[] { local, remote })
        {
            var window = scope.Window;
            var kind = window is ProjectCard ? "local" : "remote";
            void Mode(bool floating) { if (window is ProjectCard project) project.ApplyMode(floating); else ((RemoteCard)window).ApplyMode(floating); }
            window.Show(); Check(window, kind + ".initial", false);
            Mode(true); Check(window, kind + ".floating", true);
            Mode(false); Check(window, kind + ".desktop", false);
            window.Hide(); window.Show(); Check(window, kind + ".reshow", false);
            if (window is ProjectCard project) project.Summon(); else ((RemoteCard)window).Summon();
            Check(window, kind + ".summon", false);
        }
        foreach (var window in new Window[] { new SettingsWindow(controller, live: false), new RemoteSettingsWindow(controller, live: false),
            new AccountWindow(controller, null, () => { }, live: false), new AttentionWindow(controller, []), new NotificationSettingsWindow(controller), new Window { Title = "Synthetic log/list control" } })
        {
            using var scope = new WindowScope(window);
            _ = new WindowInteropHelper(window).EnsureHandle();
            if ((WidgetWindow.ReadStyle(window) & 0x80) != 0) throw new IOException("Ordinary window was excluded from the switcher.");
            checks.Add(new { name = window.GetType().Name, ordinaryWindow = true });
        }
        foreach (var language in DevDeck.Windows.Core.Localization.Languages)
        {
            Text.Use(language);
            using (var menu = new System.Windows.Forms.ContextMenuStrip()) {
                controller.AddCardMenu(menu);
                foreach (var descriptor in RemoteCardCatalog.All) {
                    var row = menu.Items.OfType<System.Windows.Forms.ToolStripMenuItem>().Single(item => item.Tag as string == descriptor.Kind);
                    if (row.Text != Text.L(descriptor.TitleKey) || row.Checked || !row.Enabled) throw new IOException("Tray card catalog is missing or loses saved visibility: " + language);
                }
                var group = menu.Items.OfType<System.Windows.Forms.ToolStripMenuItem>().Single(item => item.DropDownItems.Count > 0);
                if (group.DropDownItems.Count != 7 || group.DropDownItems.OfType<System.Windows.Forms.ToolStripMenuItem>().Any(item => !item.Checked)) throw new IOException("Tray project visibility group missing.");
                checks.Add(new { name = language + ".tray.cardCatalog", allKindsDiscoverable = true, hiddenStatesPreserved = true, localVisibilityGrouped = true });
            }
            using var scope = new WindowScope(new ProjectCard(controller, new(new("ddev.project.sample", "Ubuntu-24.04", "ddev", "/home/user/example"), "Example shop"), live: false));
            var project = (ProjectCard)scope.Window;
            project.Show();
            foreach (var state in new[] { "running", "stopped", "paused", "starting" })
            {
                project.ApplySnapshot(new("ddev.project.sample", state, "feature/widgets", "http://localhost:8080", "drupal 11", null));
                project.UpdateLayout();
                var buttons = Buttons(project).ToArray();
                Button Named(string key) => buttons.Single(button => AutomationProperties.GetName(button) == Text.L(key));
                if (Named("card.localSite").IsEnabled != (state == "running") || Named("card.action.start").IsVisible != (state is not ("running" or "starting")) ||
                    Named("card.action.stop").IsVisible != (state is "running" or "starting" or "paused"))
                    throw new IOException("Project controls do not match the state: " + language + "." + state);
                var actions = new[] { Named("card.action.start"), Named("card.action.stop"), Named("card.action.restart") }.Where(button => button.IsVisible).ToArray();
                var top = actions[0].TransformToAncestor(project).Transform(new Point()).Y;
                if (actions.Any(button => Math.Abs(button.TransformToAncestor(project).Transform(new Point()).Y - top) > 1))
                    throw new IOException("Translated project actions overflow their row: " + language + "." + state);
                var idleHeight = project.ActualHeight;
                project.ShowOperation("restart"); project.UpdateLayout();
                if (!Named("button.cancel").IsVisible || actions.Any(button => button.IsVisible) || Named("card.localSite").IsEnabled || project.ActualHeight > idleHeight + 1)
                    throw new IOException("Project operation controls overflow or remain active: " + language + "." + state);
                checks.Add(new { name = language + "." + state, singleActionRow = true, siteRequiresRunning = true, compactCancellation = true });
            }
            foreach (var state in new[] { "running","stopped" }) {
                project.SetCollapsed(true); project.ApplySnapshot(new("ddev.project.sample",state,"feature/widgets","http://localhost:8080","drupal 11",null)); project.UpdateLayout();
                if (project.ActualHeight > 76 || !Buttons(project).Single(button => AutomationProperties.GetName(button) == Text.L("card.action.terminal")).IsVisible || !project.ContextMenu.Items.OfType<MenuItem>().Any(item => item.Header.ToString() == Text.L("menu.card.showLog")) || !project.ContextMenu.Items.OfType<MenuItem>().Any(item => item.Header.ToString() == Text.L("project.folder"))) throw new IOException("Collapsed controls lost compact layout or utilities: " + language);
                project.SetCollapsed(false); project.UpdateLayout();
            }
            checks.Add(new { name = language + ".collapsed", singleCompactRow = true, utilitiesReachable = true, repeatedReparenting = true });
            Buttons(project).Single(button => AutomationProperties.GetName(button) == Text.L("menu.card.collapse")).RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); project.UpdateLayout();
            if (project.ActualHeight > 76 || !Buttons(project).Single(button => AutomationProperties.GetName(button) == Text.L("menu.card.showWhole")).IsVisible) throw new IOException("Visible local compact control missing.");
            project.ContextMenu.Items.OfType<MenuItem>().Single(item => item.Header.ToString() == Text.L("menu.card.showWhole")).RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); project.UpdateLayout();
            if (project.ActualHeight <= 76) throw new IOException("Local context-menu expansion failed.");
            checks.Add(new { name = language + ".compact.controls", visibleHeaderToggle = true, contextExpansion = true });
            project.ApplyAttention(new("local:Ubuntu-24.04", [], [], "notRunning", false));
            project.ApplySnapshot(new("ddev.project.sample", "stopped", null, null, null, null)); project.UpdateLayout();
            var gated = Buttons(project).ToArray();
            if (gated.Single(button => AutomationProperties.GetName(button) == Text.L("card.action.start")).IsEnabled
                || gated.Single(button => AutomationProperties.GetName(button) == Text.L("card.action.restart")).IsEnabled
                || !gated.Single(button => AutomationProperties.GetName(button) == Text.L("windows.openDocker")).IsVisible)
                throw new IOException("Docker gating does not match shared readiness.");
            checks.Add(new { name = language + ".docker", startBlocked = true, explicitDockerAction = true });
            foreach (var kind in new[] { "pullRequests","mergeRequests","inbox","actions" }) {
                using var sample = new WindowScope(new RemoteCard(controller,SampleDeck.RemoteSettings(kind),live:false));
                var window = (RemoteCard)sample.Window; var snapshot = SampleDeck.Remote(kind,15);
                window.ApplySnapshot(snapshot); window.Show(); window.UpdateLayout();
                Buttons(window).Single(button => AutomationProperties.GetName(button) == Text.L("menu.card.collapse")).RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); window.UpdateLayout();
                if (window.ActualHeight > 78 || !Buttons(window).Single(button => AutomationProperties.GetName(button) == Text.L("menu.card.showWhole")).IsVisible) throw new IOException("Remote header compact control missing.");
                window.ContextMenu.Items.OfType<MenuItem>().Single(item => item.Header.ToString() == Text.L("menu.card.showWhole")).RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); window.UpdateLayout();
                if (window.ActualHeight <= 78) throw new IOException("Remote context-menu expansion failed.");
                checks.Add(new { name = language + ".remote." + kind + ".compact.controls", visibleHeaderToggle = true, contextExpansion = true });
                var labels = Descendants<TextBlock>(window).Select(label => label.Text).ToArray();
                if (kind is "pullRequests" or "mergeRequests" && (!labels.Contains("CF") || !labels.Contains("RV") || !labels.Contains("IR-6258"))) throw new IOException("Remote status/ticket/review lost: " + language + "/"+kind);
                if (!labels.Contains(RemoteWords.Summary(snapshot))) throw new IOException("Remote summary lost: " + language + "/"+kind);
                if (kind != "actions" && Buttons(window).Single(button => AutomationProperties.GetName(button) == snapshot.Rows[2].Title).IsEnabled) throw new IOException("Unaddressable row opens a browser.");
                if (kind == "inbox" && !ContextMenuService.GetShowOnDisabled(Buttons(window).Single(button => AutomationProperties.GetName(button) == snapshot.Rows[2].Title))) throw new IOException("Unaddressable Inbox row loses mark-read context menu.");
                checks.Add(new { name = language+".remote."+kind+".metadata", summary = true, sharedStatus = true, safeLinks = true });
                window.SetExpanded(true); window.UpdateLayout();
                var rowButtons = Buttons(window).Count(button => snapshot.Rows.Any(row => AutomationProperties.GetName(button) == row.Title));
                if (rowButtons != (kind == "actions" ? 1 : 12) || window.ActualHeight > 850) throw new IOException("Remote expanded rows lost or exceed the screen: " + language + "/"+kind);
                checks.Add(new { name = language+".remote."+kind+".expanded", boundedRows = true });
                window.SetMutationPresentation(true); window.UpdateLayout();
                if (Buttons(window).Single(button => AutomationProperties.GetName(button) == Text.L("menu.card.collapse")).IsEnabled) throw new IOException("Compact control can hide mutation cancellation.");
                if (!Buttons(window).Single(button => AutomationProperties.GetName(button) == Text.L("button.cancel")).IsVisible || Buttons(window).Any(button => snapshot.Rows.Any(row => AutomationProperties.GetName(button) == row.Title) && button.IsEnabled)) throw new IOException("Inbox mutation leaves row actions enabled.");
                window.SetMutationPresentation(false);
                checks.Add(new { name = language+".remote."+kind+".busy", cancellable = true, rowsDisabled = true });
                window.ApplyFailure(new WorkerException("remoteUnavailable","Synthetic offline failure")); window.UpdateLayout();
                if (!Descendants<TextBlock>(window).Any(label => label.Text.Contains(Text.L("windows.previousResults"))) || Buttons(window).Count(button => snapshot.Rows.Any(row => AutomationProperties.GetName(button) == row.Title)) != rowButtons) throw new IOException("Refresh failure discards previous results.");
                checks.Add(new { name = language+".remote."+kind+".failure", previousRowsPreserved = true });
                var partial = snapshot with { Failures = [new(kind == "mergeRequests" ? "lab" : "second","rateLimited")],Capped = true };
                window.ApplySnapshot(partial); window.UpdateLayout();
                if (!Descendants<TextBlock>(window).Any(label => label.Text.Contains(Text.L("error.rateLimited"))) || kind == "inbox" && Buttons(window).Single(button => AutomationProperties.GetName(button) == Text.L("card.inbox.readAll.capped")).IsEnabled) throw new IOException("Partial failure or bounded Inbox guard lost.");
                checks.Add(new { name = language+".remote."+kind+".partial", accountFailureVisible = true, cappedVisible = true });
                window.SetCollapsed(true); window.UpdateLayout();
                if (window.ActualHeight > 78 || !Buttons(window).Single(button => AutomationProperties.GetName(button) == Text.L("card.action.openInBrowser")).IsVisible || !window.ContextMenu.Items.OfType<MenuItem>().Any(item => item.Header.ToString() == Text.L("menu.refresh"))) throw new IOException("Collapsed remote lost summary/dashboard/menu.");
                checks.Add(new { name = language+".remote."+kind+".collapsed", compact = true, dashboardReachable = true });
                window.SetCollapsed(false);
                Buttons(window).Single(button => AutomationProperties.GetName(button) == Text.L("windows.allItems")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                var list = application.Windows.OfType<Window>().Single(candidate => candidate != window && candidate.Title == window.Title);
                if ((WidgetWindow.ReadStyle(list) & 0x80) != 0 || Buttons(list).Count(button => snapshot.Rows.Any(row => AutomationProperties.GetName(button) == row.Title)) != 15) throw new IOException("Expanded remote list loses rows or ordinary window style.");
                Buttons(window).Single(button => AutomationProperties.GetName(button) == Text.L("windows.allItems")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                if (application.Windows.OfType<Window>().Count(candidate => candidate != window && candidate.Title == window.Title) != 1) throw new IOException("Duplicate full remote lists.");
                list.Close(); checks.Add(new { name = language+".remote."+kind+".fullList", allRows = true, singleton = true, ordinaryWindow = true });
                if (kind == "actions") {
                    window.ApplySnapshot(snapshot with { Rows = [],Total = 0,Blocked = 0,SuccessRate = null,RepositoryCount = 0,FollowsPullRequests = true,RunningCount = 0,AverageDurationSeconds = null,WatchedRepositories = [] }); window.UpdateLayout();
                    if (!Buttons(window).Any(button => AutomationProperties.GetName(button) == Text.L("card.actions.empty.choose"))) throw new IOException("Empty Actions has no configuration target.");
                    checks.Add(new { name = language+".remote.actions.empty", chooseRepositories = true });
                    window.ApplySnapshot(snapshot with { Rows = [],Total = 0,Blocked = 0,SuccessRate = null,RunningCount = 0,AverageDurationSeconds = null }); window.UpdateLayout();
                    if (!Descendants<TextBlock>(window).Any(label => label.Text.Contains(Text.L("card.actions.quiet.detail","shop, tools")))) throw new IOException("Quiet Actions loses watched repositories.");
                    checks.Add(new { name = language+".remote.actions.quiet", watchedRepositories = true });
                }
            }
            foreach (var window in new Window[] { new SettingsWindow(controller, live: false), new RemoteSettingsWindow(controller, live: false),
                new AccountWindow(controller, null, () => { }, live: false), new NotificationSettingsWindow(controller), new AttentionWindow(controller,
                    [new("safe", "safe", "needsFixing", "token", Text.L("attention.account.rejected.title", "GitHub", "Example account"),
                        Text.L("attention.account.rejected.subtitle", "HTTP 401"), null, new("none"), false, false)]) }) {
                using var sample = new WindowScope(window); window.Show(); window.UpdateLayout();
                var viewport = window is SettingsWindow settings ? settings.Page : (ScrollViewer)window.Content;
                if (window.ActualWidth <= 0 || window.ActualHeight > SystemParameters.WorkArea.Height || viewport.ViewportWidth <= 0)
                    throw new IOException("Translated settings or attention content cannot be reached: " + language);
                checks.Add(new { name = language + "." + window.GetType().Name, scrollable = true, synthetic = true });
            }
            using (var settings = new WindowScope(new SettingsWindow(controller, live: false))) {
                var window = (SettingsWindow)settings.Window; window.Show();
                foreach (var id in new[] { "deck", "cards", "notifications", "project:sample.project.0", "account:sample", "new-project", "new-account", "new-account:gitlab" }) {
                    await window.SelectPageAsync(id); foreach (var expander in Descendants<Expander>(window.Page)) expander.IsExpanded = true; window.UpdateLayout();
                    if (window.Page.ViewportWidth < 500 || window.Page.ViewportHeight < 250) throw new IOException("Settings page is not reachable: " + language + "/" + id);
                    if (id == "cards" && RemoteCardCatalog.All.Any(descriptor => !Descendants<CheckBox>(window.Page).Any(toggle => toggle.Tag as string == descriptor.Kind && toggle.IsChecked == false))) throw new IOException("Settings card catalog is missing: " + language);
                    if (id == "cards" && Descendants<CheckBox>(window.Page).Count(toggle => AutomationProperties.GetName(toggle) == Text.L("windows.compactCard")) != 5 || id == "project:sample.project.0" && !Descendants<CheckBox>(window.Page).Any(toggle => AutomationProperties.GetName(toggle) == Text.L("windows.compactCard"))) throw new IOException("Compact settings toggle missing.");
                    if (id == "new-account:gitlab" && !Descendants<ComboBox>(window.Page).Any(input => input.SelectedItem as string == "gitlab")) throw new IOException("Missing-account route selected the wrong provider.");
                    foreach (var input in Descendants<Control>(window.Page).Where(input => input.IsVisible && input.ActualWidth > 0)) {
                        var right = input.TransformToAncestor(window).Transform(new Point(input.ActualWidth, 0)).X;
                        if (right > window.ActualWidth + 1) throw new IOException("Settings field clipped: " + language + "/" + id);
                    }
                    checks.Add(new { name = language + ".settings." + id, contextual = true, fieldsReachable = true });
                }
                await window.SelectPageAsync("account:sample"); Descendants<PasswordBox>(window.Page).Single().Password = "synthetic-unsaved-draft";
                await window.SelectPageAsync("account:lab"); if (Descendants<PasswordBox>(window.Page).Single().Password.Length != 0) throw new IOException("Token draft crossed accounts.");
                await window.SelectPageAsync("account:sample"); if (Descendants<PasswordBox>(window.Page).Single().Password != "synthetic-unsaved-draft") throw new IOException("Unsaved token draft lost on navigation.");
                using (var another = new WindowScope(new SettingsWindow(controller,live:false))) {
                    var second = (SettingsWindow)another.Window; await second.SelectPageAsync("account:sample");
                    if (Descendants<PasswordBox>(second.Page).Single().Password.Length != 0) throw new IOException("Token draft escaped its owning window.");
                }
                checks.Add(new { name = language+".settings.tokenDraft", navigationPreserved = true, accountAndWindowIsolation = true, noVaultWrite = true });
                var query = Descendants<TextBox>(window).First(input => AutomationProperties.GetName(input) == Text.L("settings.search"));
                query.Text = "example-3";
                var found = Descendants<ListBox>(window).Single().Items.Cast<ListBoxItem>().Where(item => item.IsEnabled).ToArray();
                if (found.Length != 1 || !found[0].ToolTip.ToString()!.Contains("example-3")) throw new IOException("Settings search did not filter by project folder.");
                checks.Add(new { name = language + ".settings.search", folderSearch = true });
            }
            using (var sample = new WindowScope(new LogWindow(controller, controller.Settings.Cards[0].Project, live: false))) {
                var window = (LogWindow)sample.Window; window.Show(); window.Activate();
                window.Apply(new(Enumerable.Range(0, 400).Select(index => "fixture " + index).ToArray(), "Synthetic source", null, "/tmp/fixture.log")); window.UpdateLayout();
                window.Search("fixture 370"); if (window.Selection != "fixture 370" || window.IsFollowing) throw new IOException("Log search/follow failed.");
                window.Apply(new(["replacement", "fixture 370"], "Synthetic source", null));
                if (window.IsFollowing) throw new IOException("Log refresh re-enabled Follow after search.");
                window.WindowState = WindowState.Minimized; if (WindowVisibility.CanRead(window)) throw new IOException("Minimized log would still poll.");
                window.WindowState = WindowState.Normal; window.Hide(); if (WindowVisibility.CanRead(window)) throw new IOException("Hidden log would still poll.");
                checks.Add(new { name = language + ".logs", search = true, preservesFollow = true, skipsHiddenAndMinimized = true });
            }
        }
        foreach (var language in DevDeck.Windows.Core.Localization.Languages) {
            NativeCheckProgress.Current?.Mark("legacy.translated." + language);
            Text.Use(language);
            using var scope = new WindowScope(new ProjectCard(controller,controller.Settings.Cards[0],live:false));
            var project = (ProjectCard)scope.Window; project.Show();
            foreach (var state in new[] { "running","stopped","paused","unknown","syncWarning","healthWarning" }) {
                var snapshot = new ProjectStatus(project.Reference.Id,state.EndsWith("Warning",StringComparison.Ordinal) ? "running" : state,
                    "feature/metadata",null,"drupal 11.4.4",null,NotAnswering:state == "healthWarning" ? "HTTP 503" : null,
                    SyncBroken:state == "syncWarning" ? "mutagen" : null,VersionsLine:"php 8.4 · mysql 8.0");
                project.ApplySnapshot(snapshot); project.UpdateLayout();
                var version = Descendants<TextBlock>(project).Single(block => block.Text == snapshot.VersionsLine);
                if (!version.IsVisible || version.ActualWidth < 100 || version.ToolTip?.ToString() != snapshot.VersionsLine)
                    throw new IOException("DDEV versions missing or clipped: " + language + "/" + state);
                var leading = Descendants<TextBlock>(project).Single(block => block.Text == (snapshot.SyncBroken is not null ? Text.L("attention.project.sync.subtitle","mutagen") : snapshot.NotAnswering ?? snapshot.Framework+" · "+project.Reference.Path.TrimEnd('/').Split('/').Last()));
                var versionOrigin = version.TransformToAncestor(project).Transform(new Point());
                var leadingOrigin = leading.TransformToAncestor(project).Transform(new Point());
                if (leadingOrigin.X + leading.ActualWidth > versionOrigin.X - 11 || Math.Abs(versionOrigin.Y - leadingOrigin.Y) > 1)
                    throw new IOException("DDEV version/framework metadata overlap.");
                var height = project.ActualHeight;
                project.SetCollapsed(true); project.UpdateLayout();
                if (version.IsVisible || project.ActualHeight > 76) throw new IOException("DDEV version row breaks compact layout.");
                project.SetCollapsed(false); project.UpdateLayout();
                if (!version.IsVisible || Math.Abs(height-project.ActualHeight) > 1) throw new IOException("Expanding loses DDEV versions.");
                checks.Add(new { name = language+".ddev.metadata."+state, realDTOField = true, separateVersionRow = true, warningsRetainVersions = true, compactRoundTrip = true });
            }
            project.ApplySnapshot(new(project.Reference.Id,"unknown",null,null,null,null)); project.UpdateLayout();
            if (Descendants<TextBlock>(project).Any(block => block.IsVisible && block.Text == "php 8.4 · mysql 8.0")) throw new IOException("Absent metadata retained invented versions.");
            checks.Add(new { name = language+".ddev.metadata.absent", noFabricatedVersions = true });
        }
        Text.Use("en");
        foreach (var hidden in new string[]?[] { null,[],["xhgui"],["Mailpit"] }) {
            using var form = new ProjectSettingsForm(controller,hidden is null ? null : controller.Settings.Cards[0] with { HiddenTools = hidden },live:false,_ => { });
            foreach (var tool in CardSettings.Tools("ddev")) {
                var toggle = Descendants<CheckBox>(form).Single(input => AutomationProperties.GetName(input) == tool);
                if (toggle.IsChecked != (hidden is null ? tool != "xhgui" : !hidden.Contains(tool))) throw new IOException("DDEV tool default or saved preference lost.");
            }
            checks.Add(new { name = "ddev.tools.settings."+(hidden is null ? "new" : string.Join("-",hidden)), newXhguiOff = true, savedVisibilityPreserved = true });
        }
        using (var scope = new WindowScope(new ProjectCard(controller,controller.Settings.Cards[0] with { HiddenTools = ["Mailpit"], Links = [new("TEST","https://example.com/test"),new("UAT","https://example.com/uat",false)] },live:false))) {
            var project = (ProjectCard)scope.Window; project.Show(); project.ApplySnapshot(new(project.Reference.Id,"running","main","http://localhost:8080","drupal 11",null,ToolLinks:[new("Mailpit","http://localhost:8025"),new("xhgui","http://localhost:8143")])); project.UpdateLayout();
            var names = Buttons(project).Select(AutomationProperties.GetName).ToArray();
            if (names.Contains("Mailpit") || names.Contains("UAT") || !names.Contains("TEST") || !names.Contains("xhgui")) throw new IOException("Card did not respect configured tool/link visibility.");
            checks.Add(new { name = "project.links.visibility", hiddenToolsAndDisabledEnvironmentsFiltered = true });
            project.ApplySnapshot(project.Latest! with { State = "stopped" }); project.UpdateLayout();
            if (Buttons(project).Any(button => button.IsVisible && AutomationProperties.GetName(button) == "xhgui")) throw new IOException("Stopped local xhgui remained available.");
            checks.Add(new { name = "ddev.tools.stopped", localToolsRequireRunning = true });
        }
        using (var scope = new WindowScope(new LogWindow(controller, controller.Settings.Cards[0].Project with { Kind = "arc" }, live: false))) {
            var log = (LogWindow)scope.Window;
            log.Show(); log.UpdateLayout();
            var terminal = Buttons(log).Single(button => AutomationProperties.GetName(button) == Text.L("windows.logTerminal"));
            log.Apply(new([], "docker logs", "Synthetic stopped stack")); if (terminal.IsEnabled) throw new IOException("Fusion terminal has no resolved container.");
            log.Apply(new(["fixture"], "docker logs fusion-engine", null)); if (!terminal.IsEnabled) throw new IOException("Fusion resolved log terminal is disabled.");
            checks.Add(new { name = "logs.fusion.target", usesResolvedEngine = true, requiresExistingContainer = true });
        }
        var settingsPath = Path.Combine(Path.GetTempPath(), "devdeck-parity-form-" + Guid.NewGuid().ToString("N") + ".json");
        var editable = SampleDeck.Controller(application, settingsPath);
        try {
            var original = editable.Settings.Cards[0];
            using var view = new WindowScope(new Window { Content = new ProjectSettingsForm(editable, original, live: true, _ => { }), Width = 740, Height = 680 });
            var form = (ProjectSettingsForm)view.Window.Content;
            var name = Descendants<TextBox>(form).First(input => AutomationProperties.GetName(input) == Text.L("account.name"));
            name.Text = "Renamed synthetic project"; await form.FlushAsync();
            var saved = new SettingsStore(settingsPath).Load().Cards[0];
            if (saved.Title != name.Text || saved.Project.Id != original.Project.Id || saved.X != original.X || saved.Y != original.Y || saved.Enabled != original.Enabled)
                throw new IOException("Project autosave lost identity/placement/visibility.");
            var mailpit = Descendants<CheckBox>(form).Single(input => AutomationProperties.GetName(input) == "Mailpit");
            mailpit.IsChecked = false; mailpit.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
            var url = Descendants<TextBox>(form).Single(input => AutomationProperties.GetName(input) == "TEST"); url.Text = "https://example.com/staging";
            var environment = Descendants<CheckBox>(form).Single(input => AutomationProperties.GetName(input) == "TEST"); environment.IsChecked = true; environment.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
            await form.FlushAsync(); saved = new SettingsStore(settingsPath).Load().Cards[0];
            if (!saved.HiddenToolList.Contains("Mailpit") || saved.LinkList.Single(link => link.Label == "TEST") is not { Enabled: true, Url: "https://example.com/staging" }) throw new IOException("Tool/link switches did not autosave.");
            environment.IsChecked = false; environment.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); await form.FlushAsync();
            if (new SettingsStore(settingsPath).Load().Cards[0].LinkList.Single(link => link.Label == "TEST") is not { Enabled: false, Url: "https://example.com/staging" }) throw new IOException("Disabling a link lost its address.");
            var compactSetting = Descendants<CheckBox>(form).Single(input => AutomationProperties.GetName(input) == Text.L("windows.compactCard"));
            compactSetting.IsChecked = true; compactSetting.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); await form.FlushAsync();
            var compactWindow = editable.LocalViews.Single(card => card.Reference.Id == original.Project.Id);
            compactWindow.UpdateLayout();
            if (!new SettingsStore(settingsPath).Load().Cards.Single(card => card.Project.Id == original.Project.Id).Collapsed || compactWindow.ActualHeight > 76) throw new IOException("Project compact setting failed to persist/update the live window: " + compactWindow.Reference.Id + "/" + compactWindow.ActualHeight);
            checks.Add(new { name = "settings.compact", persisted = true, liveWindowUpdated = true });
            checks.Add(new { name = "settings.project.switches", toolAndEnvironmentAutosave = true, disabledURLPreserved = true });
            form.Dispose();
            using var accountView = new WindowScope(new Window { Content = new AccountSettingsForm(editable, editable.Settings.AccountList[0], live: true, _ => { }), Width = 740, Height = 680 });
            var accountForm = (AccountSettingsForm)accountView.Window.Content;
            var accountName = Descendants<TextBox>(accountForm).First(input => AutomationProperties.GetName(input) == Text.L("account.name"));
            accountName.Text = "Renamed synthetic account"; await accountForm.FlushAsync();
            var account = new SettingsStore(settingsPath).Load().AccountList[0];
            if (account.Id != "sample" || account.Label != accountName.Text || Descendants<PasswordBox>(accountForm).Single().Password.Length != 0)
                throw new IOException("Account metadata autosave touched token input or identity.");
            accountForm.Dispose();
            var first = editable.ShowLogs(saved.Project); var second = editable.ShowLogs(saved.Project);
            if (!ReferenceEquals(first, second)) throw new IOException("Duplicate log windows."); first.Close();
            var reopened = editable.ShowLogs(saved.Project);
            if (ReferenceEquals(first, reopened)) throw new IOException("Closed log window was reused.");
            reopened.Apply(new(["fixture"], "Synthetic source", null, "/tmp/fixture.log"));
            reopened.UpdateProject(saved.Project with { Path = "/home/user/changed-fixture" });
            if (reopened.Latest is not null) throw new IOException("Changed project retained a stale full-file target.");
            reopened.UpdateProject(saved.Project);
            var retainedLogs = new WorkerLogs(["retained fixture"], "Synthetic source", null, "/tmp/fixture.log");
            reopened.Apply(retainedLogs);
            var logHandle = new WindowInteropHelper(reopened).Handle;
            var logClosed = false; reopened.Closed += (_, _) => logClosed = true;
            await editable.SetCardVisibleAsync(saved.Project.Id, false);
            if (!reopened.IsVisible || logClosed || new WindowInteropHelper(reopened).Handle != logHandle || !ReferenceEquals(reopened.Latest, retainedLogs)) throw new IOException("Hiding a widget closed/replaced its explicitly opened log window or discarded its contents.");
            await editable.ToggleLogsAsync(saved.Project);
            if (reopened.IsVisible || !logClosed) throw new IOException("Explicitly hiding logs failed to dispose their own window.");
            checks.Add(new { name = "settings.metadata.autosave", projectAndAccount = true, preservesIdentityAndPlacement = true, noWorkerOrCredentialAccess = true });
            checks.Add(new { name = "logs.singleton", duplicatePrevented = true, reopenAfterClose = true });
            checks.Add(new { name = "logs.settings.lifecycle", widgetHideRetainsExplicitLogWindowAndContents = true, explicitLogHideClosesWindow = true, changedProjectClearsFileTarget = true });
            editable.ShowSettings(); var previousSettingsWindow = editable.SettingsView!;
            await editable.SaveSettingsAsync(current => current with { Language = "ru" });
            if (previousSettingsWindow.IsVisible || editable.SettingsView is null || ReferenceEquals(previousSettingsWindow, editable.SettingsView) || !editable.SettingsView.IsVisible)
                throw new IOException("Language change failed to reopen translated settings.");
            await editable.SettingsView.CloseSettingsAsync(); Text.Use("en");
            checks.Add(new { name = "settings.language.reopen", savesAndReopens = true, noWorkersOrCredentials = true });
        } finally {
            editable.CloseViews();
            foreach (var path in new[] { settingsPath, settingsPath + ".bak" }) if (File.Exists(path)) File.Delete(path);
        }
        var discoveryPath = Path.Combine(Path.GetTempPath(), "devdeck-card-discovery-" + Guid.NewGuid().ToString("N") + ".json");
        DeckController? discovered = null;
        try {
            var fixtureStore = new SettingsStore(discoveryPath);
            fixtureStore.Save(new DeckSettings(1, [new("Ubuntu-24.04","/home/user/runtime")], [], Accounts: [
                new("a","Example work","github","https://api.github.com",[],[]),new("b","Example personal","github","https://api.github.com",[],[])]));
            discovered = new DeckController(application,fixtureStore,live:false);
            if (discovered.Settings.RemoteCardList.Length != 3 || discovered.Settings.RemoteCardList.Count(card => card.Enabled) != 2) throw new IOException("Existing account-only settings did not acquire default cards.");
            await discovered.SaveSettingsAsync(current => current);
            if (discovered.RemoteViews.Length != 2 || discovered.RemoteViews.Any(window => !WidgetWindow.IsExcluded(window))) throw new IOException("Discovered widgets missing or in Alt+Tab.");
            var original = RemoteCardCatalog.Resolve(discovered.Settings,"pullRequests")!;
            var previousWindows = discovered.RemoteViews;
            await discovered.SetRemoteVisibleAsync("pullRequests",false);
            if (discovered.RemoteViews.Length != 1 || previousWindows.Single(window=>window.CardID==original.Id).IsVisible
                || !previousWindows.Single(window=>window.CardID!=original.Id).IsVisible
                || !ReferenceEquals(discovered.RemoteViews.Single(),previousWindows.Single(window=>window.CardID!=original.Id)))
                throw new IOException("Visibility either retains the selected polling widget or replaces/hides its unrelated sibling.");
            var restarted = new DeckController(application,fixtureStore,live:false);
            if (RemoteCardCatalog.Resolve(restarted.Settings,"pullRequests")!.Enabled) throw new IOException("Restart enabled a hidden widget.");
            await discovered.SetRemoteVisibleAsync("pullRequests",true);
            var restored = RemoteCardCatalog.Resolve(discovered.Settings,"pullRequests")!;
            if (restored.Id != original.Id || restored.X != original.X || restored.Y != original.Y || discovered.RemoteViews.Length != 2) throw new IOException("Visibility toggle lost identity/placement or duplicated widgets.");
            checks.Add(new { name = "cardDiscovery.bootstrap", twoAccountsMerged = true, defaultWidgets = 2, noWorkerOrCredentialAccess = true });
            checks.Add(new { name = "cardDiscovery.visibility", hiddenWindowRetainedWithoutPolling = true, unrelatedWindowRetained = true, restartPreserved = true, identitiesAndPlacementPreserved = true, excludedFromSwitcher = true });
            await discovered.SaveSettingsAsync(current => current with { Accounts = current.AccountList.Select(account => account with { Enabled = false }).ToArray() });
            if (discovered.RemoteViews.Length != 0) throw new IOException("Disabled accounts retained polling widgets.");
            await discovered.SaveSettingsAsync(current => current with { Accounts = current.AccountList.Select(account => account with { Enabled = true }).ToArray() });
            if (discovered.RemoteViews.Length != 2 || RemoteCardCatalog.Resolve(discovered.Settings,"pullRequests")!.Id != original.Id) throw new IOException("Account reactivation recreated or lost widgets.");
            checks.Add(new { name = "cardDiscovery.accountActivation", inactiveScopesStopPolling = true, savedVisibilityPreserved = true });
        } finally { discovered?.CloseViews(); foreach (var path in new[] { discoveryPath, discoveryPath + ".bak" }) if (File.Exists(path)) File.Delete(path); }
        var layoutPath = Path.Combine(Path.GetTempPath(), "devdeck-measured-layout-" + Guid.NewGuid().ToString("N") + ".json");
        var arranged = SampleDeck.Controller(application,layoutPath);
        try {
            await arranged.SaveSettingsAsync(current => current with {
                Cards = current.Cards.Select((card,index) => index == 6 ? card with { Enabled = false, X = 3500, Y = 3500 } : card with { Collapsed = index % 2 == 0 }).ToArray(),
                RemoteCards = current.RemoteCardList.Select(card => card with { Enabled = card.Kind is "pullRequests" or "inbox" }).ToArray()
            });
            foreach (var card in arranged.LocalViews) card.ApplySnapshot(new(card.Reference.Id,"stopped","feature/columns",null,"drupal 11",null));
            foreach (var card in arranged.RemoteViews) card.ApplySnapshot(SampleDeck.Remote(card.Latest?.Kind ?? arranged.Settings.RemoteCardList.Single(item => item.Id == card.CardID).Kind));
            var beforeViews = arranged.RemoteViews.Cast<Window>().Concat(arranged.LocalViews).ToArray();
            foreach (var window in beforeViews) window.UpdateLayout();
            var snapshots = arranged.RemoteViews.Select(card => card.Latest).ToArray();
            var hidden = arranged.Settings.Cards[6]; var originalOrder = arranged.Settings.Cards.Select(card => card.Project.Id).ToArray();
            var anchor = beforeViews.MinBy(window => window.Top)!; var anchorX = anchor.Left; var anchorY = anchor.Top;
            await arranged.ArrangeAsync(new Rect(0,0,1700,900));
            var afterViews = arranged.RemoteViews.Cast<Window>().Concat(arranged.LocalViews).ToArray();
            if (!beforeViews.SequenceEqual(afterViews) || !snapshots.SequenceEqual(arranged.RemoteViews.Select(card => card.Latest))) throw new IOException("Tidying rebuilt windows or lost snapshots.");
            var columns = afterViews.GroupBy(window => window.Left).ToArray();
            if (columns.Length < 2 || afterViews[0].Left != anchorX || afterViews[0].Top != anchorY) throw new IOException("Measured tidy lost anchor or wrapping.");
            foreach (var column in columns) {
                var stack = column.OrderBy(window=>window.Top).ToArray();
                for (var index = 1; index < stack.Length; index++) {
                    var previous = ReadBounds(stack[index-1]); var current = ReadBounds(stack[index]);
                    var expectedGap = 12 * VisualTreeHelper.GetDpi(stack[index]).DpiScaleY;
                    if (Math.Abs(current.Top - previous.Bottom - expectedGap) > 1) throw new IOException("Native column gap differs from twelve DIPs after pixel rounding.");
                }
                if (stack.Any(window => ReadBounds(window).Bottom / VisualTreeHelper.GetDpi(window).DpiScaleY > 900.1)) throw new IOException("Tidy did not wrap at the work-area edge.");
            }
            var loaded = new SettingsStore(layoutPath).Load();
            if (loaded.Cards[6] != hidden || !loaded.Cards.Select(card => card.Project.Id).SequenceEqual(originalOrder)) throw new IOException("Tidy moved hidden cards or reordered configuration.");
            foreach (var card in arranged.LocalViews) { var saved = loaded.Cards.Single(item => item.Project.Id == card.Reference.Id); if (saved.X != card.Left || saved.Y != card.Top) throw new IOException("Local tidy placement was not persisted."); }
            foreach (var card in arranged.RemoteViews) { var saved = loaded.RemoteCardList.Single(item => item.Id == card.CardID); if (saved.X != card.Left || saved.Y != card.Top) throw new IOException("Remote tidy placement was not persisted."); }
            checks.Add(new { name = "columns.measured", actualMixedHeights = true, gap = 12, nativePixelsChecked = true, pixelRoundingTolerance = 1, wrapsAtWorkArea = true, anchorPreserved = true });
            checks.Add(new { name = "columns.persistence", hiddenPlacementAndOrderPreserved = true, noWindowOrSnapshotRebuild = true });
        } finally { arranged.CloseViews(); foreach (var path in new[] { layoutPath,layoutPath+".bak" }) if (File.Exists(path)) File.Delete(path); }
        checkProgress.Mark("legacy.cleanup");
        controller.CloseViews(); foreach (var path in new[] { sampleSettingsPath,sampleSettingsPath+".bak" }) if (File.Exists(path)) File.Delete(path);
        checkProgress.Mark("finalReport");
        await File.WriteAllTextAsync(report, JsonSerializer.Serialize(new { nativeWindows = true, passed = checks.Count, failed = 0, checks, releaseQualified = false }, new JsonSerializerOptions { WriteIndented = true }));
        checkProgress.Complete();
    }
    private static async Task CheckSettingsNavigationAsync(Application application, DeckController controller, List<object> checks)
    {
        foreach (var language in DevDeck.Windows.Core.Localization.Languages) {
            NativeCheckProgress.Current?.Mark("legacy.translated." + language);
            Text.Use(language);
            var requested = new List<SettingsRemovalRequest>();
            using (var scope = new WindowScope(new SettingsWindow(controller, live:false, request => { requested.Add(request); return false; }))) {
                var window = (SettingsWindow)scope.Window; window.Show(); window.Activate(); window.UpdateLayout();
                await window.SelectPageAsync("account:sample");
                var password = Descendants<PasswordBox>(window.Page).Single(); password.Password = "synthetic-settings-draft"; password.Focus();
                window.Search.Text = "work";
                if (!await window.HandleSettingsKeyAsync(Key.F, ModifierKeys.Control, sidebarFocused:false) || !window.Search.IsKeyboardFocused || window.Search.SelectedText != "work" || password.Password != "synthetic-settings-draft") throw new IOException("Ctrl+F does not focus/select settings search from the token field.");
                checks.Add(new { name=language+".settings.keyboard.search", fromToken=true, searchFocused=true, querySelected=true, draftPreserved=true });
                window.Search.Text = ""; await window.SelectPageAsync("notifications");
                window.Navigation.Focus();
                if (!await window.HandleSettingsKeyAsync(Key.Down, ModifierKeys.None, sidebarFocused:true) || window.SelectedPage != "account:lab" || !window.Navigation.IsKeyboardFocusWithin) throw new IOException("Sidebar Down fails to skip headings or retain focus after rebuilding. selected="+window.SelectedPage+"; focusWithin="+window.Navigation.IsKeyboardFocusWithin+"; selectedItem="+(window.Navigation.SelectedItem as ListBoxItem)?.Tag+"; focused="+Keyboard.FocusedElement?.GetType().Name);
                await window.HandleSettingsKeyAsync(Key.Up, ModifierKeys.None, sidebarFocused:true);
                if (window.SelectedPage != "notifications") throw new IOException("Sidebar Up fails to skip account heading.");
                await window.SelectPageAsync("general"); await window.HandleSettingsKeyAsync(Key.Up, ModifierKeys.None, sidebarFocused:true);
                if (window.SelectedPage != "general") throw new IOException("Sidebar Up wraps beyond its first item.");
                await window.SelectPageAsync("project:sample.project.0"); await window.HandleSettingsKeyAsync(Key.Down, ModifierKeys.None, sidebarFocused:true);
                if (window.SelectedPage != "project:sample.project.0") throw new IOException("Sidebar Down wraps beyond its last item.");
                checks.Add(new { name=language+".settings.keyboard.arrows", headingsSkipped=true, focusRetained=true, firstLastClamped=true, naturalFirstAccount=true, naturalLastProject=true });
                window.Search.Text = "  EXAMPLE-3  "; await window.SelectPageAsync("general");
                await window.HandleSettingsKeyAsync(Key.Down, ModifierKeys.None, sidebarFocused:true);
                var visible = window.Navigation.Items.OfType<ListBoxItem>().ToArray();
                if (window.SelectedPage != "project:sample.project.3" || visible.Count(item => item.IsEnabled) != 1 || visible.Count(item => !item.IsEnabled) != 1) throw new IOException("Filtered keyboard navigation includes a hidden item or an empty heading.");
                window.Search.Text = "unmatched-synthetic-query";
                if (window.Navigation.Items.Count != 0) throw new IOException("A search with no matches retains empty section headings.");
                await window.HandleSettingsKeyAsync(Key.Down, ModifierKeys.None, sidebarFocused:true);
                if (window.SelectedPage != "project:sample.project.3") throw new IOException("Empty search unexpectedly changes selection.");
                checks.Add(new { name=language+".settings.keyboard.filtered", detailQueryCaseAndWhitespace=true, onlyVisibleItems=true, emptyGroupsHidden=true, emptyResultSafe=true });
                window.Search.Text = ""; await window.SelectPageAsync("account:sample");
                window.UpdateLayout();
                password = Descendants<PasswordBox>(window.Page).Single(); password.Focus();
                var accountName = Descendants<TextBox>(window.Page).First(input => AutomationProperties.GetName(input) == Text.L("account.name"));
                foreach (var input in new Control[] { accountName, password, window.Search }) {
                    input.Focus();
                    var before = window.SelectedPage;
                    foreach (var key in new[] { Key.Up, Key.Down, Key.Delete, Key.Back }) {
                        if (await window.HandleSettingsKeyAsync(key, ModifierKeys.None, sidebarFocused:false) || window.SelectedPage != before || requested.Count != 0) throw new IOException("A field cursor key navigates/removes the selected settings item.");
                    }
                }
                if (Descendants<PasswordBox>(window.Page).Single().Password != "synthetic-settings-draft") throw new IOException("Field cursor routing lost the token draft.");
                checks.Add(new { name=language+".settings.keyboard.fieldIsolation", textPasswordSearchProtected=true, arrowsDeleteBackUnclaimed=true, draftRetained=true });
                window.Navigation.Focus();
                await window.HandleSettingsKeyAsync(Key.Delete, ModifierKeys.None, sidebarFocused:true);
                if (requested.Count != 1 || requested[0].Title != Text.L("settings.remove.account.title", "Example work account") || requested[0].Detail != Text.L("windows.removeAccountDetail") || window.SelectedPage != "account:sample" || Descendants<PasswordBox>(window.Page).Single().Password != "synthetic-settings-draft") throw new IOException("Sidebar Delete skips scoped confirmation or loses the canceled account draft.");
                await window.RemoveSelectedAsync();
                Buttons(window.Page).Single(button => AutomationProperties.GetName(button) == Text.L("windows.removeSelected")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                if (requested.Count != 3 || requested.Any(request => request != requested[0])) throw new IOException("Account form/sidebar remove actions do not share their confirmation.");
                checks.Add(new { name=language+".settings.removal.accountRoutes", deleteSidebarAndFormSamePrompt=true, cancellationKeepsSelectionAndDraft=true, noVaultAccess=true });
                await window.SelectPageAsync("project:sample.project.0");
                window.UpdateLayout();
                await window.HandleSettingsKeyAsync(Key.Back, ModifierKeys.None, sidebarFocused:true);
                await window.RemoveSelectedAsync();
                Buttons(window.Page).Single(button => AutomationProperties.GetName(button) == Text.L("windows.removeCard")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                if (requested.Count != 6 || requested.Skip(3).Any(request => request.Title != Text.L("settings.remove.account.title", "Example shop") || request.Detail != Text.L("settings.remove.project.detail.ddev")) || window.SelectedPage != "project:sample.project.0") throw new IOException("Project remove routes do not share scoped confirmation or cancel changes selection.");
                await window.SelectPageAsync("general"); await window.HandleSettingsKeyAsync(Key.Delete, ModifierKeys.None, sidebarFocused:true);
                var sidebarRemove = Buttons(window).Single(button => AutomationProperties.GetName(button) == Text.L("settings.sidebar.remove"));
                if (requested.Count != 6 || sidebarRemove.IsEnabled) throw new IOException("A fixed settings page can be removed.");
                await window.SelectPageAsync("new-project"); await window.RemoveSelectedAsync();
                if (requested.Count != 6 || sidebarRemove.IsEnabled) throw new IOException("An unsaved project can be removed through the sidebar.");
                checks.Add(new { name=language+".settings.removal.projectRoutes", backSidebarAndFormSamePrompt=true, cancellationRetainsCard=true, fixedAndUnsavedPagesProtected=true });
            }
            foreach (var kind in new[] { "account", "arc", "ddev", "local" }) {
                var card = controller.Settings.Cards[0] with { Project=controller.Settings.Cards[0].Project with { Kind=kind == "account" ? "ddev" : kind } };
                SettingsRemovalRequest? request = null;
                var owner = new Border();
                if (kind == "account") SettingsConfirmation.ForAccount(owner, controller.Settings.AccountList[0], value => { request=value; return false; });
                else SettingsConfirmation.ForProject(owner, card, value => { request=value; return false; });
                var expectedDetail = Text.L(kind == "account" ? "windows.removeAccountDetail" : "settings.remove.project.detail."+kind);
                if (request is null || request.Detail != expectedDetail) throw new IOException("Removal confirmation uses the wrong project/account detail.");
                using var dialog = new WindowScope(SettingsConfirmation.CreateDialog(request));
                var cancel = Descendants<Button>(dialog.Window).Single(button => AutomationProperties.GetName(button) == Text.L("button.cancel"));
                var remove = Descendants<Button>(dialog.Window).Single(button => AutomationProperties.GetName(button) == Text.L("button.remove"));
                if (!cancel.IsDefault || !cancel.IsCancel || remove.IsDefault || remove.IsCancel || dialog.Window.ShowInTaskbar || dialog.Window.ResizeMode != ResizeMode.NoResize || !Descendants<TextBlock>(dialog.Window).Any(label => label.Text == expectedDetail)) throw new IOException("Removal dialog defaults Return/Escape to destructive action or loses its explanation.");
                checks.Add(new { name=language+".settings.removal.dialog."+kind, kindDetailRetained=true, returnAndEscapeCancel=true, explicitDestructiveClick=true });
            }
            var verificationCalls = 0; var pending = new TaskCompletionSource();
            using (var form = new AccountSettingsForm(controller, controller.Settings.AccountList[0], live:false, _ => { }, verifyToken: () => { verificationCalls++; return verificationCalls == 1 ? pending.Task : Task.CompletedTask; })) {
                using var scope = new WindowScope(new Window { Content=form, Width=900, Height=850 }); scope.Window.Show(); scope.Window.UpdateLayout();
                var token = Descendants<PasswordBox>(form).Single(); token.Password = "synthetic-return-draft";
                KeyEventArgs Enter() => new(Keyboard.PrimaryDevice, PresentationSource.FromVisual(scope.Window)!, Environment.TickCount, Key.Return) { RoutedEvent=Keyboard.KeyDownEvent };
                var first = Enter(); token.RaiseEvent(first); token.RaiseEvent(Enter());
                if (!first.Handled || verificationCalls != 1 || form.IsEnabled) throw new IOException("Token Return does not use the guarded verify/save path.");
                pending.SetResult(); await System.Windows.Threading.Dispatcher.Yield(System.Windows.Threading.DispatcherPriority.Background);
                Buttons(form).Single(button => AutomationProperties.GetName(button) == Text.L("windows.verifySaveToken")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                if (verificationCalls != 2 || token.Password != "synthetic-return-draft") throw new IOException("Token Return/button follow different verification paths or expose/clear a draft without persistence.");
                checks.Add(new { name=language+".settings.token.return", sameVerifyPathAsButton=true, duplicateSubmitGuarded=true, fakeVerifierOnly=true, noWorkerOrVaultAccess=true });
            }
        }
        Text.Use("en");
        var path = Path.Combine(Path.GetTempPath(), "devdeck-settings-removal-"+Guid.NewGuid().ToString("N")+".json");
        var editable = SampleDeck.Controller(application,path);
        try {
            var before = editable.Settings; var original = before.AccountList[0]; var cleared = new List<string>(); var changes = new List<string>(); var allow=false; var confirmations=0;
            using var form = new AccountSettingsForm(editable, original, live:true, changes.Add, confirmation:_ => { confirmations++; return allow; }, clearCredential:account => cleared.Add(account.Id));
            form.TokenDraft="synthetic-cancel-draft";
            await form.RemoveAsync();
            if (confirmations != 1 || cleared.Count != 0 || changes.Count != 0 || editable.Settings != before || form.TokenDraft != "synthetic-cancel-draft" || File.Exists(path)) throw new IOException("Cancel removes an account, writes metadata/credentials, or loses a token draft.");
            checks.Add(new { name="settings.removal.accountCancel", temporarySyntheticSettings=true, unchangedMetadata=true, draftRetained=true, noCredentialWrite=true });
            allow=true; await form.RemoveAsync();
            var saved = new SettingsStore(path).Load();
            if (confirmations != 2 || !cleared.SequenceEqual(new[] { original.Id }) || !changes.SequenceEqual(new[] { "" }) || saved.AccountList.Any(account => account.Id == original.Id) || JsonSerializer.Serialize(saved.AccountList) != JsonSerializer.Serialize(before.AccountList.Skip(1).ToArray()) || JsonSerializer.Serialize(saved.Cards) != JsonSerializer.Serialize(before.Cards) || saved.RemoteCardList.Any(card => card.AccountIDs.Contains(original.Id)) || form.TokenDraft.Length != 0) throw new IOException("Confirmed account removal touches unrelated settings or fails to clear only the account's credential/draft.");
            await form.FlushAsync(); await form.RemoveAsync();
            if (confirmations != 2 || cleared.Count != 1 || new SettingsStore(path).Load().AccountList.Any(account => account.Id == original.Id)) throw new IOException("A removed account can be recreated by autosave or cleared twice.");
            checks.Add(new { name="settings.removal.accountConfirmed", explicitConfirmation=true, onlySelectedIDRemoved=true, remainingCardsAccountsPreserved=true, remoteScopesPruned=true, fakeVaultOnly=true, noAutosaveResurrection=true });
        } finally {
            editable.CloseViews();
            foreach (var file in new[] { path,path+".bak" }) if (File.Exists(file)) File.Delete(file);
        }
    }
    [DllImport("user32.dll")] private static extern uint GetGuiResources(nint process, uint flags);
    [DllImport("user32.dll")] private static extern nint SendMessage(nint hwnd, int message, nint wparam, nint lparam);
    [StructLayout(LayoutKind.Sequential)] private struct NativeBounds { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint hwnd,out NativeBounds rectangle);
    private static NativeBounds ReadBounds(Window window)
    {
        if (!GetWindowRect(new WindowInteropHelper(window).Handle,out var rectangle)) throw new IOException("Synthetic native bounds unavailable.");
        return rectangle;
    }

    private static IEnumerable<Button> Buttons(DependencyObject root)
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is Button button) yield return button;
            foreach (var descendant in Buttons(child)) yield return descendant;
        }
    }
    private static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
    {
        foreach (var child in LogicalTreeHelper.GetChildren(root).OfType<DependencyObject>()) {
            if (child is T value) yield return value;
            foreach (var descendant in Descendants<T>(child)) yield return descendant;
        }
    }

    private sealed class WindowScope(Window window) : IDisposable
    {
        internal Window Window { get; } = window;
        public void Dispose() => Window.Close();
    }
}
