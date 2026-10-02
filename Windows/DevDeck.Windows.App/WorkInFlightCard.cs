using System;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Retained presentation owner. The controller's shared pass owns periodic scan admission.
internal sealed class WorkInFlightCard : Window
{
    private readonly DeckController controller;
    private readonly Func<CancellationToken,Task<WorkInFlightSnapshot>>? snapshotReader;
    private readonly Action<CheckoutEntry> terminalOpener;
    private readonly CancellationTokenSource lifetime=new();
    private readonly StackPanel body=new();
    private readonly StackPanel rows=new();
    private readonly TextBlock heading;
    private readonly TextBlock foldedNote=new() { FontSize=10, Foreground=CardTheme.Secondary, TextTrimming=TextTrimming.CharacterEllipsis };
    private readonly TextBlock state=new() { FontSize=24, FontWeight=FontWeights.SemiBold, Margin=new(0,10,0,8), TextWrapping=TextWrapping.Wrap };
    private readonly TextBlock verdict=new() { FontSize=11, Foreground=CardTheme.Amber, VerticalAlignment=VerticalAlignment.Center };
    private readonly TextBlock footer=new() { FontSize=10, Foreground=CardTheme.Quiet, Margin=new(0,9,0,0), TextWrapping=TextWrapping.Wrap };
    private readonly TextBlock diagnostic=new() { FontSize=11, Foreground=CardTheme.Amber, Margin=new(0,7,0,0), TextWrapping=TextWrapping.Wrap, Visibility=Visibility.Collapsed };
    private readonly TextBlock timestamp=new() { Text="--:--:--", FontSize=10, FontFamily=new("Consolas"), Foreground=CardTheme.Quiet, VerticalAlignment=VerticalAlignment.Center };
    private readonly Button expand,refreshButton,settingsButton,collapseButton;
    private readonly MenuItem compactMenu=new() { Tag="compact" };
    private Task? refreshing;
    private bool closed,deckVisible=true,collapsed,expanded,floating,checking;
    private string? failure;
    private nint handle;
    internal WorkInFlightSnapshot? Latest { get; private set; }
    internal string CardID=>CheckoutCatalog.CardID;
    internal bool DeckVisible=>deckVisible;
    internal bool CanRefresh=>deckVisible && !closed;
    internal bool IsExpanded=>expanded;
    internal bool ModeApplied { get; private set; }

    internal WorkInFlightCard(DeckController controller,WorkInFlightSettings settings,bool live=true,
        Func<CancellationToken,Task<WorkInFlightSnapshot>>? snapshotReader=null,Action<CheckoutEntry>? terminalOpener=null)
    {
        this.controller=controller; this.snapshotReader=snapshotReader;
        this.terminalOpener=terminalOpener ?? controller.OpenWorkInFlightTerminal;
        collapsed=settings.Collapsed;
        Title="DevDeck · "+Text.L("card.title.workInFlight"); Width=CardTheme.Width; SizeToContent=SizeToContent.Height;
        Left=settings.X; Top=settings.Y; Foreground=CardTheme.Ink; FontFamily=new("Segoe UI");
        WindowStyle=WindowStyle.None; ResizeMode=ResizeMode.NoResize; AllowsTransparency=true;
        Background=Brushes.Transparent; ShowInTaskbar=false; ShowActivated=false;
        var panel=new StackPanel { Margin=new(14,12,14,12) }; var header=new DockPanel();
        collapseButton=CardTheme.Button(Text.L("menu.card.collapse"),()=>{ ToggleCollapsed(); return Task.CompletedTask; },"collapse",iconOnly:true);
        collapseButton.Background=Brushes.Transparent; collapseButton.Margin=new(0); DockPanel.SetDock(collapseButton,Dock.Right); header.Children.Add(collapseButton);
        settingsButton=CardTheme.Button(Text.L("menu.card.settings"),()=>{ controller.ShowSettings("cards"); return Task.CompletedTask; },"settings",iconOnly:true);
        settingsButton.Background=Brushes.Transparent; settingsButton.Margin=new(0); DockPanel.SetDock(settingsButton,Dock.Right); header.Children.Add(settingsButton);
        refreshButton=CardTheme.Button(Text.L("menu.refresh"),controller.RefreshAllAsync); refreshButton.Content=timestamp;
        refreshButton.Padding=new(0); refreshButton.Background=Brushes.Transparent; DockPanel.SetDock(refreshButton,Dock.Right); header.Children.Add(refreshButton);
        heading=CardTheme.Heading(Text.L("card.title.workInFlight").ToUpperInvariant());
        heading.MouseLeftButtonDown+=(_,args)=> {
            if (args.ClickCount==2) { ToggleCollapsed(); return; }
            if (args.LeftButton==MouseButtonState.Pressed && !controller.Settings.Locked) { DragMove(); controller.SavePosition(CardID,Left,Top); }
        };
        var titleGroup=new StackPanel { VerticalAlignment=VerticalAlignment.Center }; titleGroup.Children.Add(heading); titleGroup.Children.Add(foldedNote); header.Children.Add(titleGroup);
        panel.Children.Add(header); panel.Children.Add(body);
        var headline=new DockPanel(); DockPanel.SetDock(verdict,Dock.Right); headline.Children.Add(verdict); headline.Children.Add(state);
        body.Children.Add(headline); body.Children.Add(rows);
        expand=CardTheme.Button(Text.L("card.showMore",1),()=>{ SetExpanded(!expanded); return Task.CompletedTask; });
        expand.HorizontalAlignment=HorizontalAlignment.Center; expand.Margin=new(0,7,0,0); expand.Visibility=Visibility.Collapsed;
        body.Children.Add(expand); body.Children.Add(footer); body.Children.Add(diagnostic);
        Content=CardTheme.Frame(panel); SetCollapsed(collapsed); Render();
        ContextMenu=new ContextMenu(); compactMenu.Click+=(_,_)=>ToggleCollapsed();
        ContextMenu.Opened+=(_,_)=>PopulateContextMenu(); PopulateContextMenu();
        SourceInitialized+=(_,_)=> {
            handle=new WindowInteropHelper(this).Handle;
            HwndSource.FromHwnd(handle)?.AddHook((nint hwnd,int message,nint wparam,nint lparam,ref bool handled)=> {
                if (message==0x21 && !floating) { handled=true; return 3; } return 0;
            });
            ApplyMode(controller.Settings.Floating);
        };
        Deactivated+=(_,_)=>{ if (!floating) ApplyMode(false); };
        Loaded+=(_,_)=>{ if (deckVisible) DesktopRecovery.EnsureReachable(this); };
        Closed+=(_,_)=>{ closed=true; lifetime.Cancel(); if (ContextMenu is not null) ContextMenu.IsOpen=false; };
    }

    internal Task RefreshAsync()
    {
        if (!CanRefresh) return Task.CompletedTask;
        return refreshing is { IsCompleted:false } ? refreshing : refreshing=ReadAsync();
    }
    private async Task ReadAsync()
    {
        SetChecking();
        try {
            var snapshot=await (snapshotReader is null ? controller.FetchWorkInFlightAsync(lifetime.Token) : snapshotReader(lifetime.Token));
            if (!closed) ApplySnapshot(snapshot);
        } catch (OperationCanceledException) when (closed || lifetime.IsCancellationRequested) { }
        catch (Exception error) when (error is System.IO.IOException or InvalidOperationException or OperationCanceledException) {
            if (!closed) ApplyFailure(error);
        }
    }
    internal void ApplySnapshot(WorkInFlightSnapshot snapshot)
    {
        if (closed) return;
        Latest=snapshot; checking=snapshot.Checking; failure=null; Render();
    }
    internal void ApplyFailure(Exception error)
    {
        if (closed) return;
        checking=false; failure=Text.Failure(error);
        if (Latest is { } previous) Latest=previous with { Checking=false,Stale=true };
        Render();
    }
    internal void SetChecking(bool value=true) { if (closed) return; checking=value; Render(); }
    internal void Invalidate() { if (Latest is { } previous) Latest=previous with { Stale=true }; Render(); }
    private void Render()
    {
        var snapshot=Latest; var projection=CheckoutPresentation.Project(snapshot?.Entries ?? []);
        var allFailed=snapshot is { SelectedCount:>0 } && projection.Watched==0 && projection.Failures>0 && !checking;
        var noQualifiedReads=snapshot is { SelectedCount:>0 } && projection.Watched==0 && projection.Failures==0;
        var unavailable=snapshot is null && failure is not null || noQualifiedReads && !checking && (snapshot?.Stale==true || snapshot?.CheckedAt is not null);
        var awaiting=snapshot is null || noQualifiedReads || checking && snapshot.CheckedAt is null && projection.Watched==0;
        var note=checking ? Text.L("windows.wif.checking") : allFailed ? Text.L("windows.wif.readFailed",projection.Failures)
            : unavailable ? Text.L("windows.wif.unavailable") : snapshot is null || noQualifiedReads ? Text.L("windows.connecting") : CheckoutWords.Collapsed(projection,Text.Resources);
        if (!checking && snapshot?.Stale==true) note+=" · "+Text.L("windows.wif.stale");
        foldedNote.Text=note; foldedNote.ToolTip=note; foldedNote.Foreground=allFailed || unavailable || projection.Urgent || snapshot?.Stale==true ? CardTheme.Amber : CardTheme.Secondary;
        state.Inlines.Clear(); state.FontSize=allFailed || unavailable || awaiting ? 14 : 24;
        if (allFailed || unavailable || awaiting) state.Text=note;
        else {
            state.Inlines.Add(new System.Windows.Documents.Run(projection.InFlight.ToString()) { FontSize=30 });
            state.Inlines.Add(new System.Windows.Documents.Run(" "+Text.L(projection.InFlight==0 ? "card.wif.clean" : "card.wif.inFlight.word")) { FontSize=12, Foreground=CardTheme.Secondary });
        }
        state.Foreground=allFailed || unavailable ? CardTheme.Amber : CardTheme.Ink;
        verdict.Text=projection.Unpushed>0 ? Text.L("card.wif.unpushed",projection.Unpushed) : ""; verdict.ToolTip=verdict.Text;
        rows.Children.Clear();
        foreach (var entry in CheckoutPresentation.CardRows(projection,expanded)) rows.Children.Add(Row(entry));
        expand.Visibility=projection.Rows.Length>3 ? Visibility.Visible : Visibility.Collapsed;
        expand.Content=Text.L(expanded ? "card.showLess" : "card.showMore",Math.Max(0,projection.Rows.Length-3));
        AutomationProperties.SetName(expand,expand.Content.ToString());
        footer.Text=snapshot is null ? "" : CheckoutWords.Footer(projection,Text.Resources); footer.ToolTip=footer.Text;
        timestamp.Text=snapshot?.CheckedAt is { } time ? DateTimeOffset.FromUnixTimeSeconds((long)time).LocalDateTime.ToString("HH:mm:ss") : "--:--:--";
        var partial=projection.Failures==0 ? "" : projection.Watched==0 ? Text.L("windows.wif.readFailed",projection.Failures)
            : Text.L("windows.wif.partial",projection.Watched,projection.Failures);
        var status=checking ? Text.L("windows.wif.checking") : failure ?? (snapshot?.Stale==true ? Text.L("windows.wif.stale") : partial);
        diagnostic.Text=status; diagnostic.Visibility=status.Length==0 ? Visibility.Collapsed : Visibility.Visible; diagnostic.ToolTip=status;
        ToolTip=string.Join(" · ",note,footer.Text,status); AutomationProperties.SetHelpText(this,ToolTip.ToString());
    }
    private Button Row(CheckoutEntry entry)
    {
        var value=entry.Result.State!;
        var summary=CheckoutWords.Summary(value,Text.Resources); var full=string.Join(" · ",entry.Reference.Title,value.Branch,summary);
        var button=CardTheme.Button(full,()=>{ if (!closed && deckVisible) terminalOpener(entry); return Task.CompletedTask; });
        button.Tag=entry; button.ToolTip=full; button.Margin=new(0); button.Padding=new(0,6,0,6);
        button.Background=Brushes.Transparent; button.HorizontalContentAlignment=HorizontalAlignment.Stretch;
        AutomationProperties.SetName(button,full); AutomationProperties.SetHelpText(button,entry.Reference.Distribution+" · "+entry.Reference.Path);
        var grid=new Grid();
        grid.ColumnDefinitions.Add(new() { Width=new(14) }); grid.ColumnDefinitions.Add(new() { Width=new(4,GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new() { Width=new(3,GridUnitType.Star) }); grid.ColumnDefinitions.Add(new() { Width=new(3,GridUnitType.Star) });
        grid.Children.Add(new System.Windows.Shapes.Ellipse { Width=6,Height=6,Fill=value.Urgent ? CardTheme.Amber : CardTheme.Quiet,VerticalAlignment=VerticalAlignment.Center,HorizontalAlignment=HorizontalAlignment.Left });
        var title=new TextBlock { Text=entry.Reference.Title, FontSize=11.5, Foreground=CardTheme.Ink, TextTrimming=TextTrimming.CharacterEllipsis, VerticalAlignment=VerticalAlignment.Center,Margin=new(0,0,6,0),ToolTip=entry.Reference.Title };
        Grid.SetColumn(title,1); grid.Children.Add(title);
        var branchPanel=new DockPanel { Margin=new(0,0,6,0) }; var glyph=CardTheme.Icon("branch",CardTheme.Quiet); DockPanel.SetDock(glyph,Dock.Left); branchPanel.Children.Add(glyph);
        branchPanel.Children.Add(new TextBlock { Text=value.Branch,FontSize=10.5,FontFamily=new("Consolas"),Foreground=CardTheme.Quiet,TextTrimming=TextTrimming.CharacterEllipsis,VerticalAlignment=VerticalAlignment.Center,Margin=new(4,0,0,0),ToolTip=value.Branch });
        Grid.SetColumn(branchPanel,2); grid.Children.Add(branchPanel);
        var facts=new TextBlock { Text=summary, FontSize=10.5,FontFamily=new("Consolas"),Foreground=value.Urgent ? CardTheme.Amber : CardTheme.Secondary,TextTrimming=TextTrimming.CharacterEllipsis,VerticalAlignment=VerticalAlignment.Center,ToolTip=summary };
        Grid.SetColumn(facts,3); grid.Children.Add(facts); button.Content=grid; return button;
    }
    internal void SetExpanded(bool value) { expanded=value; Render(); }
    internal void SetCollapsed(bool value)
    {
        collapsed=value; body.Visibility=value ? Visibility.Collapsed : Visibility.Visible; foldedNote.Visibility=value ? Visibility.Visible : Visibility.Collapsed;
        heading.Text=Text.L("card.title.workInFlight"); if (!value) heading.Text=heading.Text.ToUpperInvariant();
        heading.FontSize=value ? 14 : 11.5; heading.Foreground=value ? CardTheme.Ink : CardTheme.Secondary;
        settingsButton.Visibility=refreshButton.Visibility=value ? Visibility.Collapsed : Visibility.Visible;
        CardTheme.CollapseControl(collapseButton,value); compactMenu.Header=Text.L(value ? "menu.card.showWhole" : "menu.card.collapse");
    }
    private void ToggleCollapsed() { SetCollapsed(!collapsed); controller.SaveCollapsed(CardID,collapsed); }
    internal void SetDeckVisible(bool value)
    {
        if (closed) return;
        deckVisible=value;
        if (!value) { if (ContextMenu is not null) ContextMenu.IsOpen=false; if (IsVisible) Hide(); return; }
        if (!IsVisible) Show(); ApplyMode(controller.Settings.Floating);
    }
    private void PopulateContextMenu()
    {
        if (ContextMenu is not { } menu) return; menu.Items.Clear();
        menu.Items.Add(new MenuItem { Header=Text.L("card.title.workInFlight"),Tag="header",IsEnabled=false });
        compactMenu.Header=Text.L(collapsed ? "menu.card.showWhole" : "menu.card.collapse"); compactMenu.IsEnabled=!closed; menu.Items.Add(compactMenu);
        void Item(string tag,string key,Func<Task> action) {
            var item=new MenuItem { Header=Text.L(key),Tag=tag,IsEnabled=!closed }; item.Click+=async (_,_)=>await controller.RunMenuAsync(action); menu.Items.Add(item);
        }
        Item("hide","menu.card.hide",()=>controller.SetWIFVisibleAsync(false));
        Item("settings","menu.card.settings",()=>{ controller.ShowSettings("cards"); return Task.CompletedTask; });
        menu.Items.Add(new Separator());
        var locked=new MenuItem { Header=Text.L("menu.lock"),Tag="lock",IsCheckable=true,IsChecked=controller.Settings.Locked,IsEnabled=!closed };
        locked.Click+=(_,_)=>controller.SetLocked(!controller.Settings.Locked); menu.Items.Add(locked);
        Item("tidy","menu.tidy",()=>controller.ArrangeAsync()); Item("refresh","menu.refresh",controller.RefreshAllAsync);
    }
    internal void ApplyMode(bool value)
    {
        floating=value; Topmost=value;
        if (handle==0) return; WidgetWindow.ExcludeFromSwitcher(handle);
        ModeApplied=SetWindowPos(handle,value ? (nint)(-1) : (nint)1,0,0,0,0,0x0001|0x0002|0x0010);
    }
    internal void Summon()
    {
        if (closed || !deckVisible) return; Show(); WindowState=WindowState.Normal; ApplyMode(controller.Settings.Floating);
        if (!controller.Settings.Floating && handle!=0) {
            SetWindowPos(handle,0,0,0,0,0,0x0001|0x0002|0x0010);
            var retreat=new DispatcherTimer { Interval=TimeSpan.FromSeconds(5) }; retreat.Tick+=(_,_)=>{ retreat.Stop(); if (!closed) ApplyMode(false); }; retreat.Start();
        }
    }
    [DllImport("user32.dll",SetLastError=true)] private static extern bool SetWindowPos(nint window,nint after,int x,int y,int cx,int cy,uint flags);
}
