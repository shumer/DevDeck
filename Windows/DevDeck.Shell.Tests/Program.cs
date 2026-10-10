using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using DevDeck.Shell;

namespace DevDeck.Shell.Tests;

public static class Program
{
    private static int passed;
    private static int failed;

    [STAThread]
    public static int Main(string[] arguments)
    {
        var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        if (arguments.Length == 2 && arguments[0] == "--capture-w5")
        {
            W5Screenshots.Generate(Path.GetFullPath(arguments[1]));
            Application.Current.Shutdown();
            return 0;
        }
        if (arguments.Length == 4 && arguments[0] == "--capture-reference")
        {
            ReferenceScreenshots.Generate(
                Path.GetFullPath(arguments[1]),
                Path.GetFullPath(arguments[2]),
                double.Parse(arguments[3], System.Globalization.CultureInfo.InvariantCulture));
            Application.Current.Shutdown();
            return 0;
        }
        if (arguments.Length == 3 && arguments[0] == "--capture-golden-cards")
        {
            GoldenCardScreenshots.Generate(
                Path.GetFullPath(arguments[1]),
                Path.GetFullPath(arguments[2]));
            Application.Current.Shutdown();
            return 0;
        }
        if (arguments.Length is 2 or 3 && arguments[0] == "--state-preview")
        {
            return StatePreview.Show(
                application,
                Path.GetFullPath(arguments[1]),
                arguments.Length == 3 ? arguments[2] : "rest");
        }
        Run("all golden sessions parse and render", GoldenSessionsParseAndRender);
        Run("commands return without changing their bytes", CommandsKeepTheirBytes);
        Run("panel frames are applied as received", PanelFramesAreAppliedAsReceived);
        Run("windows do not activate or enter task switchers", WindowIsNonactivating);
        Run("project header uses icon buttons and engine tooltips", ProjectHeaderUsesIconButtons);
        Run("project header reflects the log state", ProjectHeaderReflectsLogState);
        Run("all exported brand marks render", ExportedBrandMarksRender);
        Run("card materials have acrylic and solid variants", CardMaterialsHaveBothVariants);
        Run("button styles expose keyboard focus", ButtonStylesExposeKeyboardFocus);
        Run("styled cards use the reference measurements", StyledCardsUseReferenceMeasurements);
        Run("review rows stretch and keep their separators", ReviewRowsStretchAndKeepSeparators);
        Run("project metadata and place chip use their specified styles", ProjectMetadataAndPlaceChipUseSpecifiedStyles);
        Run("the expander uses the Fluent chevron", ExpanderUsesFluentChevron);
        Run("middle trimming preserves both ends", MiddleTrimmingPreservesBothEnds);
        Run("every golden card uses the Windows frame", EveryGoldenCardUsesWindowsFrame);
        Run("inbox rows and footer use the styled model parts", InboxRowsAndFooterUseStyledModelParts);
        Run("action variants and work rows use styled layouts", ActionVariantsAndWorkRowsUseStyledLayouts);
        Run("project kinds share chips actions and collapsed rows", ProjectKindsShareStyledParts);
        Run("expanded lists report a larger measured height", ExpandedListsReportLargerHeight);
        Run("runtime menu builds every entry kind", RuntimeMenuBuildsEveryEntryKind);
        Run("menu clicks send the exact command", MenuClicksSendExactCommand);
        Run("menu prompts fill only the command name", MenuPromptsFillOnlyTheCommandName);
        Run("cancelled confirmations send no command", CancelledConfirmationsSendNoCommand);
        Run("menu alternates send their own command", MenuAlternatesSendTheirOwnCommand);
        Run("card windows accept their context menu", CardWindowsAcceptTheirContextMenu);
        Run("tray status creates every icon tier", TrayStatusCreatesEveryIconTier);
        Console.WriteLine();
        Console.WriteLine($"{passed} passed, {failed} failed");
        Application.Current.Shutdown();
        return failed == 0 ? 0 : 1;
    }

    private static void GoldenSessionsParseAndRender()
    {
        var kinds = new HashSet<string>(StringComparer.Ordinal);
        var cards = 0;
        foreach (var path in GoldenPaths())
        {
            var revision = 0;
            var lineNumber = 0;
            foreach (var line in File.ReadLines(path))
            {
                lineNumber++;
                DeckEvent message;
                try
                {
                    message = DeckEvent.Parse(line);
                }
                catch (JsonException exception)
                {
                    throw new Exception($"{Path.GetFileName(path)}:{lineNumber}", exception);
                }
                Equal(2, message.ProtocolVersion);
                True(message.Revision > revision);
                revision = message.Revision;
                if (message.Event != "card.changed")
                {
                    continue;
                }

                var model = message.Model ?? throw new Exception();
                True(CardRenderer.CanRender(model));
                var kind = model.EnumerateObject().Single();
                kinds.Add(kind.Name);
                var view = CardRenderer.Create(model, _ => { });
                view.Measure(new Size(352, double.PositiveInfinity));
                True(view.DesiredSize.Height > 0);
                cards++;
            }
        }

        True(cards > 0);
        Equal(
            "actions,inbox,project,reviewList,workInFlight",
            string.Join(',', kinds.Order(StringComparer.Ordinal)));
    }

    private static void CommandsKeepTheirBytes()
    {
        var commands = 0;
        foreach (var path in GoldenPaths())
        {
            foreach (var line in File.ReadLines(path))
            {
                var message = DeckEvent.Parse(line);
                if (message.Model is not { } model)
                {
                    continue;
                }

                foreach (var command in Commands(model))
                {
                    var intent = ProtocolWriter.Command("test", command);
                    using var document = JsonDocument.Parse(intent);
                    Equal(command.Json, document.RootElement.GetProperty("command").GetRawText());
                    commands++;
                }
            }
        }

        True(commands > 0);
    }

    private static void PanelFramesAreAppliedAsReceived()
    {
        var expected = FirstPanelFrame();
        var window = CreateWindow();
        window.Show();
        window.ApplyFrame(expected);
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        var actual = window.CurrentFrame();
        Equal(expected.Length, actual.Length);
        for (var index = 0; index < expected.Length; index++)
        {
            Equal(expected[index], actual[index]);
        }
        window.Close();
    }

    private static void WindowIsNonactivating()
    {
        var before = NativeMethods.GetForegroundWindow();
        var window = CreateWindow();
        window.Show();
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        var styles = NativeMethods.GetWindowLongPtr(window.Handle, NativeMethods.ExtendedStyleIndex);
        True((styles & NativeMethods.ToolWindowStyle) != 0);
        True((styles & NativeMethods.NoActivateStyle) != 0);
        Equal(NativeMethods.RoundedWindowCorners, NativeMethods.GetWindowCornerPreference(window.Handle));
        Equal(
            NativeMethods.TransientWindowBackdrop,
            NativeMethods.GetWindowAttribute(window.Handle, NativeMethods.SystemBackdropType));
        Equal(1, NativeMethods.GetWindowAttribute(window.Handle, NativeMethods.ImmersiveDarkMode));
        True(!window.ShowActivated);
        True(!window.ShowInTaskbar);
        if (before != 0)
        {
            Equal(before, NativeMethods.GetForegroundWindow());
        }
        window.Close();
    }

    private static void ProjectHeaderUsesIconButtons()
    {
        DeckCommand? invoked = null;
        var withoutPhone = CardRenderer.Create(ProjectModel(false, null), value => invoked = value);
        var log = Button(withoutPhone, "project.header.log");
        Equal(24.0, log.Width);
        Equal(24.0, log.Height);
        Equal("open the log in a window", log.ToolTip);
        True(log.Content is TextBlock text && text.Text == DeckIcons.Text("log"));
        True(ButtonOrNull(withoutPhone, "project.header.phone") is null);
        log.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
        Equal("{\"toggleLogs\":{\"_0\":\"project.sample\"}}", invoked?.Json);

        var withPhone = CardRenderer.Create(ProjectModel(false, "https://example.invalid"), _ => { });
        var phone = Button(withPhone, "project.header.phone");
        Equal(24.0, phone.Width);
        Equal(24.0, phone.Height);
        Equal("open this on your phone", phone.ToolTip);
        True(phone.Content is TextBlock phoneText && phoneText.Text == DeckIcons.Text("phone"));
    }

    private static void ProjectHeaderReflectsLogState()
    {
        var off = Button(CardRenderer.Create(ProjectModel(false, null), _ => { }), "project.header.log");
        var on = Button(CardRenderer.Create(ProjectModel(true, null), _ => { }), "project.header.log");
        True(!Equals(off.Foreground, on.Foreground));
        True(!Equals(off.Background, on.Background));
        True(on.Content is TextBlock onIcon && Equals(onIcon.Foreground, WindowsTheme.Brush("ToneGood")));
    }

    private static void ExportedBrandMarksRender()
    {
        True(BrandMarks.Names.Count >= 10);
        foreach (var name in BrandMarks.Names)
        {
            var mark = BrandMarks.Create(name, 16);
            mark.Measure(new Size(16, 16));
            True(mark.DesiredSize.Width > 0);
            True(mark.DesiredSize.Height > 0);
        }
    }

    private static void CardMaterialsHaveBothVariants()
    {
        var acrylic = (SolidColorBrush)WindowsTheme.CardBackground(true);
        var solid = (SolidColorBrush)WindowsTheme.CardBackground(false);
        Equal((byte)168, acrylic.Color.A);
        Equal((byte)255, solid.Color.A);
        Equal(Color.FromRgb(43, 43, 47), solid.Color);
    }

    private static void ButtonStylesExposeKeyboardFocus()
    {
        foreach (var style in new[] { "FluentButton", "HeaderIconButton", "RowButton", "ChipButton", "ExpanderButton", "LinkButton" })
        {
            var button = new Button
            {
                Content = "Sample",
                Style = WindowsTheme.Style(style),
            };
            var window = new Window
            {
                Width = 200,
                Height = 100,
                Content = button,
                ShowInTaskbar = false,
            };
            window.Show();
            True(button.Focusable);
            True(button.Focus());
            window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
            var focusBorder = (Border)button.Template.FindName("FocusBorder", button);
            True(focusBorder.BorderBrush is SolidColorBrush brush && brush.Color.A > 0);
            window.Close();
        }
    }

    private static void StyledCardsUseReferenceMeasurements()
    {
        var review = RenderSample("github.pullRequests");
        var project = RenderSample("project.windows");
        var reviewFrame = (Border)review;
        Equal(new Thickness(16, 14, 16, 14), reviewFrame.Padding);
        Equal(352.0, review.ActualWidth);
        True(Descendants(review).OfType<DockPanel>().Any(row => row.Height == 20));
        True(Descendants(project).OfType<DockPanel>().Any(row => row.Height == 20));

        var eyebrows = Descendants(review).OfType<TrackedTextBlock>().Concat(
            Descendants(project).OfType<TrackedTextBlock>()).Where(text => text.TrackingEm > 0).ToArray();
        True(eyebrows.Length >= 2);
        True(eyebrows.All(text => text.FontSize == 11 && text.FontWeight == FontWeights.SemiBold));
        True(eyebrows.All(text => text.TrackingEm == 0.07));

        var reviewText = Descendants(review).OfType<TextBlock>().ToArray();
        True(reviewText.Any(text => text.Text == "4" && text.FontSize == 30 && text.FontWeight == FontWeights.SemiBold));
        True(reviewText.Any(text => text.Text == "open" && text.FontSize == 14));
        var projectText = Descendants(project).OfType<TextBlock>().ToArray();
        True(projectText.Any(text => text.Text == "stopped" && text.FontSize == 22 && text.FontWeight == FontWeights.SemiBold));
        True(reviewText.Any(text => text.Text == "2 repos · 1 org" && text.FontSize == 12 && Equals(text.Foreground, WindowsTheme.Brush("TextTertiary"))));
    }

    private static void ReviewRowsStretchAndKeepSeparators()
    {
        var review = RenderSample("github.pullRequests");
        var rowFrames = Descendants(review).OfType<Grid>()
            .Where(grid => grid.Height == 30 && grid.Children.OfType<Button>().Any())
            .ToArray();
        Equal(4, rowFrames.Length);
        True(rowFrames.All(frame => frame.Children.OfType<Button>().Single().HorizontalContentAlignment == HorizontalAlignment.Stretch));
        Equal(3, rowFrames.Count(frame => frame.Children.OfType<Border>().Any(border => border.Height == 1)));

        var firstButton = rowFrames[0].Children.OfType<Button>().Single();
        var content = (Grid)firstButton.Content;
        var title = content.Children.OfType<TextBlock>().Single(text => text.Text == "Fix the feed");
        var trailing = content.Children.OfType<TextBlock>().Single(text => text.Text == "CR");
        True(title.ActualWidth > 80);
        var trailingRight = trailing.TranslatePoint(new Point(trailing.ActualWidth, 0), content).X;
        True(Math.Abs(trailingRight - content.ActualWidth) < 1);
    }

    private static void ProjectMetadataAndPlaceChipUseSpecifiedStyles()
    {
        var project = RenderSample("project.wsl");
        var leading = Descendants(project).OfType<TextBlock>().Single(text => text.Text == "bun · next · feed");
        Equal(12.0, leading.FontSize);
        Equal(WindowsTheme.Sans, leading.FontFamily);
        Equal(WindowsTheme.Brush("TextSecondary"), leading.Foreground);

        var trailing = Descendants(project).OfType<TrackedTextBlock>().Single(text => text.Text == "bun run dev");
        Equal(11.0, trailing.FontSize);
        Equal(WindowsTheme.Mono, trailing.FontFamily);
        Equal(DeckTextTrimming.Middle, trailing.Trimming);
        Equal(WindowsTheme.Brush("TextTertiary"), trailing.Foreground);

        var place = Descendants(project).OfType<Grid>().Single(grid =>
            grid.Children.OfType<TextBlock>().Any(text => text.Text == "WSL · Ubuntu-24.04"));
        Equal(24.0, place.Height);
        var outline = place.Children.OfType<System.Windows.Shapes.Rectangle>().Single();
        True(outline.Fill is null);
        Equal("2,2", string.Join(',', outline.StrokeDashArray.Select(value => value.ToString(System.Globalization.CultureInfo.InvariantCulture))));
        var placeText = place.Children.OfType<TextBlock>().Single();
        Equal(WindowsTheme.Brush("TextPrimary"), placeText.Foreground);
    }

    private static void ExpanderUsesFluentChevron()
    {
        var review = RenderSample("github.pullRequests");
        var expander = Descendants(review).OfType<Button>().Single(button =>
            button.Content is StackPanel panel && panel.Children.OfType<TextBlock>().Any(text => text.Text == "show less"));
        var content = (StackPanel)expander.Content;
        var icon = content.Children.OfType<TextBlock>().Single(text => text.FontFamily.Source == "Segoe Fluent Icons");
        Equal(DeckIcons.Text("collapse"), icon.Text);
    }

    private static void MiddleTrimmingPreservesBothEnds()
    {
        var text = new TrackedTextBlock
        {
            Text = "beginning-middle-ending",
            Foreground = WindowsTheme.Brush("TextPrimary"),
            FontFamily = WindowsTheme.Mono,
            FontSize = 11,
            Trimming = DeckTextTrimming.Middle,
        };
        text.Measure(new Size(60, 30));
        text.Arrange(new Rect(0, 0, 60, text.DesiredSize.Height));
        var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap(
            60,
            30,
            96,
            96,
            PixelFormats.Pbgra32);
        bitmap.Render(text);
        True(text.RenderedText.StartsWith("b", StringComparison.Ordinal));
        True(text.RenderedText.EndsWith("g", StringComparison.Ordinal));
        True(text.RenderedText.Contains('…'));
    }

    private static void EveryGoldenCardUsesWindowsFrame()
    {
        var kinds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var cardId in new[]
        {
            "github.pullRequests",
            "github.inbox",
            "github.actions",
            "gitlab.mergeRequests",
            "local.workInFlight",
            "arc.project.paper",
            "ddev.project.shop",
            "project.feed",
        })
        {
            foreach (var model in GoldenModels(cardId))
            {
                kinds.Add(model.EnumerateObject().Single().Name);
                var frame = (Border)Render(model);
                True(frame.Background is SolidColorBrush brush && brush.Color != Colors.White);
                if (frame.Height == 44)
                {
                    Equal(new Thickness(16, 6, 16, 6), frame.Padding);
                }
                else
                {
                    Equal(new Thickness(16, 14, 16, 14), frame.Padding);
                }
            }
        }
        Equal("actions,inbox,project,reviewList,workInFlight", string.Join(',', kinds.Order()));
    }

    private static void InboxRowsAndFooterUseStyledModelParts()
    {
        var inbox = Render(GoldenModels("github.inbox").Last(model =>
            JsonModel.Object(model.EnumerateObject().Single().Value, "content", out _)));
        var text = Descendants(inbox).OfType<TextBlock>().ToArray();
        True(text.Any(item => item.Text == "review" && item.FontSize == 11));
        True(text.Any(item => item.Text == "Review the parser" && item.FontWeight == FontWeights.SemiBold));
        True(text.Any(item => item.Text == "now" && Equals(item.Foreground, WindowsTheme.Brush("TextTertiary"))));
        var links = Descendants(inbox).OfType<Button>()
            .Where(button => button.Content is string)
            .Select(button => (string)button.Content)
            .ToArray();
        True(links.Contains("Mark as read, except the 2 for you"));
        True(links.Contains("Mark all 3 as read"));
    }

    private static void ActionVariantsAndWorkRowsUseStyledLayouts()
    {
        var runs = Render(GoldenModels("github.actions").Last(model =>
            JsonModel.Object(model.EnumerateObject().Single().Value, "content", out _)));
        True(Descendants(runs).OfType<TextBlock>().Any(text => text.Text == "50" && text.FontSize == 30));
        True(Descendants(runs).OfType<TextBlock>().Any(text => text.Text == "site · ci" && text.FontSize == 13));

        var repositories = JsonSerializer.SerializeToElement(new
        {
            actions = new
            {
                isCollapsed = false,
                title = "GitHub · actions",
                content = new
                {
                    repositories = new
                    {
                        title = "No recent runs",
                        detail = "Two repositories were checked.",
                        link = new
                        {
                            title = "Open workflow runs",
                            help = "Open workflow runs",
                            command = new { openURL = new { _0 = "https://example.invalid/actions" } },
                        },
                    },
                },
            },
        });
        var repositoryCard = Render(repositories);
        True(Descendants(repositoryCard).OfType<TextBlock>().Any(text => text.Text == "No recent runs"));
        True(Descendants(repositoryCard).OfType<Button>().Any(button => Equals(button.Content, "Open workflow runs")));

        var work = JsonSerializer.SerializeToElement(new
        {
            workInFlight = new
            {
                isCollapsed = false,
                title = "Work in flight",
                timestamp = "04:00:00",
                count = 1,
                unit = "in flight",
                rows = new[]
                {
                    new
                    {
                        id = "sample",
                        tone = "attention",
                        title = "Sample checkout",
                        branch = "feature/sample",
                        summary = "2 changes",
                        help = "Sample checkout",
                        command = new { openCheckout = new { _0 = "sample" } },
                    },
                },
                footer = new { leading = "1 checkout watched", isStale = false },
            },
        });
        var workCard = Render(work);
        var branch = Descendants(workCard).OfType<TextBlock>().Single(text => text.Text == "feature/sample");
        Equal(WindowsTheme.Mono, branch.FontFamily);
        Equal(WindowsTheme.Brush("LinkInfo"), branch.Foreground);
        True(Descendants(workCard).OfType<TextBlock>().Any(text => text.Text == "2 changes"));
    }

    private static void ProjectKindsShareStyledParts()
    {
        var arc = Render(GoldenModels("arc.project.paper").Last());
        var tool = Descendants(arc).OfType<Button>().Single(button => Equals(button.Content, "PageBuilder"));
        Equal(WindowsTheme.Brush("LinkInfo"), tool.Foreground);
        var local = Descendants(arc).OfType<TextBlock>().First(text => text.Text == "Local site");
        Equal(WindowsTheme.Brush("ToneGood"), local.Foreground);

        var ddev = Render(GoldenModels("ddev.project.shop").Last());
        var docker = Descendants(ddev).OfType<Button>().Single(button =>
            AutomationProperties.GetName(button) == "Start Docker");
        True(docker.Content is StackPanel dockerContent && dockerContent.Children.Count == 2);

        var collapsed = (Border)Render(GoldenModels("project.feed").Last(model =>
            JsonModel.Bool(model.EnumerateObject().Single().Value, "isCollapsed")));
        Equal(44.0, collapsed.ActualHeight);
        // The row carries Start and the log, so the model sends it without a note: the title is
        // the only text.
        True(Descendants(collapsed).OfType<TextBlock>().Any(text => text.Text == "Feed"));
        True(Descendants(collapsed).OfType<TextBlock>().All(text => text.Text != "stopped"));
        True(Descendants(collapsed).OfType<Button>().All(button => button.Width == 28));

        var pullRequestModel = GoldenModels("github.pullRequests").Last().EnumerateObject().Single().Value;
        True(JsonModel.Object(pullRequestModel, "collapsed", out var pullRequestCollapsedModel));
        var pullRequestCollapsed = (Border)Arrange(WindowsCardRenderer.Stopped(pullRequestCollapsedModel, _ => { }));
        var pullRequestNote = Descendants(pullRequestCollapsed).OfType<TrackedTextBlock>().Single();
        Equal(DeckTextTrimming.End, pullRequestNote.Trimming);
        Equal(HorizontalAlignment.Right, pullRequestNote.HorizontalAlignment);
        var pullRequestRow = Descendants(pullRequestCollapsed).OfType<Grid>().Single();
        Equal(GridUnitType.Star, pullRequestRow.ColumnDefinitions[3].Width.GridUnitType);
        Equal(GridLength.Auto, pullRequestRow.ColumnDefinitions[2].Width);
        var collapsedBitmap = new System.Windows.Media.Imaging.RenderTargetBitmap(
            352,
            44,
            96,
            96,
            PixelFormats.Pbgra32);
        collapsedBitmap.Render(pullRequestCollapsed);
        Equal(pullRequestNote.Text, pullRequestNote.RenderedText);

        var ddevModel = GoldenModels("ddev.project.shop").Last().EnumerateObject().Single().Value;
        True(JsonModel.Object(ddevModel, "collapsed", out var ddevCollapsedModel));
        var ddevCollapsed = (Border)Arrange(WindowsCardRenderer.Stopped(ddevCollapsedModel, _ => { }));
        var title = Descendants(ddevCollapsed).OfType<TextBlock>().Single(text => text.Text == "shop");
        True(title.ActualWidth > 0);
    }

    private static void ExpandedListsReportLargerHeight()
    {
        var models = GoldenModels("github.pullRequests");
        var compactModel = models.First(model =>
            JsonModel.Object(model.EnumerateObject().Single().Value, "content", out _) &&
            !JsonModel.Bool(model.EnumerateObject().Single().Value, "isExpanded"));
        var expandedModel = models.First(model =>
            JsonModel.Bool(model.EnumerateObject().Single().Value, "isExpanded"));
        var compact = Render(compactModel);
        var expanded = Render(expandedModel);
        True(expanded.ActualHeight > compact.ActualHeight);

        var measurements = new List<CardMeasurement>();
        var window = new CardWindow("github.pullRequests", measurements.Add, _ => { }, _ => { });
        window.Show();
        window.Update(compactModel);
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        window.Update(expandedModel);
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        Equal(2, measurements.Count);
        True(measurements[1].Size[1] > measurements[0].Size[1]);
        window.Close();
    }

    private static void RuntimeMenuBuildsEveryEntryKind()
    {
        var value = RuntimeMenuValue("runtime-menu-en.expected.jsonl", "menu", last: true);
        var entries = DeckMenuEntryModel.ParseList(value);
        True(entries.Any(entry => entry.Kind == DeckMenuEntryKind.Item));
        True(entries.Any(entry => entry.Kind == DeckMenuEntryKind.Header));
        True(entries.Any(entry => entry.Kind == DeckMenuEntryKind.Separator));
        True(entries.Any(entry => entry.Kind == DeckMenuEntryKind.Submenu));
        var presenter = new MenuPresenter(_ => { });
        presenter.Update(value);
        Equal(entries.Count, presenter.View.Items.Count);
    }

    private static void MenuClicksSendExactCommand()
    {
        var value = RuntimeMenuValue("runtime-menu-en.expected.jsonl", "menu", last: false);
        var expected = DeckMenuEntryModel.ParseList(value)
            .Where(entry => entry.Kind == DeckMenuEntryKind.Item)
            .Select(entry => entry.Item)
            .First(item => item?.Command is not null)?.Command ?? throw new Exception();
        DeckCommand? sent = null;
        var presenter = new MenuPresenter(command => sent = command);
        presenter.Update(value);
        var menuItem = presenter.View.Items.OfType<MenuItem>()
            .First(item => item.Tag is DeckMenuItemModel model && model.Command?.Json == expected.Json);
        menuItem.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
        Equal(expected.Json, sent?.Json);
    }

    private static void MenuPromptsFillOnlyTheCommandName()
    {
        var value = RuntimeMenuValue("runtime-menu-en.expected.jsonl", "menu", last: false);
        var promptItem = Flatten(DeckMenuEntryModel.ParseList(value))
            .Select(entry => entry.Item)
            .Single(item => item?.Prompt is not null) ?? throw new Exception();
        var dialogs = new RecordingDialogs { PromptAnswer = "Desk" };
        DeckCommand? sent = null;
        new MenuActionRunner(dialogs, command => sent = command).Invoke(promptItem, false);
        Equal("{\"saveArrangement\":{\"name\":\"Desk\"}}", sent?.Json);
    }

    private static void CancelledConfirmationsSendNoCommand()
    {
        var value = RuntimeMenuValue("runtime-menu-en.expected.jsonl", "menu", last: false);
        var confirmationItem = Flatten(DeckMenuEntryModel.ParseList(value))
            .Select(entry => entry.Item)
            .Single(item => item?.Confirmation is not null) ?? throw new Exception();
        var dialogs = new RecordingDialogs { ConfirmationAnswer = false };
        DeckCommand? sent = null;
        new MenuActionRunner(dialogs, command => sent = command).Invoke(confirmationItem, false);
        True(sent is null);
    }

    private static void MenuAlternatesSendTheirOwnCommand()
    {
        var value = RuntimeMenuValue("runtime-menu-en.expected.jsonl", "menu", last: true);
        var alternateItem = Flatten(DeckMenuEntryModel.ParseList(value))
            .Select(entry => entry.Item)
            .First(item => item?.Alternate is not null) ?? throw new Exception();
        DeckCommand? sent = null;
        new MenuActionRunner(new RecordingDialogs(), command => sent = command).Invoke(alternateItem, true);
        Equal(alternateItem.Alternate?.Command.Json, sent?.Json);
    }

    private static void CardWindowsAcceptTheirContextMenu()
    {
        var value = RuntimeMenuValue("runtime-menu-en.expected.jsonl", "projectMenu", last: true);
        var window = CreateWindow();
        window.UpdateMenu(value);
        Equal(DeckMenuEntryModel.ParseList(value).Count, window.ContextMenu?.Items.Count);
        window.Close();
    }

    private static void TrayStatusCreatesEveryIconTier()
    {
        foreach (var tier in new int?[] { null, 0, 1, 2, 3 })
        {
            foreach (var light in new[] { false, true })
            {
                using var icon = TrayIconFactory.Create(tier, light);
                Equal(new System.Drawing.Size(32, 32), icon.Size);
            }
        }
    }

    private static IEnumerable<DeckMenuEntryModel> Flatten(IReadOnlyList<DeckMenuEntryModel> entries)
    {
        foreach (var entry in entries)
        {
            yield return entry;
            foreach (var child in Flatten(entry.Children))
            {
                yield return child;
            }
        }
    }

    private static JsonElement RuntimeMenuValue(string fileName, string stepName, bool last)
    {
        var values = new List<JsonElement>();
        var path = Path.Combine(RepositoryRoot(), "Tests", "EngineTests", "Golden", fileName);
        foreach (var line in File.ReadLines(path))
        {
            using var document = JsonDocument.Parse(line);
            if (document.RootElement.GetProperty("step").GetString() == stepName)
            {
                values.Add(document.RootElement.GetProperty("value").Clone());
            }
        }
        return last ? values.Last() : values.First();
    }

    private static FrameworkElement Render(JsonElement model)
    {
        return Arrange(CardRenderer.Create(model, _ => { }));
    }

    private static FrameworkElement Arrange(FrameworkElement view)
    {
        view.Width = 352;
        view.Measure(new Size(352, double.PositiveInfinity));
        view.Arrange(new Rect(0, 0, 352, view.DesiredSize.Height));
        view.UpdateLayout();
        return view;
    }

    private static IReadOnlyList<JsonElement> GoldenModels(string cardId)
    {
        var models = new List<JsonElement>();
        foreach (var line in File.ReadLines(GoldenPaths().First()))
        {
            var message = DeckEvent.Parse(line);
            if (message.Card == cardId && message.Model is { } model &&
                models.All(existing => existing.GetRawText() != model.GetRawText()))
            {
                models.Add(model.Clone());
            }
        }
        return models;
    }

    private static FrameworkElement RenderSample(string cardId)
    {
        var view = CardRenderer.Create(SampleCard(cardId), _ => { });
        view.Width = 352;
        view.Measure(new Size(352, double.PositiveInfinity));
        view.Arrange(new Rect(0, 0, 352, view.DesiredSize.Height));
        view.UpdateLayout();
        return view;
    }

    private static JsonElement SampleCard(string cardId)
    {
        var path = Path.Combine(RepositoryRoot(), "docs", "poc", "windows-ui", "windows-style-sample.jsonl");
        foreach (var line in File.ReadLines(path))
        {
            var message = DeckEvent.Parse(line);
            if (message.Card == cardId && message.Model is { } model)
            {
                return model;
            }
        }
        throw new Exception($"Sample card {cardId} was not found.");
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            yield return child;
            foreach (var descendant in Descendants(child))
            {
                yield return descendant;
            }
        }
    }

    private static JsonElement ProjectModel(bool logIsOn, string? phoneURL)
    {
        return JsonSerializer.SerializeToElement(new
        {
            project = new
            {
                isCollapsed = false,
                mark = "next",
                title = "Project Sample",
                timestamp = "12:00:00",
                header = new
                {
                    log = new { toggleLogs = new { _0 = "project.sample" } },
                    logHelp = "open the log in a window",
                    logIsOn,
                    phoneURL,
                    phoneHelp = "open this on your phone",
                },
                hero = new { text = "running", tone = "good" },
                meta = new { place = "Windows" },
                tools = Array.Empty<object>(),
                environments = Array.Empty<object>(),
                actions = Array.Empty<object>(),
            },
        });
    }

    private static Button Button(DependencyObject root, string automationId)
    {
        return ButtonOrNull(root, automationId) ?? throw new Exception($"Button {automationId} was not found.");
    }

    private static Button? ButtonOrNull(DependencyObject root, string automationId)
    {
        if (root is Button button && AutomationProperties.GetAutomationId(button) == automationId)
        {
            return button;
        }
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            if (ButtonOrNull(VisualTreeHelper.GetChild(root, index), automationId) is { } found)
            {
                return found;
            }
        }
        return null;
    }

    private static CardWindow CreateWindow()
    {
        return new CardWindow("project.sample", _ => { }, _ => { }, _ => { });
    }

    private static double[] FirstPanelFrame()
    {
        foreach (var line in File.ReadLines(GoldenPaths().First()))
        {
            var message = DeckEvent.Parse(line);
            if (message.Panels?.FirstOrDefault(panel => panel.Frame.Length == 4) is { } panel)
            {
                return panel.Frame;
            }
        }

        throw new Exception();
    }

    private static IEnumerable<DeckCommand> Commands(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in value.EnumerateObject())
            {
                if (property.Name == "command" && property.Value.ValueKind == JsonValueKind.Object)
                {
                    yield return DeckCommand.From(property.Value);
                }
                else
                {
                    foreach (var command in Commands(property.Value))
                    {
                        yield return command;
                    }
                }
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in value.EnumerateArray())
            {
                foreach (var command in Commands(item))
                {
                    yield return command;
                }
            }
        }
    }

    private static IReadOnlyList<string> GoldenPaths()
    {
        var root = RepositoryRoot();
        var golden = Path.Combine(root, "Tests", "EngineTests", "Golden");
        var names = new[]
        {
            "session-en.expected.jsonl",
            "session-ru.expected.jsonl",
            "session-settings-en.expected.jsonl",
            "session-settings-ru.expected.jsonl",
        };
        return names.Select(name => Path.Combine(golden, name)).ToArray();
    }

    private static string RepositoryRoot()
    {
        var directory = new DirectoryInfo(Directory.GetCurrentDirectory());
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "Package.swift")))
            {
                return directory.FullName;
            }
            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException();
    }

    private static void Run(string name, Action test)
    {
        try
        {
            test();
            passed++;
            Console.WriteLine($"  ok   {name}");
        }
        catch (Exception exception)
        {
            failed++;
            Console.WriteLine($"  fail {name}: {exception.Message}");
        }
    }

    private static void True(bool value)
    {
        if (!value)
        {
            throw new Exception();
        }
    }

    private static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new Exception($"Expected {expected}, got {actual}.");
        }
    }

    private sealed class RecordingDialogs : IMenuDialogs
    {
        public bool ConfirmationAnswer { get; init; }
        public string? PromptAnswer { get; init; }

        public bool Confirm(DeckMenuDialogModel model)
        {
            return ConfirmationAnswer;
        }

        public string? Prompt(DeckMenuPromptModel model)
        {
            return PromptAnswer;
        }
    }
}
