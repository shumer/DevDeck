using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed class ProjectLinkEditor : StackPanel
{
    internal sealed record LinkRow(TextBox Label, TextBox Template, CheckBox Enabled, ComboBox Kind, Border Panel);
    private readonly List<LinkRow> rows = [];
    private readonly Action changed;
    private readonly Button add;
    private readonly string projectKind;
    internal IReadOnlyList<LinkRow> Rows => rows;
    internal ProjectLink[] Value => rows.Select(row => new ProjectLink(row.Label.Text.Trim(),row.Template.Text.Trim(),row.Enabled.IsChecked == true,(string)row.Kind.SelectedValue)).ToArray();
    private sealed record KindChoice(string ID, string Label);

    internal ProjectLinkEditor(ProjectLink[] links, Action changed, string projectKind = "local")
    {
        this.changed = changed; this.projectKind = projectKind;
        add = SettingsForm.Button(Text.L("project.arc.addLink"), () => {
            var label = Text.L("project.link.new"); var number = 2;
            while (rows.Any(row => row.Label.Text == label)) label = Text.L("project.link.new.numbered",number++);
            AddLink(new(label,"",false,"tool")); changed(); return System.Threading.Tasks.Task.CompletedTask;
        });
        foreach (var link in links) AddLink(link);
        Children.Add(add);
    }

    internal void AddLink(ProjectLink link)
    {
        if (rows.Count >= 30) return;
        var label = new TextBox { Text = link.Label, MinWidth = 100, Padding = new(5,3,5,3) };
        var template = new TextBox { Text = link.Url, Padding = new(5,3,5,3), MinHeight = 28, ToolTip = "https://…" };
        var enabled = new CheckBox { IsChecked = link.Enabled, VerticalAlignment = VerticalAlignment.Center, Margin = new(0,0,8,0) };
        var kind = new ComboBox { ItemsSource = new[] { new KindChoice("tool",Text.L("windows.linkTool")),new("site",Text.L("windows.linkSite")) },
            DisplayMemberPath = "Label", SelectedValuePath = "ID", SelectedValue = link.EffectiveKind, Width = 118, Margin = new(8,0,0,0) };
        AutomationProperties.SetName(label,Text.L("account.name")+": "+link.Label); AutomationProperties.SetName(template,link.Label);
        AutomationProperties.SetName(enabled,link.Label); AutomationProperties.SetName(kind,Text.L("windows.linkKind"));
        var panel = new StackPanel(); var header = new DockPanel { Margin = new(0,0,0,5) };
        var remove = SettingsForm.Button(Text.L("project.link.remove"), () => { RemoveLink(label); changed(); return System.Threading.Tasks.Task.CompletedTask; });
        remove.Margin = new(8,0,0,0); remove.Padding = new(8,2,8,2);
        DockPanel.SetDock(remove,Dock.Right); header.Children.Add(remove); DockPanel.SetDock(kind,Dock.Right); header.Children.Add(kind);
        DockPanel.SetDock(enabled,Dock.Left); header.Children.Add(enabled); header.Children.Add(label); panel.Children.Add(header); panel.Children.Add(template);
        if (ProjectLinks.Defaults(projectKind).Any(item => item.Label == link.Label)) {
            label.IsReadOnly = true; label.Width = projectKind == "arc" ? 110 : 72; label.MinWidth = 0;
            label.BorderThickness = new(0); label.Background = System.Windows.Media.Brushes.Transparent; label.VerticalContentAlignment = VerticalAlignment.Center;
            kind.Visibility = remove.Visibility = Visibility.Collapsed; panel.Children.Remove(template); DockPanel.SetDock(label,Dock.Left); header.Children.Add(template); header.Margin = new(0);
        }
        var border = new Border { Child = panel, Background = System.Windows.Media.Brushes.WhiteSmoke, CornerRadius = new(7), Padding = new(10,8,10,8), Margin = new(0,0,0,6) };
        rows.Add(new(label,template,enabled,kind,border)); Children.Insert(Children.Count > 0 && Children.Contains(add) ? Children.Count-1 : Children.Count,border);
        label.TextChanged += (_,_) => { AutomationProperties.SetName(enabled,label.Text); AutomationProperties.SetName(template,label.Text); changed(); }; template.TextChanged += (_,_) => changed();
        enabled.Click += (_,_) => changed(); kind.SelectionChanged += (_,_) => changed();
        add.IsEnabled = rows.Count < 30;
    }

    internal void RemoveLink(TextBox label)
    {
        var row = rows.Single(item => item.Label == label); rows.Remove(row); Children.Remove(row.Panel); add.IsEnabled = true;
    }
}
