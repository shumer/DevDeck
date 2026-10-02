using System;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed class ProjectCheckRow : StackPanel, IDisposable
{
    private readonly Func<ProjectReference?> reference;
    private readonly Func<ProjectReference,CancellationToken,Task<ProjectStatus>>? read;
    private readonly CancellationToken lifetime;
    private readonly TextBlock state = new() { FontWeight=FontWeights.SemiBold,TextWrapping=TextWrapping.Wrap };
    private readonly TextBlock detail = new() { Foreground=Brushes.DimGray,FontSize=12,TextWrapping=TextWrapping.Wrap,Margin=new(0,3,0,0) };
    private readonly Button check;
    private readonly DispatcherTimer debounce = new() { Interval=TimeSpan.FromMilliseconds(650) };
    private string? identity;
    private long generation;
    private CancellationTokenSource? pending;
    private bool disposed;
    internal string State => state.Text;
    internal string Detail => detail.Text;
    internal Button CheckButton => check;

    internal ProjectCheckRow(Func<ProjectReference?> reference, Func<ProjectReference,CancellationToken,Task<ProjectStatus>>? read, CancellationToken lifetime)
    {
        this.reference=reference;this.read=read;this.lifetime=lifetime;
        var row=new DockPanel(); check=new Button { Content=Text.L("button.checkNow"),Padding=new(12,7,12,7),HorizontalAlignment=HorizontalAlignment.Left };
        System.Windows.Automation.AutomationProperties.SetName(check,Text.L("button.checkNow"));
        check.Click+=async(_,_)=>await CheckAsync();
        check.Margin=new(12,0,0,0);DockPanel.SetDock(check,Dock.Right);row.Children.Add(check);
        var labels=new StackPanel { VerticalAlignment=VerticalAlignment.Center };labels.Children.Add(state);labels.Children.Add(detail);row.Children.Add(labels);
        Children.Add(new Border { Background=new SolidColorBrush(Color.FromRgb(246,246,246)),CornerRadius=new(8),Padding=new(12),Child=row });
        debounce.Tick += async (_,_) => { debounce.Stop();await CheckAsync(); };
        RefreshIdentity(false);
    }
    private static string? Identity(ProjectReference? value) => value is null ? null :
        value.Kind+"\0"+value.Id+"\0"+value.Distribution+"\0"+value.Path+"\0"+
        (value.Kind=="arc" ? (value.Arc?.LocalURL??"")+"\0"+(value.Arc?.HealthPath??"/release") : (value.StartCommand??"")+"\0"+(value.HealthURL??""));
    internal void RefreshIdentity(bool autoCheck=true)
    {
        if(disposed)return;
        var current=reference();var next=Identity(current);
        if(next==identity && identity is not null)return;
        identity=next;generation++;pending?.Cancel();debounce.Stop();
        state.Text=Text.L(current is null ? "project.notConfigured" : "check.notChecked.yet");
        detail.Text=current is null ? Text.L("project.notConfigured.detail") : "";state.Foreground=Brushes.DimGray;
        check.IsEnabled=current is not null && read is not null;
        if(autoCheck && check.IsEnabled)debounce.Start();
    }
    internal Task CheckOnArrivalAsync() => read is null ? Task.CompletedTask : CheckAsync();
    internal async Task CheckAsync()
    {
        debounce.Stop(); if(disposed||read is null||reference() is not { } current)return;
        var expected=Identity(current);var mine=++generation;pending?.Cancel();pending?.Dispose();
        pending=CancellationTokenSource.CreateLinkedTokenSource(lifetime);var cancellation=pending.Token;
        check.IsEnabled=false;state.Text=Text.L("token.checking");detail.Text="";state.Foreground=Brushes.DimGray;
        try {
            var result=await read(current,cancellation);
            if(disposed||cancellation.IsCancellationRequested||mine!=generation||expected!=Identity(reference()))return;
            if(result.ProjectID!=current.Id)throw new WorkerException("protocolMismatch","Settings check belongs to another project.");
            var summary=result.CheckSummary;
            state.Text=summary?.State??Text.L("card.state."+result.State);detail.Text=summary?.Detail??result.NotAnswering??"";
            state.Foreground=summary?.Tone switch { "good"=>Brushes.ForestGreen,"bad"=>Brushes.Firebrick,"busy"=>Brushes.DarkGoldenrod,_=>Brushes.DimGray };
        } catch(OperationCanceledException) { }
        catch(Exception error) { if(!disposed&&mine==generation&&expected==Identity(reference())) { state.Text=Text.L("windows.refreshFailed");detail.Text=Text.Failure(error);state.Foreground=Brushes.Firebrick; } }
        finally { if(!disposed&&mine==generation)check.IsEnabled=reference() is not null; }
    }
    public void Dispose() { if(disposed)return;disposed=true;generation++;debounce.Stop();pending?.Cancel();pending?.Dispose();check.IsEnabled=false; }
}
