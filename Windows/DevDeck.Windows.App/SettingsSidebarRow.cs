using System;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace DevDeck.Windows.App;

/// Retained sidebar presentation. Configured disabled entries remain selectable.
internal sealed class SettingsSidebarRow : ListBoxItem
{
    internal TextBlock TitleText { get; } = new() { TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
    internal Border IconFrame { get; } = new() { Margin = new(0,0,10,0), VerticalAlignment = VerticalAlignment.Center };
    internal Ellipse Dot { get; } = new() { Width = 7, Height = 7, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, Opacity = 1 };
    private readonly Grid grid = new();
    private string? iconKind;
    private bool dimmed, heading, hint;

    internal SettingsSidebarRow()
    {
        grid.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new() { Width = new(17) });
        grid.Children.Add(IconFrame); Grid.SetColumn(TitleText, 1); grid.Children.Add(TitleText);
        Grid.SetColumn(Dot, 2); grid.Children.Add(Dot);
        Content = grid; HorizontalContentAlignment = HorizontalAlignment.Stretch;
        Selected += (_, _) => RefreshForeground(); Unselected += (_, _) => RefreshForeground();
    }

    internal void Update(string title, string detail, string kind, bool disabled, Brush? dot, bool isHeading = false, bool isHint = false)
    {
        dimmed = disabled; heading = isHeading; hint = isHint;
        IsEnabled = !(heading || hint); Focusable = IsEnabled; Opacity = 1;
        grid.Margin = new(0, heading ? 14 : 0, 0, 0);
        TitleText.Text = heading ? title.ToUpperInvariant() : title;
        RefreshFont();
        TitleText.FontWeight = heading ? FontWeights.SemiBold : FontWeights.Normal;
        IconFrame.Visibility = heading || hint ? Visibility.Collapsed : Visibility.Visible;
        IconFrame.Opacity = dimmed ? .45 : 1;
        if (!(heading || hint) && !string.Equals(iconKind, kind, StringComparison.Ordinal)) {
            IconFrame.Child = BrandMarks.Create(kind, 18, tile: true); iconKind = kind;
        }
        grid.ColumnDefinitions[2].Width = heading || hint ? new(0) : new(17);
        Dot.Fill = dot ?? Brushes.Transparent;
        Dot.Visibility = dot is null || heading || hint ? Visibility.Hidden : Visibility.Visible;
        Dot.Opacity = 1;
        var description = string.Join(" · ", new[] { title, detail, disabled ? Text.L("settings.list.notOnDeck") : "" }.Where(value => value.Length > 0));
        ToolTip = description; AutomationProperties.SetName(this, description); AutomationProperties.SetHelpText(this, detail);
        RefreshForeground();
    }

    private void RefreshForeground() => TitleText.Foreground = IsSelected ? Brushes.White
        : heading ? Brushes.DimGray : hint || dimmed ? SystemColors.GrayTextBrush : Brushes.Black;

    private void RefreshFont() => TitleText.FontSize = FontSize * (heading ? 10.5 : hint ? 12 : 13.5) / 13;
    protected override void OnPropertyChanged(DependencyPropertyChangedEventArgs e)
    {
        base.OnPropertyChanged(e);
        if (e.Property == FontSizeProperty && TitleText is not null) RefreshFont();
    }
}
