using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace DevDeck.Shell;

public sealed class LogWindow : Window, ILogWindow
{
    private readonly string card;
    private readonly LogBuffer buffer = new();
    private readonly LogWindowPlacementStore placements = new();
    private readonly StackPanel linePanel = new();
    private readonly ScrollViewer scroll = new();
    private readonly TextBlock detail = new();
    private readonly TextBlock source = new();
    private readonly TextBox search = new();
    private readonly Button nextSearch = new();
    private readonly List<TextBlock> lineViews = [];
    private bool followsEnd = true;
    private int currentMatch = -1;
    private TextBlock? currentMatchView;

    public LogWindow(string card)
    {
        this.card = card;
        WindowsTheme.EnsureLoaded();
        Width = 720;
        Height = 440;
        MinWidth = 480;
        MinHeight = 260;
        WindowStyle = WindowStyle.SingleBorderWindow;
        ResizeMode = ResizeMode.CanResize;
        ShowInTaskbar = true;
        Background = WindowsTheme.CardBackground(false);
        Foreground = WindowsTheme.Brush("TextPrimary");
        FontFamily = WindowsTheme.Sans;
        Content = BuildContent();
        SourceInitialized += OnSourceInitialized;
        Closing += (_, _) => SavePlacement();
        PreviewKeyDown += OnPreviewKeyDown;
    }

    public LogBuffer Buffer => buffer;
    public TextBox SearchBox => search;
    public Button SearchNextButton => nextSearch;
    public bool DetailIsVisible => detail.Visibility == Visibility.Visible;

    void ILogWindow.Activate()
    {
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }
        _ = Activate();
    }

    public void SetTitle(string title)
    {
        Title = title;
        AutomationProperties.SetName(this, title);
    }

    public void Update(DeckLog log)
    {
        var wasAtEnd = followsEnd;
        var change = buffer.Apply(log);
        source.Text = buffer.Source ?? "";
        detail.Text = buffer.Detail ?? "";
        detail.Visibility = buffer.Lines.Count == 0 && detail.Text.Length > 0
            ? Visibility.Visible
            : Visibility.Collapsed;

        if (change.Reset)
        {
            linePanel.Children.Clear();
            lineViews.Clear();
        }
        foreach (var line in change.Added)
        {
            var view = CreateLine(line);
            lineViews.Add(view);
            linePanel.Children.Add(view);
        }
        if (search.Text.Length > 0)
        {
            RefreshSearch(false);
        }
        if (wasAtEnd)
        {
            Dispatcher.BeginInvoke(scroll.ScrollToEnd);
        }
    }

    public void SetSearchQuery(string value)
    {
        search.Text = value;
    }

    private FrameworkElement BuildContent()
    {
        var root = new DockPanel
        {
            LastChildFill = true,
            Background = WindowsTheme.CardBackground(false),
        };
        var searchBar = new Grid { Margin = new Thickness(12, 10, 12, 8) };
        searchBar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        searchBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        search.Background = WindowsTheme.Brush("ControlFill");
        search.BorderBrush = WindowsTheme.Brush("ControlStroke");
        search.BorderThickness = new Thickness(1);
        search.Foreground = WindowsTheme.Brush("TextPrimary");
        search.CaretBrush = WindowsTheme.Brush("TextPrimary");
        search.FontFamily = WindowsTheme.Sans;
        search.FontSize = 13;
        search.MinHeight = 32;
        search.Padding = new Thickness(8, 5, 8, 5);
        search.Margin = new Thickness(0, 0, 8, 0);
        search.TextChanged += (_, _) => RefreshSearch(true);
        searchBar.Children.Add(search);

        nextSearch.Content = DeckIcons.Create("expand", 14);
        nextSearch.Width = 32;
        nextSearch.Padding = new Thickness(0);
        nextSearch.Style = WindowsTheme.Style("FluentButton");
        nextSearch.Click += (_, _) => SelectNextMatch();
        Grid.SetColumn(nextSearch, 1);
        searchBar.Children.Add(nextSearch);
        DockPanel.SetDock(searchBar, Dock.Top);
        root.Children.Add(searchBar);

        source.FontFamily = WindowsTheme.Mono;
        source.FontSize = 11;
        source.Foreground = WindowsTheme.Brush("TextTertiary");
        source.Margin = new Thickness(14, 8, 14, 10);
        source.TextTrimming = TextTrimming.CharacterEllipsis;
        DockPanel.SetDock(source, Dock.Bottom);
        root.Children.Add(source);

        detail.FontFamily = WindowsTheme.Sans;
        detail.FontSize = 13;
        detail.Foreground = WindowsTheme.Brush("TextSecondary");
        detail.HorizontalAlignment = HorizontalAlignment.Center;
        detail.VerticalAlignment = VerticalAlignment.Center;
        detail.TextWrapping = TextWrapping.Wrap;
        detail.Margin = new Thickness(24);
        detail.Visibility = Visibility.Collapsed;

        scroll.Content = linePanel;
        scroll.Margin = new Thickness(14, 4, 14, 0);
        scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        scroll.HorizontalScrollBarVisibility = ScrollBarVisibility.Auto;
        scroll.ScrollChanged += OnScrollChanged;

        var body = new Grid();
        body.Children.Add(scroll);
        body.Children.Add(detail);
        root.Children.Add(body);
        return root;
    }

    private TextBlock CreateLine(string value)
    {
        return new TextBlock
        {
            Text = value,
            Tag = value,
            FontFamily = WindowsTheme.Mono,
            FontSize = 12,
            Foreground = WindowsTheme.Brush("TextPrimary"),
            TextWrapping = TextWrapping.NoWrap,
            Margin = new Thickness(0, 1, 0, 1),
        };
    }

    private void RefreshSearch(bool resetSelection)
    {
        var query = search.Text;
        if (resetSelection)
        {
            currentMatch = -1;
        }
        currentMatchView = null;
        var matchNumber = 0;
        foreach (var view in lineViews)
        {
            var value = view.Tag as string ?? "";
            view.Inlines.Clear();
            view.Background = Brushes.Transparent;
            if (query.Length == 0)
            {
                view.Visibility = Visibility.Visible;
                view.Inlines.Add(new Run(value));
                continue;
            }

            var matches = MatchIndexes(value, query).ToArray();
            view.Visibility = matches.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
            var offset = 0;
            foreach (var index in matches)
            {
                if (index > offset)
                {
                    view.Inlines.Add(new Run(value[offset..index]));
                }
                var isCurrent = matchNumber == currentMatch;
                view.Inlines.Add(new Run(value.Substring(index, query.Length))
                {
                    Background = WindowsTheme.Brush(isCurrent ? "TonePersonal" : "ToneAttention"),
                    Foreground = Brushes.Black,
                });
                if (isCurrent)
                {
                    currentMatchView = view;
                }
                matchNumber++;
                offset = index + query.Length;
            }
            if (offset < value.Length)
            {
                view.Inlines.Add(new Run(value[offset..]));
            }
        }
    }

    private void SelectNextMatch()
    {
        if (search.Text.Length == 0)
        {
            return;
        }
        var count = lineViews.Sum(view => MatchIndexes(view.Tag as string ?? "", search.Text).Count());
        if (count == 0)
        {
            return;
        }
        currentMatch = (currentMatch + 1) % count;
        RefreshSearch(false);
        currentMatchView?.BringIntoView();
    }

    private static IEnumerable<int> MatchIndexes(string value, string query)
    {
        var start = 0;
        while (start <= value.Length - query.Length)
        {
            var index = value.IndexOf(query, start, StringComparison.CurrentCultureIgnoreCase);
            if (index < 0)
            {
                yield break;
            }
            yield return index;
            start = index + query.Length;
        }
    }

    private void OnScrollChanged(object sender, ScrollChangedEventArgs eventArgs)
    {
        if (eventArgs.ExtentHeightChange == 0)
        {
            followsEnd = scroll.ScrollableHeight - scroll.VerticalOffset < 1;
        }
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs eventArgs)
    {
        if (eventArgs.Key == Key.F && Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
        {
            search.Focus();
            search.SelectAll();
            eventArgs.Handled = true;
        }
        else if (eventArgs.Key == Key.Enter && search.IsKeyboardFocusWithin)
        {
            SelectNextMatch();
            eventArgs.Handled = true;
        }
    }

    private void OnSourceInitialized(object? sender, EventArgs eventArgs)
    {
        NativeMethods.ApplyLogWindowStyles(new WindowInteropHelper(this).Handle);
        if (placements.Read(card) is not { } value)
        {
            return;
        }
        Left = value.Left;
        Top = value.Top;
        Width = Math.Max(MinWidth, value.Width);
        Height = Math.Max(MinHeight, value.Height);
    }

    private void SavePlacement()
    {
        if (!IsLoaded)
        {
            return;
        }
        var bounds = WindowState == WindowState.Normal
            ? new Rect(Left, Top, ActualWidth, ActualHeight)
            : RestoreBounds;
        if (!double.IsFinite(bounds.Left) || !double.IsFinite(bounds.Top) ||
            !double.IsFinite(bounds.Width) || !double.IsFinite(bounds.Height))
        {
            return;
        }
        placements.Write(card, new LogWindowPlacement(bounds.Left, bounds.Top, bounds.Width, bounds.Height));
    }
}
