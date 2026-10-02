using System;
using System.IO;
using System.Linq;
using System.Windows;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal static class Program
{
    // Rendering scenes always use fixture facts; production windows retain startup metadata.
    internal static SettingsWindow CreateSampleSettingsWindow(DeckController controller) => new(controller, live:false,
        runningBuildInfoProvider:() => SettingsProvenanceSamples.Facts("native"));
    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Contains("--account-token-fake-worker")) return AccountTokenActionTests.RunFakeWorker(args);
        RunningBuildInfo.InitializeStartup();
        string Option(string key, string fallback) => Array.IndexOf(args, key) is var index && index >= 0 && index + 1 < args.Length ? args[index + 1] : fallback;
        var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var path = Option("--settings", Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DevDeck", "windows-settings.json"));
        using var instance = args.Contains("--settings-provenance-check") || args.Contains("--account-token-check") || args.Contains("--account-provider-check") || args.Contains("--settings-geometry-check") || args.Contains("--sidebar-check") || args.Contains("--tray-actions-check") || args.Contains("--integration-check") || args.Contains("--sample-render") || args.Contains("--tray-artwork") || args.Contains("--tray-attention-artwork") || args.Contains("--window-check") ? null : new SingleInstance(path);
        if (instance is { Acquired: false }) return 0;
        application.Startup += async (_, _) =>
        {
            try
            {
                if (args.Contains("--settings-provenance-check")) {
                    var checks = new System.Collections.Generic.List<object>();
                    var scenario = Option("--settings-provenance-case", "all");
                    if (scenario == "all") await SettingsProvenanceTests.RunAsync(application, checks);
                    else await SettingsProvenanceTests.RunRedAsync(application, checks, scenario);
                    File.WriteAllText(Option("--report", Path.Combine(Path.GetTempPath(), "devdeck-settings-provenance-checks.json")), System.Text.Json.JsonSerializer.Serialize(new { passed = checks.Count, failed = 0, componentOnly = true, releaseQualified = false, checks }));
                    application.Shutdown(); return;
                }
                if (args.Contains("--account-token-check")) {
                    var checks = new System.Collections.Generic.List<object>();
                    var scenario = Option("--account-token-case", "creation");
                    await AccountTokenActionTests.RunAsync(application, checks, scenario == "all" ? null : scenario);
                    File.WriteAllText(Option("--report", Path.Combine(Path.GetTempPath(), "devdeck-account-token-checks.json")), System.Text.Json.JsonSerializer.Serialize(new { passed = checks.Count, failed = 0, componentOnly = true, releaseQualified = false, checks }));
                    application.Shutdown(); return;
                }
                if (args.Contains("--account-provider-check")) {
                    var checks = new System.Collections.Generic.List<object>();
                    var scenario=Option("--account-provider-case","form");
                    await AccountProviderTests.RunAsync(application,checks,scenario=="all" ? null : scenario);
                    File.WriteAllText(Option("--report",Path.Combine(Path.GetTempPath(),"devdeck-account-provider-checks.json")),System.Text.Json.JsonSerializer.Serialize(new{passed=checks.Count,failed=0,componentOnly=true,releaseQualified=false,checks}));
                    application.Shutdown();return;
                }
                if (args.Contains("--settings-geometry-check")) {
                    var checks=new System.Collections.Generic.List<object>();
                    var geometryCase=Option("--settings-geometry-case","red");
                    if(geometryCase=="red")await SettingsGeometryTests.RunRedAsync(application,checks);
                    else if(geometryCase=="footer-red")await SettingsGeometryTests.RunFooterRedAsync(application,checks);
                    else if(geometryCase=="closing-red")await SettingsGeometryTests.RunClosingRedAsync(application,checks);
                    else if(geometryCase=="failure")await SettingsGeometryTests.RunFailureAsync(application,checks);
                    else if(geometryCase=="all")await SettingsGeometryTests.RunAsync(application,checks);
                    else throw new ArgumentException("Unknown geometry component case.");
                    File.WriteAllText(Option("--report",Path.Combine(Path.GetTempPath(),"devdeck-settings-geometry-checks.json")),System.Text.Json.JsonSerializer.Serialize(new{passed=checks.Count,failed=0,componentOnly=true,releaseQualified=false,checks}));
                    application.Shutdown();return;
                }
                if (args.Contains("--sidebar-check")) {
                    var checks = new System.Collections.Generic.List<object>();
                    var sidebarCase = Option("--sidebar-case", "all");
                    if (sidebarCase == "baseline") await SettingsSidebarTests.RunRedAsync(application,checks);
                    else if (sidebarCase == "legacy-navigation") await WindowChecks.RunSettingsNavigationAsync(application,checks);
                    else {
                        if (sidebarCase != "publication") await SettingsSidebarTests.RunAsync(application,checks);
                        if (sidebarCase != "views") await SettingsSidebarPublicationTests.RunAsync(application,checks);
                    }
                    File.WriteAllText(Option("--report",Path.Combine(Path.GetTempPath(),"devdeck-sidebar-checks.json")),System.Text.Json.JsonSerializer.Serialize(new {passed=checks.Count,failed=0,componentOnly=true,releaseQualified=false,checks}));
                    application.Shutdown(); return;
                }
                if (args.Contains("--tray-actions-check")) {
                    var checks = new System.Collections.Generic.List<object>();
                    if (Option("--tray-actions-case","showCard")=="fullList") await TrayAttentionActionsTests.RunRedAsync(application,checks);
                    else if (Option("--tray-actions-case","showCard")=="views") {await AttentionActivationTests.ShowCardAsync(application,checks);await TrayAttentionActionsChecks.RunAsync(application,checks);await TrayAttentionModifierTests.RunAsync(application,checks);await TrayAttentionMenuRebuildTests.RunAsync(application,checks);await AttentionReadLifetimeTests.RunAsync(application,checks);await AttentionPrimaryDispatchTests.RunAsync(application,checks);await AttentionDismissAdmissionTests.RunAsync(application,checks);}
                    else if (Option("--tray-actions-case","showCard")=="visibleRebuild") await TrayAttentionMenuRebuildTests.RunAsync(application,checks);
                    else if (Option("--tray-actions-case","showCard")=="dismiss-red") await AttentionDismissAdmissionTests.RunRedAsync(application,checks);
                    else if (Option("--tray-actions-case","showCard")=="dismiss") await AttentionDismissAdmissionTests.RunAsync(application,checks);
                    else if (Option("--tray-actions-case","showCard")=="modifier") await TrayAttentionModifierTests.RunAsync(application,checks);
                    else if (Option("--tray-actions-case","showCard")=="read") await AttentionReadLifetimeTests.RunAsync(application,checks);
                    else if (Option("--tray-actions-case","showCard")=="primary") await AttentionPrimaryDispatchTests.RunAsync(application,checks);
                    else await AttentionActivationTests.ShowCardAsync(application, checks);
                    File.WriteAllText(Option("--report", Path.Combine(Path.GetTempPath(),"devdeck-tray-actions.json")), System.Text.Json.JsonSerializer.Serialize(new { passed=checks.Count, failed=0, componentOnly=true, releaseQualified=false, checks }));
                    application.Shutdown(); return;
                }
                if (args.Contains("--tray-attention-artwork")) {
                    Text.Use(Option("--language", "en"));
                    TrayAttentionArtwork.Write(application, Option("--tray-attention-artwork", Path.Combine(Path.GetTempPath(), "devdeck-tray-attention.png")), Option("--sample-variant", "main"));
                    application.Shutdown(); return;
                }
                if (args.Contains("--tray-artwork")) {
                    DeckTrayArtwork.WritePreview(Option("--tray-artwork",Path.Combine(Path.GetTempPath(),"devdeck-tray-artwork.png")));
                    application.Shutdown(); return;
                }
                if (args.Contains("--window-check"))
                {
                    await WindowChecks.RunAsync(application, Option("--report", Path.Combine(Path.GetTempPath(), "devdeck-window-check.json")));
                    application.Shutdown(); return;
                }
                if (args.Contains("--sample-render"))
                {
                    var sample = SampleDeck.Controller(application);
                    Text.Use(Option("--language", "en"));
                    Window card;
                    if (args.Contains("--sample-settings-provenance")) {
                        card = await SettingsProvenanceSamples.CreateAsync(sample,Option("--sample-variant","native"));
                    }
                    else if (args.Contains("--sample-account-token")) {
                        card = await AccountTokenSamples.WindowAsync(application,Option("--sample-variant","github-present"));
                    }
                    else if (args.Contains("--sample-account-provider")) {
                        card = await AccountProviderSamples.WindowAsync(application,Option("--sample-variant","existing-github"));
                    }
                    else if (args.Contains("--sample-settings-geometry")) {
                        card = await SettingsGeometrySamples.CreateAsync(sample,Option("--sample-variant","general"));
                    }
                    else if (args.Contains("--sample-settings-sidebar")) {
                        card = await SettingsSidebarSamples.WindowAsync(application, Option("--sample-variant", "projects"));
                    }
                    else if (args.Contains("--sample-settings")) {
                        var settings = CreateSampleSettingsWindow(sample);
                        await settings.SelectPageAsync(Option("--sample-page", "general")); card = settings;
                    }
                    else if (args.Contains("--sample-phone")) {
                        var issue = Enum.Parse<PhoneLinkIssue>(Option("--sample-phone-issue","None"));
                        var link = new PhoneLinkResult(issue == PhoneLinkIssue.None ? new Uri("http://192.168.1.8:8080/example?preview=1") : null,issue);
                        card = new Window { Width = 330, SizeToContent = SizeToContent.Height, Content = new PhonePanel(link,_ => { },() => { },() => { }) };
                    }
                    else if (args.Contains("--sample-log")) {
                        var log = new LogWindow(sample, sample.Settings.Cards[0].Project, live: false);
                        log.Apply(new(Enumerable.Range(1, 400).Select(index => index == 370 ? "[error] Synthetic request failed: HTTP 503" : "[info] Synthetic request " + index + " completed").ToArray(), "Synthetic fixture log", null, "/home/user/example/log.txt")); card = log;
                    }
                    else if (args.Contains("--sample-project")) {
                        var kind=Option("--sample-kind","arc");
                        var settings=new CardSettings(new(kind+".project.example","Ubuntu-24.04",kind,"/home/user/example",StartCommand:kind=="local" ? "bun run dev" : null,HealthURL:kind=="local" ? "http://localhost:8111/health" : null,Arc:kind=="arc" ? new("sandbox.example","news") : null,Subtitle:kind=="local" ? "bun · next + nest" : null,OpenURL:kind=="local" ? "http://localhost:4112/front" : null),"Example shop",Links:ProjectLinks.Defaults(kind),HiddenTools:kind=="ddev" ? ["xhgui"] : []);
                        var form=new ProjectSettingsForm(sample,settings,live:false,_ => { },checker:args.Contains("--sample-check") ? (reference,_) => System.Threading.Tasks.Task.FromResult(new ProjectStatus(reference.Id,"stopped",null,null,null,null,
                            CheckSummary:new("bad",Text.L("check.stopped"),reference.Kind=="arc" ? "HTTP 503 · http://localhost:8080/release" : "HTTP 503 · http://localhost:8111/health"),CheckedAt:DateTimeOffset.UtcNow.ToUnixTimeSeconds())) : null);
                        if(args.Contains("--sample-advanced") && form.Content is System.Windows.Controls.Panel panel)
                            foreach(var expander in panel.Children.OfType<System.Windows.Controls.Expander>()) expander.IsExpanded=true;
                        card=new Window { Content=new System.Windows.Controls.ScrollViewer { Content=form,VerticalScrollBarVisibility=System.Windows.Controls.ScrollBarVisibility.Auto },Width=1000,Height=900,Background=System.Windows.Media.Brushes.White };
                    }
                    else if (args.Contains("--sample-notifications")) card = new NotificationSettingsWindow(sample);
                    else if (args.Contains("--sample-arrangement")) card = new ArrangementNameDialog();
                    else if (args.Contains("--sample-ddev-poweroff")) card = new DDEVPowerOffDialog(["Ubuntu-24.04", "Debian"]);
                    else if (args.Contains("--sample-account")) card = new Window { Width=960,Height=900,Background=System.Windows.Media.Brushes.White,Content=new System.Windows.Controls.ScrollViewer { Content=new AccountSettingsForm(sample,sample.Settings.AccountList[0],live:false,_=>{}),VerticalScrollBarVisibility=System.Windows.Controls.ScrollBarVisibility.Auto } };
                    else if (args.Contains("--sample-browser")) {
                        var picker=new BrowserPicker("chrome","Profile 2",[new("chrome","Google Chrome","C:/synthetic/chrome.exe",true),new("vivaldi","Vivaldi","C:/synthetic/vivaldi.exe",true)],_=>[new("Default","Personal"),new("Profile 2","Work projects")]);
                        var panel=SettingsForm.Page(Text.L("account.openLinksIn"));SettingsForm.Field(panel,Text.L("account.openLinksIn"),picker.Picker);SettingsForm.Field(panel,Text.L("windows.profile"),picker.Profile);
                        var root=new System.Windows.Controls.Grid();root.Children.Add(panel);
                        card=new Window { Width=720,Height=320,Background=System.Windows.Media.Brushes.White,Content=root };
                    }
                    else if (args.Contains("--sample-attention-actions")) card = AttentionActionSamples.Window(sample,Option("--sample-variant","ready"));
                    else if (args.Contains("--sample-attention")) card = new AttentionWindow(sample,
                        [new("sample", "sample", "needsFixing", "token", Text.L("attention.account.rejected.title", "GitHub", "Example account"),
                            Text.L("attention.account.rejected.subtitle", "HTTP 401"), null, new("none"), false, false)]);
                    else if(args.Contains("--sample-wif-settings")) {
                        await sample.SetWIFVisibleAsync(true);
                        var settingsView=CreateSampleSettingsWindow(sample);settingsView.SelectPage("cards");card=settingsView;
                    }
                    else if (args.Contains("--sample-wif")) card=WorkInFlightSamples.Card(sample,Option("--sample-variant","mixed"),args.Contains("--sample-collapsed"));
                    else if (args.Contains("--sample-remote"))
                    {
                        var kind = Option("--sample-kind","pullRequests");
                        var remote = new RemoteCard(sample, SampleDeck.RemoteSettings(kind,args.Contains("--sample-collapsed")), live: false);
                        var snapshot = SampleDeck.Remote(kind);
                        if (args.Contains("--sample-empty")) snapshot = snapshot with { Rows = [], Total = 0, Blocked = 0, SuccessRate = null,RepositoryCount = 0,FollowsPullRequests = true,RunningCount = 0,AverageDurationSeconds = null,ReviewCount = 0,ActionableCount = 0,WatchedRepositories = [] };
                        if (args.Contains("--sample-quiet")) snapshot = snapshot with { Rows = [], Total = 0, Blocked = 0, SuccessRate = null,RunningCount = 0,AverageDurationSeconds = null,ReviewCount = 0,ActionableCount = 0 };
                        if (args.Contains("--sample-partial")) snapshot = snapshot with { Failures = [new(kind == "mergeRequests" ? "lab" : "second","rateLimited")], Capped = true };
                        remote.ApplySnapshot(snapshot);
                        if (args.Contains("--sample-error")) remote.ApplyFailure(new WorkerException("remoteUnavailable","Synthetic offline failure"));
                        if (args.Contains("--sample-busy")) remote.SetMutationPresentation(true);
                        card = remote;
                    }
                    else
                    {
                        var kind = Option("--sample-kind","ddev");
                        var project = new ProjectCard(sample, new CardSettings(new("ddev.project.sample", "Ubuntu-24.04", kind, args.Contains("--sample-hosted") ? "" : "/home/user/example",StartCommand:kind=="local" ? "bun run dev" : null,Arc:kind=="arc" ? new("sandbox.example","news") : null,Subtitle:kind=="local" ? "bun · next + nest" : null), "Example shop", Collapsed: args.Contains("--sample-collapsed"),HiddenTools:kind == "ddev" ? ["xhgui"] : [],Links:kind=="arc" ? ProjectLinks.Defaults(kind) : null), live: false);
                        project.ApplySnapshot(new("ddev.project.sample", args.Contains("--sample-hosted") ? "unavailable" : Option("--sample-state", "running"), "feature/widgets", args.Contains("--sample-hosted") ? null : "http://localhost:8080", kind == "ddev" ? "drupal 11" : kind == "arc" ? null : "bun · next + nest", kind == "local" ? "bun run dev" : null,VersionsLine:kind == "ddev" ? "php 8.4 · mysql 8.0" : null,RepositoryURL:"https://example.com/repository",ToolLinks:kind == "ddev" ? [new("Mailpit","http://localhost:8025"),new("xhgui","http://localhost:8143")] : [],LocalEditorURL:kind=="arc" && !args.Contains("--sample-hosted") ? "http://localhost:8080/pagebuilder/experiences/_default/pages/" : null));
                        if (args.Contains("--sample-docker")) {
                            project.ApplyAttention(new("local:Ubuntu-24.04", [], [], "notRunning", false));
                            project.ApplySnapshot(new("ddev.project.sample", "stopped", "feature/widgets", null, "drupal 11", null));
                        }
                        if (args.Contains("--sample-busy")) project.ShowOperation("restart");
                        if (args.Contains("--sample-group-busy")) project.BeginDDEVPowerOff("owned-synthetic-group");
                        card = project;
                    }
                    if(args.Contains("--sample-project")||args.Contains("--sample-account")||args.Contains("--sample-browser"))card.Resources=CreateSampleSettingsWindow(sample).Resources;
                    card.Show(); card.UpdateLayout();
                    if (args.Contains("--sample-advanced") && card.Content is System.Windows.Controls.ScrollViewer scroll) { scroll.ScrollToEnd(); card.UpdateLayout(); }
                    var render = (System.Windows.FrameworkElement)card.Content;
                    if(args.Contains("--sample-context")){
                        var context=card.ContextMenu??throw new InvalidOperationException("Synthetic card has no context menu.");
                        context.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.ContextMenu.OpenedEvent));
                        context.ApplyTemplate();context.Measure(new Size(double.PositiveInfinity,double.PositiveInfinity));
                        context.Arrange(new Rect(new Point(),context.DesiredSize));context.UpdateLayout();render=context;
                    }
                    var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap((int)render.ActualWidth, (int)render.ActualHeight, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
                    var background = new System.Windows.Media.DrawingVisual();
                    using (var drawing = background.RenderOpen()) drawing.DrawRectangle(args.Contains("--sample-context")?SystemColors.MenuBrush:card.Background,null,new Rect(0,0,render.ActualWidth,render.ActualHeight));
                    bitmap.Render(background);
                    bitmap.Render(render);
                    var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
                    encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
                    using (var image = File.Create(Option("--sample-render", "sample.png"))) encoder.Save(image);
                    card.Close(); application.Shutdown(); return;
                }
                var controller = new DeckController(application, new SettingsStore(path));
                await controller.StartAsync();
                instance?.Listen(() => application.Dispatcher.BeginInvoke(new Action(controller.ShowCards)));
                if (args.Contains("--integration-check"))
                {
                    var report = Option("--report", Path.Combine(Path.GetTempPath(), "devdeck-windows-integration.json"));
                    await controller.CheckAsync(report);
                    await controller.CloseAsync();
                }
            }
            catch (Exception error)
            {
                if (args.Contains("--settings-provenance-check") || args.Contains("--account-token-check") || args.Contains("--account-provider-check") || args.Contains("--settings-geometry-check") || args.Contains("--sidebar-check") || args.Contains("--tray-actions-check") || args.Contains("--integration-check") || args.Contains("--window-check") || args.Contains("--sample-render") || args.Contains("--tray-attention-artwork"))
                {
                    var report = Option("--report", Path.Combine(Path.GetTempPath(), "devdeck-windows-integration.json"));
                    if (args.Contains("--settings-provenance-check") || args.Contains("--account-token-check") || args.Contains("--account-provider-check") || args.Contains("--settings-geometry-check") || args.Contains("--sidebar-check") || args.Contains("--tray-actions-check") || args.Contains("--window-check"))
                        await File.WriteAllTextAsync(report, System.Text.Json.JsonSerializer.Serialize(new { error = error.Message, exceptionType = error.GetType().FullName, hresult = error.HResult, stackTrace = error.StackTrace, releaseQualified = false }));
                    else
                        await File.WriteAllTextAsync(report, System.Text.Json.JsonSerializer.Serialize(new { error = error.Message, releaseQualified = false }));
                }
                else MessageBox.Show(Text.Failure(error), "DevDeck", MessageBoxButton.OK, MessageBoxImage.Error);
                application.Shutdown(1);
            }
        };
        return application.Run();
    }
}
