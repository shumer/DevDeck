using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace DevDeck.Windows.App;

internal sealed class DDEVPowerOffDialog : Window
{
    internal Button ConfirmButton { get; } = new() { MinWidth=92, Padding=new(16,8,16,8) };
    internal Button CancelButton { get; } = new() { IsDefault=true, IsCancel=true, MinWidth=92, Padding=new(16,8,16,8), Margin=new(0,0,8,0) };
    internal TextBlock Heading { get; } = new() { FontSize=19, FontWeight=FontWeights.SemiBold, TextWrapping=TextWrapping.Wrap };
    internal TextBlock Detail { get; } = new() { Margin=new(0,12,0,0), Foreground=Brushes.DimGray, TextWrapping=TextWrapping.Wrap };
    internal TextBlock Scope { get; } = new() { Margin=new(0,12,0,0), TextWrapping=TextWrapping.Wrap };
    internal TextBlock Routes { get; } = new() { Margin=new(0,12,0,0), Foreground=Brushes.DimGray, TextWrapping=TextWrapping.Wrap };
    internal IReadOnlyList<string> AffectedNames { get; }
    internal bool WasConfirmed { get; private set; }

    internal static bool Confirm(string[] affectedNames,Window? owner=null)
    {
        var dialog=new DDEVPowerOffDialog(affectedNames,owner);
        dialog.ShowDialog();
        return dialog.WasConfirmed;
    }

    internal DDEVPowerOffDialog(string[] affectedNames,Window? owner=null)
    {
        AffectedNames=Array.AsReadOnly(affectedNames.ToArray());
        Title=Text.L("menu.ddev.confirm.title"); Width=580; SizeToContent=SizeToContent.Height;
        MaxHeight=Math.Max(260,SystemParameters.WorkArea.Height-64);
        MaxWidth=Math.Max(320,SystemParameters.WorkArea.Width-48);
        ResizeMode=ResizeMode.NoResize; WindowStyle=WindowStyle.ToolWindow; ShowInTaskbar=false;
        WindowStartupLocation=owner is null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.CenterOwner;
        Background=Brushes.White; FontFamily=new("Segoe UI"); FontSize=13; Topmost=owner?.Topmost ?? true;
        if (owner is not null) Owner=owner;
        SettingsStyles.AddTo(Resources);
        var settings=Application.Current?.Windows.OfType<SettingsWindow>().FirstOrDefault(window=>window.IsVisible);
        foreach (var type in new[] { typeof(Button) }) {
            var style=owner?.Resources[type] ?? Application.Current?.Resources[type] ?? settings?.Resources[type];
            if (style is Style reusable) Resources[type]=reusable;
        }
        Heading.Text=Title; Detail.Text=Text.L("windows.ddevPowerOff.scope"); Scope.Text=Text.L("menu.ddev.powerOff.tooltip");
        Routes.Text=Text.L("windows.ddevPowerOff.routes",string.Join(", ",AffectedNames));
        ConfirmButton.Content=Text.L("button.powerOff"); CancelButton.Content=Text.L("button.cancel");
        AutomationProperties.SetName(this,Title);
        AutomationProperties.SetHelpText(this,string.Join(Environment.NewLine,Detail.Text,Scope.Text,Routes.Text));
        AutomationProperties.SetName(ConfirmButton,Text.L("button.powerOff"));
        AutomationProperties.SetHelpText(ConfirmButton,string.Join(Environment.NewLine,Detail.Text,Scope.Text,Routes.Text));
        AutomationProperties.SetName(CancelButton,Text.L("button.cancel"));
        var content=new StackPanel { Margin=new(24) };
        foreach (var block in new[] { Heading,Detail,Scope,Routes }) content.Children.Add(block);
        var buttons=new StackPanel { Orientation=Orientation.Horizontal, HorizontalAlignment=HorizontalAlignment.Right, Margin=new(0,20,0,0) };
        buttons.Children.Add(CancelButton); buttons.Children.Add(ConfirmButton); content.Children.Add(buttons);
        Content=new ScrollViewer { Content=content, HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled, VerticalScrollBarVisibility=ScrollBarVisibility.Auto };
        ConfirmButton.Click+=(_,_)=>{ WasConfirmed=true; Close(); };
        CancelButton.Click+=(_,_)=>Cancel();
        PreviewKeyDown+=(_,args)=>{ if (HandleKey(args.Key)) args.Handled=true; };
        Loaded+=(_,_)=>CancelButton.Focus();
    }

    private void Cancel() { WasConfirmed=false; Close(); }
    internal bool HandleKey(Key key)
    {
        if (key is not (Key.Return or Key.Escape)) return false;
        Cancel(); return true;
    }
}
