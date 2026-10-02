using System;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// The entered page is used only for this explicit browser opening, never saved with the account.
internal sealed class EnterpriseTokenAddressDialog : Window
{
    internal TextBox AddressInput { get; } = new() { MinHeight=34, Padding=new(8,6,8,6), MaxLength=2048 };
    internal Button OpenButton { get; } = new() { MinWidth=110, Padding=new(16,8,16,8) };
    internal Button CancelButton { get; } = new() { IsCancel=true, IsDefault=true, MinWidth=92, Padding=new(16,8,16,8), Margin=new(0,0,8,0) };
    internal string? SelectedAddress { get; private set; }
    internal string APIEndpoint { get; }
    internal static string? Show(string apiEndpoint,Window? owner=null)
    {
        var dialog=new EnterpriseTokenAddressDialog(apiEndpoint,owner); dialog.ShowDialog(); return dialog.SelectedAddress;
    }
    internal EnterpriseTokenAddressDialog(string apiEndpoint,Window? owner=null)
    {
        _=AccountTokenActions.Creation("github",apiEndpoint); APIEndpoint=apiEndpoint;
        Title=Text.L("windows.enterpriseTokenPage"); Width=540; SizeToContent=SizeToContent.Height;
        MinWidth=360; MaxWidth=Math.Max(360,SystemParameters.WorkArea.Width-48);
        MaxHeight=Math.Max(300,SystemParameters.WorkArea.Height-64);
        ResizeMode=ResizeMode.NoResize; WindowStyle=WindowStyle.ToolWindow; ShowInTaskbar=false;
        WindowStartupLocation=owner is null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.CenterOwner;
        Background=Brushes.White; FontFamily=new("Segoe UI"); FontSize=13; Topmost=owner?.Topmost ?? true;
        if (owner is not null) Owner=owner;
        SettingsStyles.AddTo(Resources);
        foreach(var type in new[]{typeof(TextBox),typeof(Button)})
            if ((owner?.Resources[type] ?? Application.Current?.Resources[type]) is Style style) Resources[type]=style;
        var panel=new StackPanel { Margin=new(24) };
        panel.Children.Add(new TextBlock { Text=Title, FontSize=19, FontWeight=FontWeights.SemiBold, TextWrapping=TextWrapping.Wrap });
        var detail=Text.L("windows.enterpriseTokenPageDetail");
        panel.Children.Add(new TextBlock { Text=detail, Margin=new(0,12,0,18), Foreground=Brushes.DimGray, TextWrapping=TextWrapping.Wrap });
        panel.Children.Add(new TextBlock { Text=Text.L("windows.apiEndpoint")+": "+APIEndpoint, Margin=new(0,0,0,16), TextWrapping=TextWrapping.Wrap, Foreground=Brushes.DimGray });
        panel.Children.Add(new TextBlock { Text=Text.L("windows.enterpriseTokenAddress"), Margin=new(0,0,0,6), TextWrapping=TextWrapping.Wrap });
        AutomationProperties.SetAutomationId(AddressInput,"account.token.enterpriseAddress");
        AutomationProperties.SetName(AddressInput,Text.L("windows.enterpriseTokenAddress"));
        AutomationProperties.SetHelpText(AddressInput,detail); panel.Children.Add(AddressInput);
        OpenButton.Content=Text.L("windows.openTokenPage"); CancelButton.Content=Text.L("button.cancel");
        AutomationProperties.SetName(OpenButton,Text.L("windows.openTokenPage"));
        AutomationProperties.SetName(CancelButton,Text.L("button.cancel"));
        var buttons=new StackPanel { Orientation=Orientation.Horizontal, HorizontalAlignment=HorizontalAlignment.Right, Margin=new(0,20,0,0) };
        buttons.Children.Add(CancelButton); buttons.Children.Add(OpenButton); panel.Children.Add(buttons);
        Content=new ScrollViewer { Content=panel, VerticalScrollBarVisibility=ScrollBarVisibility.Auto, HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled };
        AddressInput.TextChanged+=(_,_)=>OpenButton.IsEnabled=ValidAddress() is not null;
        OpenButton.Click+=(_,_)=>TryOpen(); CancelButton.Click+=(_,_)=>{SelectedAddress=null;Close();};
        PreviewKeyDown+=(_,args)=>{if (HandleKey(args.Key,Keyboard.Modifiers)) args.Handled=true;};
        Loaded+=(_,_)=>AddressInput.Focus(); OpenButton.IsEnabled=false;
    }
    private string? ValidAddress()
    {
        try { return AccountTokenActions.EnterpriseCreationAddress(AddressInput.Text); }
        catch (System.IO.InvalidDataException) { return null; }
    }
    internal bool TryOpen()
    {
        if (ValidAddress() is not { } address) return false;
        SelectedAddress=address; Close(); return true;
    }
    internal bool HandleKey(Key key,ModifierKeys modifiers)
    {
        if (modifiers!=ModifierKeys.None) return false;
        if (key==Key.Escape || key==Key.Return) { SelectedAddress=null;Close();return true; }
        return false;
    }
}
