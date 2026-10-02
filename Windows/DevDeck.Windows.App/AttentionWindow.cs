using System;
using System.ComponentModel;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed class AttentionWindow : Window
{
    private bool closed;

    internal AttentionWindow(DeckController controller, AttentionItem[] items,
        Func<AttentionItem, AttentionChoice, Task<bool>>? actionHandler = null)
    {
        var execute = actionHandler ?? controller.ExecuteAttentionChoiceAsync;
        Title = "DevDeck · " + Text.L("windows.attentionAll", items.Length);
        Width = 620; Height = 580; MaxHeight = SystemParameters.WorkArea.Height - 64;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Closed += (_, _) => closed = true;
        SettingsStyles.AddTo(Resources);
        var panel = new StackPanel { Margin = new(24) };
        string? tier = null;
        if (items.Length == 0) panel.Children.Add(new TextBlock { Text = Text.L("attention.summary.none") });
        foreach (var item in items) {
            if (tier != item.Tier) {
                tier = item.Tier;
                panel.Children.Add(new TextBlock { Text = Text.L("attention.tier." + tier), FontSize = 20, FontWeight = FontWeights.SemiBold, Margin = new(0, 12, 0, 10) });
            }
            var content = new StackPanel();
            content.Children.Add(new TextBlock { Text = item.Title, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
            content.Children.Add(new TextBlock { Text = item.Subtitle, Foreground = Brushes.DimGray, TextWrapping = TextWrapping.Wrap, Margin = new(0, 4, 0, 0) });
            var primary = AttentionChoices.Primary(item);
            var alternate = AttentionChoices.Alternate(item);
            var button = new Button { Content = content, Tag = item, IsEnabled = primary.Enabled, Padding = new(12),
                Margin = new(0, 0, 0, 8), HorizontalContentAlignment = HorizontalAlignment.Stretch, ToolTip = item.Subtitle };
            AutomationProperties.SetName(button, item.Title + ", " + item.Subtitle);
            panel.Children.Add(button);
            Button? alternateButton = null;
            if (alternate.Enabled) {
                var caption = Text.L(alternate.Kind == "read" ? "menu.markRead" : "menu.dismiss", item.Title);
                alternateButton = new Button { Content = caption, Tag = alternate, IsEnabled = true,
                    HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Right,
                    Margin = new(0, 0, 0, 8), Padding = new(8, 6, 8, 6), ToolTip = caption + ", " + item.Subtitle };
                // Titles can contain underscores and long Unicode names. Render plain,
                // wrapping text instead of interpreting the title as an access key.
                var templateText = new FrameworkElementFactory(typeof(TextBlock));
                templateText.SetBinding(TextBlock.TextProperty, new Binding());
                templateText.SetValue(TextBlock.TextWrappingProperty, TextWrapping.Wrap);
                alternateButton.ContentTemplate = new DataTemplate { VisualTree = templateText };
                AutomationProperties.SetName(alternateButton, caption + ", " + item.Subtitle);
                AutomationProperties.SetHelpText(alternateButton, item.Subtitle);
                panel.Children.Add(alternateButton);
            }
            var failure = new TextBlock { Foreground = new SolidColorBrush(Color.FromRgb(160, 54, 54)),
                TextWrapping = TextWrapping.Wrap, Margin = new(0, 0, 0, 8), Visibility = Visibility.Collapsed };
            panel.Children.Add(failure);
            var busy = false;
            var completed = false;
            async Task ChooseAsync(AttentionChoice choice)
            {
                if (closed || busy || completed || !choice.Enabled) return;
                busy = true; button.IsEnabled = false;
                if (alternateButton is not null) alternateButton.IsEnabled = false;
                failure.Text = ""; failure.Visibility = Visibility.Collapsed;
                try {
                    var succeeded = await execute(item, choice);
                    // Primary navigation remains usable. Only a successful read/dismiss
                    // retires this captured row; false admission is not a completed read.
                    if (!closed) completed = succeeded && choice.IsAlternate;
                } catch (Exception error) when (error is IOException or InvalidOperationException or Win32Exception) {
                    if (!closed) {
                        failure.Text = Text.Failure(error); failure.Visibility = Visibility.Visible;
                        AutomationProperties.SetName(failure, failure.Text);
                    }
                } finally {
                    if (!closed) {
                        busy = false; button.IsEnabled = !completed && primary.Enabled;
                        if (alternateButton is not null) alternateButton.IsEnabled = !completed && alternate.Enabled;
                    }
                }
            }
            button.Click += async (_, _) => await ChooseAsync(primary);
            if (alternateButton is not null) alternateButton.Click += async (_, _) => await ChooseAsync(alternate);
        }
        Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }
}
