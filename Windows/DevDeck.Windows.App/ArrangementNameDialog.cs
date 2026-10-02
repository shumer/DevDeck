using System;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace DevDeck.Windows.App;

/// A name-only prompt. Persistence belongs to the caller after an explicit Save.
internal sealed class ArrangementNameDialog : Window
{
    internal TextBox NameInput { get; } = new() { MaxLength=128, MinHeight=34, Padding=new(8,6,8,6), AcceptsReturn=false, AcceptsTab=false };
    internal Button SaveButton { get; } = new() { IsDefault=true, MinWidth=92, Padding=new(16,8,16,8) };
    internal Button CancelButton { get; } = new() { IsCancel=true, MinWidth=92, Padding=new(16,8,16,8), Margin=new(0,0,8,0) };
    internal TextBlock Heading { get; } = new() { FontSize=19, FontWeight=FontWeights.SemiBold, TextWrapping=TextWrapping.Wrap };
    internal TextBlock Detail { get; } = new() { Margin=new(0,12,0,20), Foreground=Brushes.DimGray, TextWrapping=TextWrapping.Wrap };
    internal TextBlock Placeholder { get; } = new() { Margin=new(10,7,10,7), Foreground=Brushes.Gray, IsHitTestVisible=false, TextTrimming=TextTrimming.CharacterEllipsis };
    internal string? SelectedName { get; private set; }

    internal static string? Show(Window? owner=null)
    {
        var dialog = new ArrangementNameDialog(owner);
        dialog.ShowDialog();
        return dialog.SelectedName;
    }

    internal ArrangementNameDialog(Window? owner=null)
    {
        Title=Text.L("arrangements.save.title"); Width=480; SizeToContent=SizeToContent.Height;
        MaxHeight=Math.Max(260,SystemParameters.WorkArea.Height-64);
        MaxWidth=Math.Max(320,SystemParameters.WorkArea.Width-48);
        ResizeMode=ResizeMode.NoResize; WindowStyle=WindowStyle.ToolWindow; ShowInTaskbar=false;
        WindowStartupLocation=owner is null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.CenterOwner;
        Background=Brushes.White; FontFamily=new("Segoe UI"); FontSize=13; Topmost=owner?.Topmost ?? true;
        if (owner is not null) Owner=owner;
        SettingsStyles.AddTo(Resources);
        var settings = Application.Current?.Windows.OfType<SettingsWindow>().FirstOrDefault(window=>window.IsVisible);
        foreach (var type in new[] { typeof(TextBox), typeof(Button) }) {
            // Only supplied dictionaries override the rounded fallback, not system theme styles.
            var style=owner?.Resources[type] ?? Application.Current?.Resources[type] ?? settings?.Resources[type];
            if (style is Style reusable) Resources[type]=reusable;
        }
        Heading.Text=Title; Detail.Text=Text.L("arrangements.save.detail"); Placeholder.Text=Text.L("arrangements.name.placeholder");
        SaveButton.Content=Text.L("button.save"); CancelButton.Content=Text.L("button.cancel");
        AutomationProperties.SetName(NameInput,Text.L("account.name"));
        AutomationProperties.SetHelpText(NameInput,Detail.Text);
        AutomationProperties.SetName(SaveButton,Text.L("button.save")); AutomationProperties.SetName(CancelButton,Text.L("button.cancel"));
        var content=new StackPanel { Margin=new(24) }; content.Children.Add(Heading); content.Children.Add(Detail);
        var input=new Grid(); input.Children.Add(NameInput); input.Children.Add(Placeholder); content.Children.Add(input);
        var buttons=new StackPanel { Orientation=Orientation.Horizontal, HorizontalAlignment=HorizontalAlignment.Right, Margin=new(0,20,0,0) };
        buttons.Children.Add(CancelButton); buttons.Children.Add(SaveButton); content.Children.Add(buttons);
        Content=new ScrollViewer { Content=content, HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled, VerticalScrollBarVisibility=ScrollBarVisibility.Auto };
        NameInput.TextChanged+=(_,_)=>UpdateValidity();
        SaveButton.Click+=(_,_)=>TrySave(); CancelButton.Click+=(_,_)=>Cancel();
        PreviewKeyDown+=(_,args)=>{ if (HandleKey(args.Key,Keyboard.Modifiers)) args.Handled=true; };
        Loaded+=(_,_)=>{ NameInput.Focus(); NameInput.SelectAll(); };
        UpdateValidity();
    }

    private string? ValidName()
    {
        var raw=NameInput.Text;
        if (raw.Any(char.IsControl)) return null;
        var name=raw.Trim();
        return name.Length is >0 and <=128 ? name : null;
    }
    private void UpdateValidity()
    {
        SaveButton.IsEnabled=ValidName() is not null;
        Placeholder.Visibility=NameInput.Text.Length==0 ? Visibility.Visible : Visibility.Collapsed;
    }
    internal bool TrySave()
    {
        if (ValidName() is not { } name) return false;
        SelectedName=name; Close(); return true;
    }
    private void Cancel() { SelectedName=null; Close(); }
    internal bool HandleKey(Key key,ModifierKeys modifiers)
    {
        if (modifiers!=ModifierKeys.None) return false;
        if (key==Key.Return) { TrySave(); return true; }
        if (key==Key.Escape) { Cancel(); return true; }
        return false;
    }
}
