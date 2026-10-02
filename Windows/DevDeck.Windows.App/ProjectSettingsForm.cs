using System;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed class ProjectSettingsForm : SettingsForm
{
    private CardSettings? original;
    private readonly Action<string> changed;
    private readonly ComboBox distribution, kind;
    private readonly TextBox title, path, start, stop, health, organization, arcSite, localURL, healthPath, subtitle, open, phoneURL;
    private ProjectLinkEditor linkEditor;
    private readonly BrowserPicker browser;
    private readonly string draftIdentity = Guid.NewGuid().ToString("N");
    private readonly Func<SettingsRemovalRequest,bool>? confirmation;
    internal ProjectCheckRow HealthCheck { get; }
    private readonly CheckBox shown, holds, docker, down, failed;
    private readonly Button add;
    private readonly Button detect;
    private readonly TextBlock detectNote = new() { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DimGray, FontSize = 12 };
    private readonly Func<ProjectReference,Task<ProjectSuggestion?>>? probe;
    private (string Name, CheckBox Toggle)[] tools = [];
    internal ProjectSettingsForm(DeckController controller, CardSettings? original, bool live, Action<string> changed, Func<ProjectReference,Task<ProjectSuggestion?>>? probe = null,
        Func<SettingsRemovalRequest,bool>? confirmation = null, Func<ProjectReference,System.Threading.CancellationToken,Task<ProjectStatus>>? checker = null,
        bool discoverDistributions = true) : base(controller, live)
    {
        this.original = original; this.changed = changed; this.probe = probe; this.confirmation=confirmation; Autosaves = original is not null;
        var panel = Page(original?.Title ?? Text.L("windows.newProject"));
        panel.Children.Clear();
        shown = Toggle(Text.L("account.showOnDeck"), original?.Enabled ?? true); shown.MaxWidth = 225;
        title = new() { Text = original?.Title ?? "" }; path = new() { Text = original?.Project.Path ?? "" };
        start = new() { Text = original?.Project.StartCommand ?? (original?.Project.Kind == "arc" ? "npx --no-install fusion daemon" : "") };
        stop = new() { Text = original?.Project.StopCommand ?? (original?.Project.Kind == "arc" ? "npx --no-install fusion stop" : "") };
        health = new() { Text = original?.Project.HealthURL ?? "" }; subtitle = new() { Text = original?.Project.Subtitle ?? "" };
        open = new() { Text = original?.Project.OpenURL ?? "" };
        open.ToolTip = Text.L("project.openURL.placeholder");
        phoneURL = new() { Text = original?.PhoneURL ?? "" };
        distribution = new() { ItemsSource = controller.Settings.Workers.Select(worker => worker.Distribution).ToArray(), SelectedItem = original?.Project.Distribution ?? controller.Settings.Workers.FirstOrDefault()?.Distribution };
        kind = new() { ItemsSource = new[] { "ddev", "arc", "local" }, SelectedItem = original?.Project.Kind ?? "ddev", IsEnabled = original is null };
        var header = new DockPanel { Margin = new(0,8,0,12) }; DockPanel.SetDock(shown,Dock.Right); header.Children.Add(shown);
        var mark = new Border { Child = BrandMarks.Create(BrandMarks.ProjectKind(original?.Project.Kind ?? "ddev"),26,tile:true), Margin = new(0,0,12,0), VerticalAlignment = VerticalAlignment.Center }; DockPanel.SetDock(mark,Dock.Left); header.Children.Add(mark);
        var labels = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var heading = new TextBlock { FontSize = 20, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis, Text = original?.Title ?? Text.L("windows.newProject") };
        labels.Children.Add(heading); labels.Children.Add(new TextBlock { Text = (original?.Project.Kind.ToUpperInvariant() ?? "DDEV") + " · " + (original?.Project.Distribution ?? distribution.SelectedItem as string), Foreground = Brushes.Gray, FontSize = 12 }); header.Children.Add(labels); panel.Children.Add(header);
        void UpdateHeader() {
            heading.Text = title.Text.Length == 0 ? Text.L("windows.newProject") : title.Text;
            ((TextBlock)labels.Children[1]).Text = (kind.SelectedItem as string)?.ToUpperInvariant() + " · " + path.Text.TrimEnd('/').Split('/').Last();
            mark.Child = BrandMarks.Create(BrandMarks.ProjectKind(kind.SelectedItem as string ?? "ddev",subtitle.Text,start.Text),26,tile:true);
        }
        UpdateHeader(); title.TextChanged += (_,_) => UpdateHeader(); path.TextChanged += (_,_) => UpdateHeader(); kind.SelectionChanged += (_,_) => UpdateHeader();
        start.TextChanged += (_,_) => UpdateHeader(); subtitle.TextChanged += (_,_) => UpdateHeader();
        if (original is not null) {
            var compact = Toggle(Text.L("windows.compactCard"),original.Collapsed); panel.Children.Add(compact);
            compact.Click += async (_,_) => await ExecuteAsync(() => { Controller.SetCardCollapsed(this.original!.Project.Id,compact.IsChecked == true); return Task.CompletedTask; });
        }
        if (original is null) Note(panel,Text.L("windows.addGuide"));
        Section(panel,Text.L("project.section.project")); var projectRows = Group(panel);
        Field(projectRows, Text.L("account.name"), title); Field(projectRows, Text.L("windows.distribution"), distribution);
        if (original is null) Field(projectRows, Text.L("windows.projectType"), kind);
        var folderRow = new DockPanel();
        var choose = Button(Text.L("button.choose"), async () => {
            var distro = distribution.SelectedItem as string ?? throw new InvalidOperationException(Text.L("windows.chooseDistribution"));
            var dialog = new Microsoft.Win32.OpenFolderDialog { InitialDirectory = @"\\wsl.localhost\" + distro + path.Text.Replace('/','\\'), Title = Text.L("project.folder") };
            if (dialog.ShowDialog() == true) {
                path.Text = LinuxFolder.FromWindows(distro,dialog.FolderName) ?? throw new InvalidOperationException(Text.L("windows.validationFolder"));
                if (original is null && string.IsNullOrWhiteSpace(title.Text)) title.Text = path.Text.TrimEnd('/').Split('/').Last();
                if (original is null && kind.SelectedItem as string == "local" && start.Text.Length == 0) await DetectAsync();
            }
        }); choose.Margin = new(8,0,0,0); DockPanel.SetDock(choose,Dock.Right); folderRow.Children.Add(choose); folderRow.Children.Add(path); path.Padding = new(5,3,5,3); path.MinHeight = 28;
        System.Windows.Automation.AutomationProperties.SetName(path,Text.L("windows.linuxFolder")); Field(projectRows,Text.L("project.folder"),folderRow);
        holds = Toggle(Text.L("windows.persistent"), original?.Project.HoldsProcess ?? true); docker = Toggle(Text.L("windows.requiresDocker"), original?.Project.RequiresDocker ?? false);
        detect = Button(Text.L("button.detect"),DetectAsync); detect.Margin = new(8,0,0,0); DockPanel.SetDock(detect,Dock.Right);
        var startRow = new DockPanel(); startRow.Children.Add(detect); startRow.Children.Add(start);
        System.Windows.Automation.AutomationProperties.SetName(start,Text.L("project.startCommand"));
        var commands = new StackPanel(); Field(commands, Text.L("project.startCommand"), startRow); Field(commands, Text.L("project.stopCommand"), stop);
        commands.Children.Add(detectNote);
        var healthRow = new StackPanel(); Section(healthRow,Text.L("project.section.health")); Field(healthRow, Text.L("project.checkURL"), health); Field(healthRow,Text.L("project.openURL"),open);
        commands.Children.Add(holds); commands.Children.Add(docker); panel.Children.Add(commands);
        panel.Children.Add(healthRow);
        void UpdateKind() { var local = kind.SelectedItem as string == "local"; commands.Visibility = kind.SelectedItem as string is "local" or "arc" ? Visibility.Visible : Visibility.Collapsed; healthRow.Visibility = holds.Visibility = docker.Visibility = detect.Visibility = local ? Visibility.Visible : Visibility.Collapsed; stop.ToolTip = local ? Text.L("windows.stopHint") : null;
            System.Windows.Automation.AutomationProperties.SetName(health,local ? Text.L("project.checkURL") : ""); System.Windows.Automation.AutomationProperties.SetName(open,local ? Text.L("project.openURL") : ""); }
        UpdateKind(); kind.SelectionChanged += (_, _) => UpdateKind();
        organization = new() { Text = original?.Project.Arc?.Organization ?? "" }; arcSite = new() { Text = original?.Project.Arc?.Site ?? "" };
        localURL = new() { Text = original?.Project.Arc?.LocalURL ?? "" }; healthPath = new() { Text = original?.Project.Arc?.HealthPath ?? "/release" };
        var arcPanel = new StackPanel(); Section(arcPanel,"Arc XP"); var arcRows = Group(arcPanel);
        Field(arcRows,Text.L("project.arc.organisation"),organization); Field(arcRows,Text.L("project.arc.site"),arcSite);
        Field(arcRows,Text.L("project.openURL"),localURL); Field(arcRows,Text.L("project.checkURL"),healthPath);
        Note(arcPanel,Text.L("project.arc.footnote")); panel.Children.Add(arcPanel);
        void UpdateArc() { var arc = kind.SelectedItem as string == "arc"; arcPanel.Visibility = arc ? Visibility.Visible : Visibility.Collapsed;
            System.Windows.Automation.AutomationProperties.SetName(localURL,arc ? Text.L("project.openURL") : ""); System.Windows.Automation.AutomationProperties.SetName(healthPath,arc ? Text.L("project.checkURL") : ""); }
        UpdateArc(); kind.SelectionChanged += (_,_) => UpdateArc();
        ProjectReference? CheckReference() {
            var type=kind.SelectedItem as string;var folder=path.Text.Trim();var distro=distribution.SelectedItem as string;
            if(type is not ("local" or "arc")||!LinuxPath.IsAbsolute(folder)||string.IsNullOrWhiteSpace(distro))return null;
            return new(original?.Project.Id??type+".project."+draftIdentity,distro,type,folder,start.Text,stop.Text,holds.IsChecked==true,docker.IsChecked==true,type=="local"?health.Text:null,
                Arc:type=="arc"?new("",null,localURL.Text.Trim(),healthPath.Text.Trim()):null);
        }
        HealthCheck=new(CheckReference,checker??(Live ? Controller.CheckProjectAsync : null),Lifetime.Token);
        var checkingGroup=new StackPanel(); Section(checkingGroup,Text.L("project.section.health"));var checkHeading=(UIElement)checkingGroup.Children[0];checkingGroup.Children.Add(HealthCheck);panel.Children.Add(checkingGroup);
        void UpdateCheckKind(){checkingGroup.Visibility=kind.SelectedItem as string is "local" or "arc"?Visibility.Visible:Visibility.Collapsed;checkHeading.Visibility=kind.SelectedItem as string=="arc"?Visibility.Visible:Visibility.Collapsed;HealthCheck.RefreshIdentity();}
        foreach(var field in new[]{path,start,health,localURL,healthPath})field.TextChanged+=(_,_)=>HealthCheck.RefreshIdentity();
        distribution.SelectionChanged+=(_,_)=>HealthCheck.RefreshIdentity();kind.SelectionChanged+=(_,_)=>UpdateCheckKind();UpdateCheckKind();
        Loaded+=async(_,_)=>await HealthCheck.CheckOnArrivalAsync();
        down = Toggle(Text.L("settings.notifications.column.down"), original?.NotifiesWhenDown ?? true);
        failed = Toggle(Text.L("settings.notifications.column.startFailed"), original?.NotifiesStartFailed ?? true);
        down.IsEnabled = failed.IsEnabled = controller.Settings.Notifications;
        var toolsPanel = new StackPanel(); Section(toolsPanel,Text.L("project.ddev.tools")); var toolRows = Group(toolsPanel); panel.Children.Add(toolsPanel);
        void BuildTools() {
            toolRows.Children.Clear(); var projectKind = kind.SelectedItem as string ?? "ddev";
            tools = (projectKind == "ddev" ? CardSettings.Tools(projectKind) : []).Select(name => (Name:name,Toggle:Toggle(name,original is null ? name != "xhgui" : !original.HiddenToolList.Contains(name,StringComparer.OrdinalIgnoreCase)))).ToArray();
            foreach (var item in tools) { toolRows.Children.Add(item.Toggle); Watch(item.Toggle); }
            toolsPanel.Visibility = tools.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        }
        BuildTools(); kind.SelectionChanged += (_,_) => BuildTools();
        Section(panel,Text.L("project.section.links")); var linkPanel = new StackPanel(); panel.Children.Add(linkPanel);
        linkEditor = new(ProjectLinks.Editable(original,kind.SelectedItem as string ?? "ddev"),Changed,kind.SelectedItem as string ?? "ddev"); linkPanel.Children.Add(linkEditor);
        kind.SelectionChanged += (_,_) => { linkPanel.Children.Clear(); linkEditor = new(ProjectLinks.Editable(original,kind.SelectedItem as string ?? "ddev"),Changed,kind.SelectedItem as string ?? "ddev"); linkPanel.Children.Add(linkEditor); };
        var linkHint=Note(panel,Text.L("windows.linkTemplateHint"));
        void UpdateLinkHint() { linkHint.Visibility=kind.SelectedItem as string == "local" ? Visibility.Collapsed : Visibility.Visible; }
        UpdateLinkHint(); kind.SelectionChanged += (_,_) => UpdateLinkHint();
        var phoneRows = new StackPanel(); Section(phoneRows, Text.L("card.phone.title"));
        Field(phoneRows,Text.L("windows.phoneURL"),phoneURL); Note(phoneRows,Text.L("windows.phoneURLHint")); panel.Children.Add(phoneRows);
        browser = new(original?.Browser ?? "system",original?.BrowserProfile);
        var browserRow = new DockPanel(); var test = Button(Text.L("button.test"), async () => {
            var draft = CreateDraft(); ProjectStatus? status = null;
            if (Live && draft.Project.Kind == "ddev") {
                status=await Controller.CheckProjectAsync(draft.Project,Lifetime.Token);
            }
            if (Lifetime.IsCancellationRequested) return;
            var url = ProjectLinks.TestTarget(draft,status);
            if (url is null) throw new InvalidOperationException(Text.L("project.link.nothingToOpen"));
            BrowserLaunch.Open(draft.Browser,draft.BrowserProfile,url);
        }); test.Margin = new(8,0,0,0); DockPanel.SetDock(test,Dock.Right); browserRow.Children.Add(test); browserRow.Children.Add(browser.Picker);
        var browserRows = new StackPanel { Margin = new(0,12,0,0) }; Field(browserRows,Text.L("account.openLinksIn"),browserRow); panel.Children.Add(browserRows);
        var profileRow=new StackPanel();Field(profileRow,Text.L("windows.profile"),browser.Profile);profileRow.SetBinding(VisibilityProperty,new System.Windows.Data.Binding(nameof(Visibility)){Source=browser.Profile});browserRows.Children.Add(profileRow);
        var advanced = new StackPanel(); var captionRow = new StackPanel(); Field(captionRow,Text.L("project.caption"),subtitle); subtitle.ToolTip = Text.L("project.caption.placeholder"); advanced.Children.Add(captionRow);
        void UpdateCaption() { captionRow.Visibility = kind.SelectedItem as string == "local" ? Visibility.Visible : Visibility.Collapsed; }
        UpdateCaption(); kind.SelectionChanged += (_,_) => UpdateCaption();
        advanced.Children.Add(down); advanced.Children.Add(failed);
        panel.Children.Add(new Expander { Header = Text.L("windows.advanced"), Content = advanced, Margin = new(0, 20, 0, 12) });
        add = Button(Text.L("windows.addProject"), () => ExecuteAsync(SaveMetadataAsync)); add.Visibility = original is null ? Visibility.Visible : Visibility.Collapsed; panel.Children.Add(add);
        if (original is not null) panel.Children.Add(Button(Text.L("windows.removeCard"),RemoveAsync));
        else panel.Children.Add(Button(Text.L("windows.importDdev"), () => ExecuteAsync(ImportAsync)));
        panel.Children.Add(Button(Text.L("windows.refreshDistributions"), () => DiscoverAsync(distribution, distribution.SelectedItem as string)));
        panel.Children.Add(Message); Content = panel;
        foreach (var field in new[] { title, path, start, stop, health, organization,arcSite,localURL,healthPath,subtitle,open,phoneURL }) Watch(field);
        Watch(kind); Watch(distribution);browser.ValueChanged+=(_,_)=>Changed();foreach (var field in new[] { holds, docker, down, failed }) Watch(field);
        shown.Click += async (_, _) => {
            if (!Live || original is null || IsDisposed) return;
            var id = original.Project.Id; var visible = shown.IsChecked == true;
            try { await Controller.RunMenuAsync(() => Controller.SetCardVisibleAsync(id, visible)); }
            finally { if (Controller.Settings.Cards.FirstOrDefault(card => card.Project.Id == id) is { } current) ReconcileEnabled(current); }
        };
        if (discoverDistributions) Loaded += async (_, _) => { var autosaves = Autosaves; Autosaves = false; await DiscoverAsync(distribution, original?.Project.Distribution); Autosaves = autosaves; };
    }
    internal void ReconcileEnabled(CardSettings current)
    {
        if (IsDisposed || original is null || original.Project.Id != current.Project.Id) return;
        original = original with { Enabled = current.Enabled };
        shown.IsChecked = current.Enabled;
    }
    internal string? TestLinkTarget(ProjectStatus? status = null) => ProjectLinks.TestTarget(CreateDraft(),status);
    internal void ApplySuggestion(ProjectSuggestion suggestion)
    {
        var current = new ProjectReference(original?.Project.Id ?? "project.detect",distribution.SelectedItem as string ?? "","local",path.Text,
            start.Text,stop.Text,holds.IsChecked == true,docker.IsChecked == true,health.Text,Subtitle:subtitle.Text,OpenURL:open.Text);
        var next = ProjectDetection.Apply(current,suggestion);
        start.Text = next.StartCommand!; stop.Text = next.StopCommand!; holds.IsChecked = next.HoldsProcess; docker.IsChecked = next.RequiresDocker;
        subtitle.Text = next.Subtitle ?? ""; health.Text = next.HealthURL ?? ""; Changed();
    }
    internal async Task DetectAsync()
    {
        if ((!Live && probe is null) || kind.SelectedItem as string != "local") return;
        detect.IsEnabled = false;
        var folder=path.Text.Trim();var distro=distribution.SelectedItem as string;
        try {
            if (!LinuxPath.IsAbsolute(folder)) throw new InvalidOperationException(Text.L("project.detect.noFolder"));
            if(distro is null)throw new InvalidOperationException(Text.L("windows.chooseDistribution"));
            var reference = new ProjectReference(original?.Project.Id ?? "project.detect",distro,"local",folder);
            ProjectSuggestion? result;
            if (probe is not null) result = await probe(reference);
            else {
                var worker = await Controller.EnsureWorkerAsync(distro);
                result = (await (await Controller.Workers.GetAsync(worker)).CallAsync("project.probe",reference,cancellation:Lifetime.Token)).Suggestion;
            }
            if (Lifetime.IsCancellationRequested || path.Text.Trim() != folder || distribution.SelectedItem as string != distro || kind.SelectedItem as string != "local") return;
            if (result is not { } suggestion) { detectNote.Text = Text.L("project.detect.nothing"); detectNote.Foreground = Brushes.Firebrick; return; }
            ApplySuggestion(suggestion);
            var found = suggestion.Subtitle + (suggestion.RequiresDocker ? ", " + Text.L("project.detect.needsDocker") : "");
            detectNote.Text = Text.L("project.detect.found",found.Length == 0 ? suggestion.StartCommand : found); detectNote.Foreground = Brushes.DimGray;
        } catch (OperationCanceledException) { }
        catch (Exception error) { if(!IsDisposed&&path.Text.Trim()==folder&&distribution.SelectedItem as string==distro&&kind.SelectedItem as string=="local") { detectNote.Text = Text.Failure(error); detectNote.Foreground = Brushes.Firebrick; } }
        finally { detect.IsEnabled = true; }
    }
    internal CardSettings CreateDraft()
    {
        var projectKind = (string)kind.SelectedItem; var folder = path.Text.Trim();
        var distro = distribution.SelectedItem as string ?? (projectKind == "arc" && folder.Length == 0 ? "" : throw new InvalidOperationException(Text.L("windows.chooseDistribution")));
        if (!(LinuxPath.IsAbsolute(folder) || projectKind == "arc" && folder.Length == 0)) throw new InvalidOperationException(Text.L("windows.validationFolder"));
        if (string.IsNullOrWhiteSpace(title.Text)) throw new InvalidOperationException(Text.L("windows.validationName"));
        if (projectKind == "local" && string.IsNullOrWhiteSpace(start.Text)) throw new InvalidOperationException(Text.L("windows.validationStart"));
        if (projectKind == "local" && holds.IsChecked != true && string.IsNullOrWhiteSpace(health.Text)) throw new InvalidOperationException(Text.L("windows.validationHealthRequired"));
        if (health.Text.Length > 0 && (!Uri.TryCreate(health.Text, UriKind.Absolute, out var url) || url.Scheme is not ("http" or "https") || url.UserInfo.Length > 0)) throw new InvalidOperationException(Text.L("windows.validationHealth"));
        var reference = new ProjectReference(original?.Project.Id ?? projectKind + ".project." + draftIdentity, distro, projectKind, folder,
            projectKind is "local" or "arc" && start.Text.Length > 0 ? start.Text : null, projectKind is "local" or "arc" && stop.Text.Length > 0 ? stop.Text : null, projectKind == "local" ? holds.IsChecked == true : null,
            projectKind == "local" ? docker.IsChecked == true : null, projectKind == "local" ? health.Text : null,
            Arc:projectKind == "arc" ? new(organization.Text.Trim(),arcSite.Text.Trim(),localURL.Text.Trim(),healthPath.Text.Trim()) : null,
            Subtitle:projectKind == "local" ? subtitle.Text.Trim() : null,OpenURL:projectKind == "local" ? open.Text.Trim() : null);
        var customLinks = linkEditor.Value;
        if (customLinks.Any(link => !DeckSettings.ValidConfiguredLink(link)) || !ProjectLinks.ValidArc(reference.Arc)) throw new InvalidOperationException(Text.L("windows.validationArcLinks"));
        if (!ProjectDetection.ValidSubtitle(reference.Subtitle)) throw new InvalidOperationException(Text.L("windows.validationCaption"));
        if (!ProjectDetection.ValidOpenURL(reference.OpenURL)) throw new InvalidOperationException(Text.L("windows.validationOpenURL"));
        if (!PhoneLink.ValidPhoneURL(phoneURL.Text.Trim())) throw new InvalidOperationException(Text.L("windows.validationPhoneURL"));
        var count = Controller.Settings.Cards.Length;
        return (original ?? new CardSettings(reference, title.Text.Trim(), X: 48 + 430 * (count % 3), Y: 80 + 285 * (count / 3))) with { Project = reference, Title = title.Text.Trim(), Enabled = shown.IsChecked == true,
            NotifiesWhenDown = down.IsChecked == true, NotifiesStartFailed = failed.IsChecked == true, Browser = browser.BrowserID, BrowserProfile = browser.SelectedProfile, Links = customLinks, PhoneURL = phoneURL.Text.Trim().Length == 0 ? null : phoneURL.Text.Trim(), HiddenTools = projectKind == "arc" ? original?.HiddenTools : tools.Where(item => item.Toggle.IsChecked != true).Select(item => item.Name).ToArray() };
    }
    protected override async Task SaveMetadataAsync()
    {
        if (!Live) return;
        var draft = CreateDraft(); var reference = draft.Project; var distro = reference.Distribution; var folder = reference.Path; var projectKind = reference.Kind;
        await Controller.SaveSettingsAsync(current => {
            if (reference.HasLocalFolder && current.Cards.Any(card => card.Project.Id != draft.Project.Id && card.Project.Distribution == distro && card.Project.Path == folder && card.Project.Kind == projectKind)) throw new InvalidOperationException(Text.L("windows.validationDuplicate"));
            var existing = current.Cards.FirstOrDefault(card => card.Project.Id == reference.Id);
            // Visibility is committed by its own action; a captured metadata draft cannot undo it.
            var replacement = existing is null ? draft : draft with { X = existing.X, Y = existing.Y, Collapsed = existing.Collapsed, Enabled = existing.Enabled };
            return current with { Cards = existing is null ? current.Cards.Append(replacement).ToArray() : current.Cards.Select(card => card.Project.Id == reference.Id ? replacement : card).ToArray() };
        });
        original = Controller.Settings.Cards.Single(card => card.Project.Id == reference.Id); Autosaves = true; add.Visibility = Visibility.Collapsed; changed(reference.Id);
    }
    internal async Task RemoveAsync()
    {
        if(original is null||!IsEnabled||(!Live&&confirmation is null))return;
        await FlushAsync();if(IsDisposed||original is null||!IsEnabled||!SettingsConfirmation.ForProject(this,original,confirmation)||!Live)return;
        await ExecuteAsync(async()=>{var id=original.Project.Id;await Controller.SaveSettingsAsync(current=>current with{Cards=current.Cards.Where(card=>card.Project.Id!=id).ToArray()});original=null;Autosaves=false;changed("");});
    }
    public override void Dispose(){HealthCheck.Dispose();base.Dispose();}
    private async Task ImportAsync()
    {
        if (!Live) return;
        var distro = distribution.SelectedItem as string ?? throw new InvalidOperationException(Text.L("windows.chooseDistribution"));
        var worker = await Controller.EnsureWorkerAsync(distro);
        var projects = (await (await Controller.Workers.GetAsync(worker)).CallAsync("ddev.list", cancellation: Lifetime.Token)).Projects ?? [];
        await Controller.SaveSettingsAsync(current => {
            var cards = current.Cards.ToList();
            foreach (var project in projects) if (LinuxPath.IsAbsolute(project.Path) && !cards.Any(card => card.Project.Distribution == distro && card.Project.Path == project.Path && card.Project.Kind == "ddev"))
                cards.Add(new(new("ddev.project." + Guid.NewGuid().ToString("N"), distro, "ddev", project.Path), project.Name, X: 48 + 430 * (cards.Count % 3), Y: 80 + 285 * (cards.Count / 3)));
            return current with { Cards = cards.ToArray() };
        }); changed("");
    }
}
