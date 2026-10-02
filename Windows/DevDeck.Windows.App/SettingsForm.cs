using System;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Markup;
using System.Windows.Threading;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal abstract class SettingsForm : UserControl, IDisposable
{
    protected readonly DeckController Controller;
    protected readonly bool Live;
    protected readonly CancellationTokenSource Lifetime = new();
    protected readonly TextBlock Message = new() { TextWrapping = TextWrapping.Wrap, Margin = new(0, 18, 0, 0), Foreground = Brushes.DimGray };
    private readonly DispatcherTimer debounce = new() { Interval = TimeSpan.FromMilliseconds(650) };
    private readonly SemaphoreSlim saveGate = new(1,1);
    private bool dirty, disposed, saveFailed;
    private long editRevision;
    private int autosavePauses;
    protected bool IsDisposed => disposed;
    internal bool FormDisposed => disposed;
    internal bool HasUncommittedChanges => dirty || saveFailed;
    protected bool Autosaves;
    protected SettingsForm(DeckController controller, bool live)
    {
        Controller = controller; Live = live;
        debounce.Tick += async (_, _) => { debounce.Stop(); await FlushAsync(); };
    }
    protected void Changed() { editRevision++; if (Live && Autosaves && !disposed) { dirty = true; debounce.Stop(); if (autosavePauses == 0) debounce.Start(); } }
    protected void Watch(TextBox field) => field.TextChanged += (_, _) => Changed();
    protected void Watch(ComboBox field) => field.SelectionChanged += (_, _) => Changed();
    protected void Watch(CheckBox field) => field.Click += (_, _) => Changed();
    public async Task FlushAsync()
    {
        debounce.Stop(); if (autosavePauses > 0 || disposed) return;
        await saveGate.WaitAsync();
        try { if (autosavePauses > 0) return; if(saveFailed&&!disposed)dirty=true; while (dirty && !disposed && autosavePauses == 0) { dirty = false; await SaveMetadataQuietlyAsync(); } }
        finally { saveGate.Release(); }
    }
    // Stop both new and already-queued autosaves before waiting for an admitted save
    // to finish. The lease never holds saveGate across an external read-only action.
    protected async Task<IDisposable> PauseAutosaveAsync(CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        if (disposed) throw new OperationCanceledException(cancellation);
        autosavePauses++; debounce.Stop();
        var lease = new AutosavePause(this);
        try {
            await saveGate.WaitAsync(cancellation);
            saveGate.Release();
            cancellation.ThrowIfCancellationRequested();
            if (disposed) throw new OperationCanceledException(cancellation);
            return lease;
        } catch { lease.Dispose(); throw; }
    }
    private void ResumeAutosave()
    {
        autosavePauses--;
        if (autosavePauses == 0 && !disposed && Live && Autosaves && dirty) {
            debounce.Stop(); debounce.Start();
        }
    }
    private sealed class AutosavePause(SettingsForm owner) : IDisposable
    {
        private SettingsForm? current = owner;
        public void Dispose() { var retained = current; current = null; retained?.ResumeAutosave(); }
    }
    private async Task SaveMetadataQuietlyAsync()
    {
        var revision = editRevision;
        try { await SaveMetadataAsync(); saveFailed=false; if (!disposed && revision == editRevision) Message.Text = ""; }
        catch (OperationCanceledException) { saveFailed=true; }
        catch (Exception error) { saveFailed=true; if (!disposed && revision == editRevision) { Message.Text = Text.Failure(error); Message.Foreground = Brushes.Firebrick; } }
    }
    protected abstract Task SaveMetadataAsync();
    protected async Task ExecuteAsync(Func<Task> action)
    {
        if (disposed) return;
        IsEnabled = false; Message.Text = "";
        try { await action(); }
        catch (OperationCanceledException) { }
        catch (Exception error) { if (!disposed) { Message.Text = Text.Failure(error); Message.Foreground = Brushes.Firebrick; } }
        finally { if (!disposed) IsEnabled = true; }
    }
    public virtual void Dispose() { if (disposed) return; disposed = true; debounce.Stop(); Lifetime.Cancel(); }
    internal static StackPanel Page(string title)
    {
        var panel = new StackPanel { Margin = new(32, 26, 32, 28) };
        panel.Children.Add(new TextBlock { Text = title, FontSize = 24, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap }); return panel;
    }
    internal static void Section(Panel panel, string title) => panel.Children.Add(new TextBlock { Text = title, FontSize = 15, FontWeight = FontWeights.SemiBold, Margin = new(0, 24, 0, 8), TextWrapping = TextWrapping.Wrap });
    internal static TextBlock Note(Panel panel, string text)
    {
        var note = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DimGray, FontSize = 12, Margin = new(0, 8, 0, 12) }; panel.Children.Add(note); return note;
    }
    internal static void Field(Panel panel, string title, UIElement input)
    {
        var row = new Grid { Margin = new(0,1,0,0) };
        row.ColumnDefinitions.Add(new() { Width = new GridLength(150) }); row.ColumnDefinitions.Add(new());
        row.Children.Add(new TextBlock { Text = title, TextWrapping = TextWrapping.Wrap, Margin = new(0,5,12,5), VerticalAlignment = VerticalAlignment.Center });
        if (input is Control control) { control.Padding = new(5,3,5,3); control.MinHeight = 28; System.Windows.Automation.AutomationProperties.SetName(control, title); }
        Grid.SetColumn(input,1); row.Children.Add(input);
        panel.Children.Add(new Border { Background = new SolidColorBrush(Color.FromRgb(246,246,246)), CornerRadius = new(6), Padding = new(10,5,10,5), Margin = new(0,1,0,0), Child = row });
    }
    private static readonly ControlTemplate SwitchTemplate = (ControlTemplate)XamlReader.Parse("""
        <ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="CheckBox">
          <Grid Background="Transparent"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <ContentPresenter Margin="0,0,16,0" VerticalAlignment="Center"/>
            <Border x:Name="track" Grid.Column="1" Width="42" Height="22" CornerRadius="11" Background="#D4D4D4" BorderBrush="Transparent" BorderThickness="1">
              <Ellipse x:Name="thumb" Width="18" Height="18" Margin="1" HorizontalAlignment="Left" Fill="White"/>
            </Border>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True"><Setter TargetName="track" Property="Background" Value="#3478F4"/><Setter TargetName="thumb" Property="HorizontalAlignment" Value="Right"/></Trigger>
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="track" Property="BorderBrush" Value="#133B87"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
        """);
    internal static CheckBox Toggle(string title, bool enabled)
    {
        var field = new CheckBox { Content = new TextBlock { Text = title, TextWrapping = TextWrapping.Wrap }, IsChecked = enabled,
            Template = SwitchTemplate, Padding = new(10), Margin = new(10,8,10,8), HorizontalContentAlignment = HorizontalAlignment.Stretch };
        System.Windows.Automation.AutomationProperties.SetName(field,title); return field;
    }
    internal static StackPanel Group(Panel parent)
    {
        var rows = new StackPanel(); parent.Children.Add(new Border { Background = new SolidColorBrush(Color.FromRgb(246,246,246)), CornerRadius = new(10), Padding = new(0,4,0,4), Child = rows }); return rows;
    }
    internal static Button Button(string title, Func<Task> action)
    {
        var button = new Button { Content = new TextBlock { Text = title, TextWrapping = TextWrapping.Wrap }, Padding = new(12, 7, 12, 7), Margin = new(0, 6, 8, 4), HorizontalAlignment = HorizontalAlignment.Left };
        System.Windows.Automation.AutomationProperties.SetName(button, title);
        button.Click += async (_, _) => { button.IsEnabled = false; try { await action(); } catch (Exception error) { MessageBox.Show(Text.Failure(error), "DevDeck", MessageBoxButton.OK, MessageBoxImage.Information); } finally { button.IsEnabled = true; } }; return button;
    }
    protected async Task DiscoverAsync(ComboBox distribution, string? selected = null)
    {
        if (!Live) return;
        try {
            var names = await WslDistributions.DiscoverAsync(Lifetime.Token);
            if (Lifetime.IsCancellationRequested) return;
            distribution.ItemsSource = names; distribution.SelectedItem = selected ?? (names.Length > 0 ? names[0] : null);
        } catch (OperationCanceledException) { } catch (Exception error) { Message.Text = Text.Failure(error); }
    }
}
