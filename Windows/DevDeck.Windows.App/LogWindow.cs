using System;
using System.IO;
using System.Linq;
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

internal sealed class LogWindow : Window
{
    private readonly DeckController controller;
    private readonly Func<ProjectReference,CancellationToken,Task<WorkerLogs?>> logsReader;
    private ProjectReference project;
    private readonly TextBox lines = new() { Text = Text.L("card.log.reading"), IsReadOnly = true, FontFamily = new("Consolas"), FontSize = 12,
        TextWrapping = TextWrapping.NoWrap, Foreground = CardTheme.Ink, Background = CardTheme.PanelBackground, BorderThickness = new(0),
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new(16) };
    private readonly TextBox query = new() { Width = 230, Margin = new(0, 0, 10, 0) };
    private readonly StackPanel search = new() { Orientation = Orientation.Horizontal, Margin = new(16, 0, 16, 12), Visibility = Visibility.Collapsed };
    private readonly TextBlock source = new() { Foreground = CardTheme.Secondary, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock heading = new() { TextTrimming = TextTrimming.CharacterEllipsis, Foreground = CardTheme.Ink, FontSize = 18, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
    private readonly CheckBox follow = new() { Content = Text.L("card.log.follow"), IsChecked = true, Foreground = CardTheme.Ink, VerticalAlignment = VerticalAlignment.Center, Margin = new(12, 0, 12, 0) };
    private readonly Button file;
    private readonly Button terminal;
    private readonly DispatcherTimer polling = new() { Interval = TimeSpan.FromSeconds(2) };
    private readonly CancellationTokenSource lifetime = new();
    private bool reading;
    private bool applying;
    private bool closed;
    internal WorkerLogs? Latest { get; private set; }
    internal bool IsFollowing => follow.IsChecked == true;
    internal void Search(string value, bool backwards = false) { query.Text = value; Find(backwards); }
    internal string Selection => lines.SelectedText;

    internal LogWindow(DeckController controller, ProjectReference project, bool live = true,
        Func<ProjectReference,CancellationToken,Task<WorkerLogs?>>? logsReader = null)
    {
        this.controller = controller; this.project = project;
        this.logsReader = logsReader ?? controller.ReadLogsAsync;
        Title = "DevDeck · " + (project.Title ?? project.Id) + " · " + Text.L("card.log.window.subtitle");
        Width = 900; Height = 560; MinWidth = 640; MinHeight = 320; Background = CardTheme.PanelBackground;
        var saved = controller.Settings.LogWindowList.FirstOrDefault(item => item.CardID == project.Id);
        if (saved is not null) { Left = saved.X; Top = saved.Y; Width = saved.Width; Height = saved.Height; }
        else WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var content = new DockPanel();
        var header = new DockPanel { Margin = new(16, 14, 16, 12) };
        var tools = new StackPanel { Orientation = Orientation.Horizontal };
        tools.Children.Add(CardTheme.Button(Text.L("settings.search"), () => { search.Visibility = Visibility.Visible; query.Focus(); return Task.CompletedTask; }));
        tools.Children.Add(CardTheme.Button(Text.L("menu.refresh"), RefreshAsync, "refresh", iconOnly: true));
        DockPanel.SetDock(tools, Dock.Right); header.Children.Add(tools);
        heading.Text = project.Title ?? project.Id; header.Children.Add(heading);
        DockPanel.SetDock(header, Dock.Top); content.Children.Add(header);
        query.SetValue(System.Windows.Automation.AutomationProperties.NameProperty, Text.L("settings.search"));
        query.KeyDown += (_, args) => { if (args.Key == Key.Enter) { Find(Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)); args.Handled = true; } };
        search.Children.Add(query);
        search.Children.Add(CardTheme.Button(Text.L("windows.findPrevious"), () => { Find(true); return Task.CompletedTask; }));
        search.Children.Add(CardTheme.Button(Text.L("windows.findNext"), () => { Find(false); return Task.CompletedTask; }));
        DockPanel.SetDock(search, Dock.Top); content.Children.Add(search);
        var footer = new DockPanel { Margin = new(16, 12, 16, 14) };
        file = CardTheme.Button(Text.L("card.log.openFile"), () => { if (Latest?.FilePath is { } path) controller.OpenLinuxFile(this.project.Distribution, path); return Task.CompletedTask; });
        file.Visibility = Visibility.Collapsed;
        terminal = CardTheme.Button(Text.L("windows.logTerminal"), () => { controller.OpenTerminal(this.project, Latest?.FilePath, logs: true, containerName: TerminalLaunch.ContainerFromSource(Latest?.Source)); return Task.CompletedTask; }, "terminal", iconOnly: true);
        terminal.IsEnabled = project.Kind == "ddev";
        var controls = new StackPanel { Orientation = Orientation.Horizontal };
        controls.Children.Add(follow); controls.Children.Add(file); controls.Children.Add(terminal);
        DockPanel.SetDock(controls, Dock.Right); footer.Children.Add(controls); footer.Children.Add(source);
        source.SetBinding(ToolTipProperty, new System.Windows.Data.Binding(nameof(TextBlock.Text)) { Source = source });
        follow.Click += (_, _) => { if (IsFollowing) ScrollToEnd(); };
        DockPanel.SetDock(footer, Dock.Bottom); content.Children.Add(footer); content.Children.Add(lines); Content = content;
        lines.AddHandler(ScrollViewer.ScrollChangedEvent, new ScrollChangedEventHandler((_, args) => {
            if (!applying && Math.Abs(args.VerticalChange) > 0.1 && args.OriginalSource is ScrollViewer scroll)
                follow.IsChecked = scroll.VerticalOffset >= scroll.ScrollableHeight - 16;
        }));
        PreviewKeyDown += (_, args) => {
            if (args.Key == Key.F && Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) { search.Visibility = Visibility.Visible; query.Focus(); query.SelectAll(); args.Handled = true; }
            else if (args.Key == Key.Escape && search.Visibility == Visibility.Visible) { search.Visibility = Visibility.Collapsed; lines.Focus(); args.Handled = true; }
        };
        SourceInitialized += (_, _) => HwndSource.FromHwnd(new WindowInteropHelper(this).Handle)?.AddHook((nint hwnd, int message, nint wparam, nint lparam, ref bool handled) => {
            if (message == 0x232 && live && WindowState == WindowState.Normal) controller.SaveLogPlacement(new(project.Id, Left, Top, ActualWidth, ActualHeight));
            return 0;
        });
        polling.Tick += async (_, _) => { if (WindowVisibility.CanRead(this)) await RefreshAsync(); };
        Loaded += async (_, _) => { DesktopRecovery.EnsureReachable(this); if (live) { polling.Start(); await RefreshAsync(); } };
        Closed += (_, _) => { closed = true; polling.Stop(); lifetime.Cancel(); if (!reading) lifetime.Dispose(); };
    }

    internal void UpdateProject(ProjectReference current)
    {
        if (current.Distribution != project.Distribution || current.Path != project.Path || current.Kind != project.Kind) {
            Latest = null; source.Text = Text.L("card.log.reading"); ChangeView(lines.Clear); file.Visibility = Visibility.Collapsed; terminal.IsEnabled = current.Kind == "ddev";
        }
        project = current;
        heading.Text = project.Title ?? project.Id;
        Title = "DevDeck · " + (project.Title ?? project.Id) + " · " + Text.L("card.log.window.subtitle");
    }
    internal void Apply(WorkerLogs logs)
    {
        Latest = logs; file.Visibility = logs.FilePath is null ? Visibility.Collapsed : Visibility.Visible;
        terminal.IsEnabled = project.Kind == "ddev" || project.Kind == "arc" && TerminalLaunch.ContainerFromSource(logs.Source) is not null || project.Kind == "local" && logs.FilePath is not null;
        source.Text = logs.Source ?? Text.L("card.log.source");
        var text = logs.Lines.Length == 0 ? logs.Detail ?? Text.L("card.log.nothing") : string.Join(Environment.NewLine, logs.Lines);
        if (text == lines.Text) return;
        ChangeView(() => { var offset = lines.VerticalOffset; lines.Text = text; lines.UpdateLayout(); if (IsFollowing) lines.ScrollToEnd(); else lines.ScrollToVerticalOffset(offset); });
    }
    internal Task RefreshAsync() => ReadAsync();
    private async Task ReadAsync()
    {
        if (closed || reading || !IsVisible || WindowState == WindowState.Minimized) return;
        reading = true;
        var requested = project;
        try { if (await logsReader(requested, lifetime.Token) is { } logs && !closed && requested == project) Apply(logs); }
        catch (OperationCanceledException) { }
        catch (IOException error) { if (!closed && requested == project) source.Text = Text.Failure(error); }
        finally { reading = false; if (closed) lifetime.Dispose(); }
    }
    private void ChangeView(Action change)
    {
        var previous = applying; applying = true;
        try { change(); lines.UpdateLayout(); }
        finally { applying = previous; }
    }
    private void ScrollToEnd() => ChangeView(lines.ScrollToEnd);
    private void Find(bool backwards)
    {
        if (query.Text.Length == 0 || lines.Text.Length == 0) return;
        var begin = backwards ? Math.Max(0, lines.SelectionStart - 1) : Math.Min(lines.Text.Length, lines.SelectionStart + lines.SelectionLength);
        var index = backwards ? lines.Text.LastIndexOf(query.Text, begin, StringComparison.CurrentCultureIgnoreCase) : lines.Text.IndexOf(query.Text, begin, StringComparison.CurrentCultureIgnoreCase);
        if (index < 0) index = backwards ? lines.Text.LastIndexOf(query.Text, StringComparison.CurrentCultureIgnoreCase) : lines.Text.IndexOf(query.Text, StringComparison.CurrentCultureIgnoreCase);
        if (index < 0) { source.Text = Text.L("windows.logNoMatch"); return; }
        follow.IsChecked = false;
        ChangeView(() => { lines.Select(index, query.Text.Length); lines.ScrollToLine(lines.GetLineIndexFromCharacterIndex(index)); });
    }
}
