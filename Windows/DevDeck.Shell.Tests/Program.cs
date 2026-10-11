using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Xml.Linq;
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
        if (arguments.Length == 2 && arguments[0] == "--capture-w6")
        {
            W6Screenshots.Generate(Path.GetFullPath(arguments[1]));
            Application.Current.Shutdown();
            return 0;
        }
        if (arguments.Length == 2 && arguments[0] == "--capture-w8")
        {
            W8Screenshots.Generate(Path.GetFullPath(arguments[1]));
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
        if (arguments.Length == 3 && arguments[0] == "--capture-theme")
        {
            ThemePreview.Generate(Path.GetFullPath(arguments[1]), Path.GetFullPath(arguments[2]));
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
        Run("only one shell instance holds the user session", SingleInstanceExcludesDuplicates);
        Run("a replay ignores the quit effect", ReplayIgnoresQuit);
        Run("a replay sizes its own panels from measurements", ReplaySizesItsPanels);
        Run("a card updated before it is shown still reports its height", CardUpdatedBeforeShowReportsHeight);
        Run("the protocol trace records both directions without typed tokens", ProtocolTraceLeavesTokensOut);
        Run("a second launch raises the first deck", SecondLaunchSignalsFirst);
        Run("replay and live shells hold separate instances", ReplayInstanceIsSeparate);
        Run("quit keeps the dispatcher responsive until cleanup completes", ShutdownKeepsDispatcherResponsive);
        Run("menus dismiss when another application takes focus", MenusDismissOutsideApplication);
        Run("the menu's input owner is never seen", MenuInputOwnerIsInvisible);
        Run("menu titles share one line after the check column", MenuTitlesShareOneLine);
        Run("dialog buttons carry the accent or the alert tone", DialogButtonsCarryTheirTone);
        Run("scroll bars and combo boxes follow the dark surface", ScrollBarsAndComboBoxesFitTheSurface);
        Run("the palette follows every scheme combination", PaletteFollowsEverySchemeCombination);
        Run("windows follow the app mode", WindowPaletteFollowsTheAppMode);
        Run("every token and tone is in both palettes", EveryTokenAndToneIsInBothPalettes);
        Run("a scheme change redraws without a restart", ThemeChangesRedrawWithoutRestart);
        Run("menu refresh preserves the open popup and capture", MenuRefreshPreservesOpenPopup);
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
        Run("card parts sit on one content edge", CardPartsShareOneContentEdge);
        Run("state dots sit on the capitals of their text", StateDotsSitOnTheirCapitals);
        Run("a project card keeps one height in every state", ProjectCardKeepsOneHeightInEveryState);
        Run("a crowded button row gives up whole labels", CrowdedActionsGiveUpWholeLabels);
        Run("expanded lists report a larger measured height", ExpandedListsReportLargerHeight);
        Run("runtime menu builds every entry kind", RuntimeMenuBuildsEveryEntryKind);
        Run("menu clicks send the exact command", MenuClicksSendExactCommand);
        Run("menu prompts fill only the command name", MenuPromptsFillOnlyTheCommandName);
        Run("cancelled confirmations send no command", CancelledConfirmationsSendNoCommand);
        Run("menu alternates send their own command", MenuAlternatesSendTheirOwnCommand);
        Run("card windows accept their context menu", CardWindowsAcceptTheirContextMenu);
        Run("tray status creates every icon tier", TrayStatusCreatesEveryIconTier);
        Run("prompt fields show their model placeholder and focus ring", PromptFieldsShowTheirModelPlaceholderAndFocusRing);
        Run("notification transcripts parse into complete models", NotificationTranscriptsParse);
        Run("notification clicks send the exact command", NotificationClicksSendExactCommand);
        Run("quiet notifications silence their toast XML", QuietNotificationsSilenceToastXml);
        Run("toast XML keeps text before its source mark", ToastXmlKeepsTextBeforeSourceMark);
        Run("notification ids are shown only once", NotificationIdsAreShownOnlyOnce);
        Run("every notification source has a shared mark", EveryNotificationSourceHasSharedMark);
        Run("notification artwork is an existing square file URI", NotificationArtworkIsExistingSquareFileUri);
        Run("toast registration uses a stable application id", ToastRegistrationUsesStableApplicationId);
        Run("log updates append only their new lines", LogUpdatesAppendOnlyNewLines);
        Run("empty logs show the engine detail", EmptyLogsShowEngineDetail);
        Run("closing a log reports that it is closed", ClosingLogReportsClosed);
        Run("opening a log twice keeps one window", OpeningLogTwiceKeepsOneWindow);
        Run("log search uses an unclipped Fluent chevron", LogSearchUsesUnclippedFluentChevron);
        Run("summon shortcuts parse and round trip", SummonShortcutsParseAndRoundTrip);
        Run("summon taps latch and holds release", SummonTapsLatchAndHoldsRelease);
        Run("present behaves like a summon tap", PresentBehavesLikeSummonTap);
        Run("disabled summon stays down", DisabledSummonStaysDown);
        Run("summon preferences parse from settings answers", SummonPreferencesParseFromSettingsAnswers);
        Run("display coordinates use primary monitor DIPs", DisplayCoordinatesUsePrimaryMonitorDips);
        Run("stable display ids do not use display indexes", StableDisplayIdsDoNotUseDisplayIndexes);
        Run("programmatic panel placement reports no move", ProgrammaticPanelPlacementReportsNoMove);
        Run("a drag reports one final move", DragReportsOneFinalMove);
        Run("a DPI change waits for a cross-display drag", DpiChangeWaitsForCrossDisplayDrag);
        Run("window size recalculates when DPI changes", WindowSizeRecalculatesWhenDpiChanges);
        Run("a system move reports one final frame", SystemMoveReportsOneFinalFrame);
        Run("display changes contain the full current list", DisplayChangesContainFullCurrentList);
        Run("settings pages build from engine words", SettingsPagesBuildFromEngineWords);
        Run("settings source has no visible text literals", SettingsSourceHasNoVisibleTextLiterals);
        Run("settings tokens leave the form once", SettingsTokensLeaveTheFormOnce);
        Run("settings words substitute their named value", SettingsWordsSubstituteNamedValue);
        Run("settings answers stay with their request", SettingsAnswersStayWithTheirRequest);
        Run("settings cards use the settings protocol", SettingsCardsUseSettingsProtocol);
        Run("token page requests keep their account shape", TokenPageRequestsKeepAccountShape);
        Run("DDEV name uses its display title", DdevNameUsesDisplayTitle);
        Run("Chromium Local State yields named profiles", ChromiumLocalStateYieldsNamedProfiles);
        Run("browser launch plans keep the chosen profile", BrowserLaunchPlansKeepChosenProfile);
        Run("terminal plans enter Windows and WSL folders", TerminalPlansEnterWindowsAndWslFolders);
        Run("Docker launches from Program Files without arguments", DockerLaunchesFromProgramFiles);
        Run("phone QR bytes are stable", PhoneQrBytesAreStable);
        Run("login item uses the Run value and quoted executable", LoginItemUsesRunValueAndQuotedExecutable);
        Run("disabling the login item deletes its value", DisablingLoginItemDeletesItsValue);
        Run("a login item for another executable is off", ForeignLoginItemIsOff);
        Run("a failed login item write restores the switch", FailedLoginItemWriteRestoresSwitch);
        Run("the login item installer flag is parsed", LoginItemInstallerFlagIsParsed);
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
        True(phone.Tag is System.Windows.Controls.Primitives.Popup);
    }

    private static void ProjectHeaderReflectsLogState()
    {
        var off = Button(CardRenderer.Create(ProjectModel(false, null), _ => { }), "project.header.log");
        var on = Button(CardRenderer.Create(ProjectModel(true, null), _ => { }), "project.header.log");
        True(!Equals(off.Foreground, on.Foreground));
        True(!Equals(off.Background, on.Background));
        True(on.Content is TextBlock onIcon && SameColour(WindowsTheme.Brush("ToneGood"), onIcon.Foreground));
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
        var acrylic = DeckPalette.ForCards(ThemeInputs.Default).CardTint;
        var solid = DeckPalette.ForCards(ThemeInputs.Default with { TransparencyEnabled = false }).CardTint;
        True(acrylic.A < 255);
        Equal((byte)255, solid.A);
        // The dark taskbar's solid colour.
        Equal(Color.FromRgb(0x1C, 0x1C, 0x1C), solid);
    }

    private static void PaletteFollowsEverySchemeCombination()
    {
        var accent = ThemeInputs.Default.AccentDark2;
        foreach (var light in new[] { false, true })
        {
            foreach (var transparent in new[] { false, true })
            {
                foreach (var accentOnTaskbar in new[] { false, true })
                {
                    var inputs = ThemeInputs.Default with
                    {
                        SystemUsesLightTheme = light,
                        TransparencyEnabled = transparent,
                        AccentOnTaskbar = accentOnTaskbar,
                    };
                    var palette = DeckPalette.ForCards(inputs);
                    // The card is the taskbar's material, which is light only without the accent.
                    Equal(light && !accentOnTaskbar, palette.IsLight);
                    Equal(transparent, palette.CardTint.A < 255);
                    var expected = accentOnTaskbar ? accent
                        : light ? Color.FromRgb(0xEE, 0xEE, 0xEE) : Color.FromRgb(0x1C, 0x1C, 0x1C);
                    Equal(expected.R, palette.CardTint.R);
                    Equal(expected.G, palette.CardTint.G);
                    Equal(expected.B, palette.CardTint.B);
                    // Text reads on the surface: light text on dark, dark text on light.
                    Equal(palette.IsLight, palette["TextPrimary"].R < 128);
                }
            }
        }
    }

    private static void WindowPaletteFollowsTheAppMode()
    {
        foreach (var light in new[] { false, true })
        {
            foreach (var transparent in new[] { false, true })
            {
                foreach (var accentOnTaskbar in new[] { false, true })
                {
                    // Windows follow the app mode whatever the taskbar does.
                    var palette = DeckPalette.ForWindows(ThemeInputs.Default with
                    {
                        AppsUseLightTheme = light,
                        SystemUsesLightTheme = !light,
                        TransparencyEnabled = transparent,
                        AccentOnTaskbar = accentOnTaskbar,
                    });
                    Equal(light, palette.IsLight);
                    Equal(light, palette["TextPrimary"].R < 128);
                    Equal(light ? Color.FromRgb(243, 243, 243) : Color.FromRgb(32, 32, 32), palette["WindowBackground"]);
                }
            }
        }
    }

    private static void EveryTokenAndToneIsInBothPalettes()
    {
        foreach (var light in new[] { false, true })
        {
            var palette = DeckPalette.ForCards(ThemeInputs.Default with { SystemUsesLightTheme = light });
            foreach (var key in DeckPalette.Keys)
            {
                _ = palette[key];
            }
            foreach (var tone in new[] { "good", "attention", "alert", "personal" })
            {
                True(palette.Tone(tone) != palette["TextPrimary"]);
                True(palette.ToneTint(tone).A > 0 && palette.ToneTint(tone).A < 64);
            }
            Equal(palette["TextPrimary"], palette.Tone("neutral"));
        }
    }

    private static void ThemeChangesRedrawWithoutRestart()
    {
        var inputs = ThemeInputs.Default;
        var monitor = new ThemeMonitor(Dispatcher.CurrentDispatcher, () => inputs);
        var cardBrush = (SolidColorBrush)WindowsTheme.CardBrush("TextPrimary");
        var windowBrush = (SolidColorBrush)WindowsTheme.Brush("TextPrimary");
        var changes = new List<(DeckPalette Cards, DeckPalette Windows)>();
        monitor.Changed += (cards, windows) => changes.Add((cards, windows));
        try
        {
            monitor.Refresh();
            Equal(0, changes.Count);
            // A light Windows mode with dark apps: the cards follow the taskbar, windows stay dark.
            inputs = inputs with { SystemUsesLightTheme = true };
            monitor.Refresh();
            Equal(1, changes.Count);
            True(changes[0].Cards.IsLight);
            True(!changes[0].Windows.IsLight);
            Equal(changes[0].Cards["TextPrimary"], cardBrush.Color);
            Equal(changes[0].Windows["TextPrimary"], windowBrush.Color);
            True(cardBrush.Color != windowBrush.Color);
            // Styles inside a card resolve the card's palette from the dictionary on its root.
            var card = Render(GoldenModels("arc.project.paper").Last());
            var chip = Descendants(card).OfType<Button>().First(button => Equals(button.Content, "PageBuilder"));
            Equal(changes[0].Cards["ControlFill"], ((SolidColorBrush)chip.Background).Color);
            // Light apps: windows follow, and so do the styles' entries.
            inputs = inputs with { AppsUseLightTheme = true };
            monitor.Refresh();
            Equal(changes[1].Windows["TextPrimary"], windowBrush.Color);
            Equal(changes[1].Windows["TextPrimary"], ((SolidColorBrush)Application.Current.FindResource("TextPrimary")).Color);
        }
        finally
        {
            inputs = ThemeInputs.Default;
            monitor.Refresh();
            monitor.Dispose();
        }
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
        True(reviewText.Any(text => text.Text == "2 repos · 1 org" && text.FontSize == 12 && SameColour(WindowsTheme.Brush("TextTertiary"), text.Foreground)));
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
        True(SameColour(WindowsTheme.Brush("TextSecondary"), leading.Foreground));

        var trailing = Descendants(project).OfType<TrackedTextBlock>().Single(text => text.Text == "bun run dev");
        Equal(11.0, trailing.FontSize);
        Equal(WindowsTheme.Mono, trailing.FontFamily);
        Equal(DeckTextTrimming.Middle, trailing.Trimming);
        True(SameColour(WindowsTheme.Brush("TextTertiary"), trailing.Foreground));

        var place = Descendants(project).OfType<Grid>().Single(grid =>
            grid.Children.OfType<TextBlock>().Any(text => text.Text == "WSL · Ubuntu-24.04"));
        Equal(24.0, place.Height);
        var outline = place.Children.OfType<System.Windows.Shapes.Rectangle>().Single();
        True(outline.Fill is null);
        Equal("2,2", string.Join(',', outline.StrokeDashArray.Select(value => value.ToString(System.Globalization.CultureInfo.InvariantCulture))));
        var placeText = place.Children.OfType<TextBlock>().Single();
        True(SameColour(WindowsTheme.Brush("TextPrimary"), placeText.Foreground));
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
        True(text.Any(item => item.Text == "now" && SameColour(WindowsTheme.Brush("TextTertiary"), item.Foreground)));
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
        True(SameColour(WindowsTheme.Brush("LinkInfo"), branch.Foreground));
        True(Descendants(workCard).OfType<TextBlock>().Any(text => text.Text == "2 changes"));
    }

    private static void ProjectKindsShareStyledParts()
    {
        var arc = Render(GoldenModels("arc.project.paper").Last());
        var tool = Descendants(arc).OfType<Button>().Single(button => Equals(button.Content, "PageBuilder"));
        True(SameColour(WindowsTheme.Brush("LinkInfo"), tool.Foreground));
        var local = Descendants(arc).OfType<TextBlock>().First(text => text.Text == "Local site");
        True(SameColour(WindowsTheme.Brush("ToneGood"), local.Foreground));

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
        // The row is the grid with columns; a card button's template is a grid too.
        var pullRequestRow = Descendants(pullRequestCollapsed).OfType<Grid>().Single(grid => grid.ColumnDefinitions.Count > 0);
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

    private static void CardPartsShareOneContentEdge()
    {
        // The mock's grid: everything inside the frame's padding starts on its left edge and ends
        // on its right edge, and a list row bleeds 6 px past both so its contents land on them.
        var list = (Border)Render(GoldenModels("github.pullRequests").Last());
        var listContent = (FrameworkElement)list.Child;
        TextBlock Named(FrameworkElement root, string text) =>
            Descendants(root).OfType<TextBlock>().First(block => block.Text == text);
        double Left(FrameworkElement element) => element.TranslatePoint(new Point(0, 0), listContent).X;
        double Right(FrameworkElement element) => listContent.ActualWidth - element.TranslatePoint(new Point(element.ActualWidth, 0), listContent).X;
        Near(0, Left(Named(list, "4")));
        Near(0, Left(Named(list, "2 repos · 1 org")));
        Near(0, Right(Named(list, "04:00:00")));
        Near(0, Right(Named(list, "1 blocked")));
        var row = Descendants(list).OfType<Button>().First(button => button.Content is Grid);
        Near(-6, Left(row));
        Near(-6, Right(row));
        var rowGrid = (Grid)row.Content;
        Near(0, Left((FrameworkElement)rowGrid.Children[0]));
        Near(0, Right(Named(list, "CR")));

        var project = (Border)Render(GoldenModels("arc.project.paper").Last());
        listContent = (FrameworkElement)project.Child;
        var buttons = Descendants(project).OfType<Button>().ToList();
        Near(0, Left(buttons.First(button => Equals(button.Content, "PageBuilder"))));
        var actions = buttons.Where(button => button.ActualHeight == 32).ToList();
        Near(0, Left(actions.First()));
        Near(0, Right(actions.Last()));
    }

    private static void CrowdedActionsGiveUpWholeLabels()
    {
        static string Card(string start, string restart) => $$$"""
            {"project":{"title":"Shop","actions":[
            {"command":{"startDocker":{}},"glyph":"docker","isEnabled":true,"isProminent":true,"title":"{{{start}}}","tone":"alert"},
            {"command":{"project":{"_0":"ddev.project.shop","_1":"restart"}},"glyph":"restart","isEnabled":false,"isProminent":false,"title":"{{{restart}}}"},
            {"command":{"revealFolder":{"_0":"ddev.project.shop"}},"glyph":"folder","isEnabled":true,"isProminent":false,"title":"Folder"},
            {"command":{"openTerminal":{"_0":"ddev.project.shop"}},"glyph":"terminal","isEnabled":true,"isProminent":false,"title":"Terminal"}]}}
            """;
        TextBlock Label(FrameworkElement card, string text) =>
            Descendants(card).OfType<TextBlock>().First(block => block.Text == text);

        using var roomy = JsonDocument.Parse(Card("Start", "Restart"));
        var english = Render(roomy.RootElement);
        Equal(Visibility.Visible, Label(english, "Restart").Visibility);

        using var crowded = JsonDocument.Parse(Card("Запустить Docker", "Перезапустить"));
        var russian = Render(crowded.RootElement);
        Equal(Visibility.Collapsed, Label(russian, "Перезапустить").Visibility);
        var start = Label(russian, "Запустить Docker");
        Equal(Visibility.Visible, start.Visibility);
        start.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        True(start.ActualWidth >= start.DesiredSize.Width - 0.5);
    }

    private static void ProjectCardKeepsOneHeightInEveryState()
    {
        // Stopped, starting with a long progress line, running with containers and a version,
        // failed with a long reason, and a meta row with nothing on either side.
        var long_ = "the stack did not answer /release on http://localhost:80 within three minutes, see the log";
        var states = new (string Text, string Tone, string? Note, string? Leading, string? Trailing)[]
        {
            ("stopped", "neutral", null, "sandbox.demo", null),
            ("starting", "attention", null, "Pulling fusion-engine, layer 3 of 12, 412 MB of 1.2 GB downloaded", null),
            ("running", "good", "9 containers", "sandbox.demo", "7.2.1"),
            ("failed", "alert", long_, "sandbox.demo", null),
            ("stopped", "neutral", "pid 4242", null, null),
        };
        var heights = new List<double>();
        foreach (var state in states)
        {
            var model = JsonNode.Parse(SampleCard("project.windows").GetRawText())!;
            var project = model["project"]!;
            project["hero"] = new JsonObject
            {
                ["text"] = state.Text,
                ["tone"] = state.Tone,
                ["note"] = state.Note,
                ["help"] = state.Text,
            };
            var meta = project["meta"]!;
            meta["branch"] = "main";
            meta["leading"] = state.Leading;
            meta["trailing"] = state.Trailing;
            var view = Render(JsonSerializer.SerializeToElement(model));
            heights.Add(view.ActualHeight);
        }
        foreach (var height in heights)
        {
            Equal(heights[0], height);
        }
    }

    private static void StateDotsSitOnTheirCapitals()
    {
        // The shift is the distance from the line box's middle to the capitals' middle: positive,
        // because a line box reaches further above the capitals than below the baseline.
        foreach (var size in new[] { 22.0, 14.0 })
        {
            var typeface = new Typeface(WindowsTheme.Sans, FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal);
            var line = new FormattedText("H", System.Globalization.CultureInfo.InvariantCulture, FlowDirection.LeftToRight, typeface, size, Brushes.Black, 1.0);
            var expected = line.Baseline - typeface.CapsHeight * size / 2 - line.Height / 2;
            Near(Math.Round(expected, 2), WindowsCardRenderer.DotShift(size, FontWeights.SemiBold));
            True(WindowsCardRenderer.DotShift(size, FontWeights.SemiBold) > 0);
        }

        void Check(FrameworkElement card, double dotSize, string text, double textSize)
        {
            var dot = Descendants(card).OfType<Border>().First(border => border.Width == dotSize && border.Height == dotSize && border.CornerRadius.TopLeft == dotSize / 2);
            var label = Descendants(card).OfType<TextBlock>().First(block => block.Text == text);
            var dotMiddle = dot.TranslatePoint(new Point(0, dotSize / 2), card).Y;
            var typeface = new Typeface(label.FontFamily, label.FontStyle, label.FontWeight, label.FontStretch);
            var line = new FormattedText(text, System.Globalization.CultureInfo.InvariantCulture, FlowDirection.LeftToRight, typeface, textSize, Brushes.Black, 1.0);
            var capitalsMiddle = label.TranslatePoint(new Point(0, line.Baseline - typeface.CapsHeight * textSize / 2), card).Y;
            True(Math.Abs(dotMiddle - capitalsMiddle) < 0.5);
        }
        Check(Render(GoldenModels("arc.project.paper").Last()), 8, "not configured", 22);
        var collapsed = (FrameworkElement)Render(GoldenModels("project.feed").Last(model =>
            JsonModel.Bool(model.EnumerateObject().Single().Value, "isCollapsed")));
        Check(collapsed, 7, "Feed", 14);
    }

    private static bool SameColour(Brush expected, Brush? actual)
    {
        return actual is SolidColorBrush solid && expected is SolidColorBrush wanted && solid.Color == wanted.Color;
    }

    private static void Near(double expected, double actual)
    {
        if (Math.Abs(expected - actual) > 0.01)
        {
            throw new Exception($"expected {expected}, got {actual}");
        }
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
        var window = new CardWindow(
            "github.pullRequests",
            measurements.Add,
            _ => { },
            _ => { },
            () => { });
        window.Show();
        window.Update(compactModel);
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        window.Update(expandedModel);
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        Equal(2, measurements.Count);
        True(measurements[1].Size[1] > measurements[0].Size[1]);
        window.Close();
    }

    private static void CardUpdatedBeforeShowReportsHeight()
    {
        var measurements = new List<CardMeasurement>();
        var window = new CardWindow("github.pullRequests", measurements.Add, _ => { }, _ => { }, () => { });
        window.Update(GoldenModels("github.pullRequests").Last());
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        Equal(0, measurements.Count);
        window.Show();
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        Equal(1, measurements.Count);
        True(measurements[0].Size[1] > 44);
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

        var lightNeedsFixing = Pixel(TrayIconFactory.Preview(32, 1, true), 26, 26);
        var darkNeedsFixing = Pixel(TrayIconFactory.Preview(32, 1, false), 26, 26);
        var waiting = Pixel(TrayIconFactory.Preview(32, 0, false), 26, 26);
        True(lightNeedsFixing.R < 80 && lightNeedsFixing.G < 80 && lightNeedsFixing.B < 80);
        True(darkNeedsFixing.R > 200 && darkNeedsFixing.G > 200 && darkNeedsFixing.B > 200);
        True(waiting.R > waiting.G + 40 && waiting.R > waiting.B + 40);
    }

    private static void PromptFieldsShowTheirModelPlaceholderAndFocusRing()
    {
        var value = RuntimeMenuValue("runtime-menu-en.expected.jsonl", "menu", last: false);
        var prompt = Flatten(DeckMenuEntryModel.ParseList(value))
            .Select(entry => entry.Item?.Prompt)
            .Single(model => model is not null) ?? throw new Exception();
        var window = MenuDialogs.Build(prompt, prompt.Placeholder, out var field, out _);
        var textBox = field ?? throw new Exception();
        window.Show();
        textBox.ApplyTemplate();
        window.UpdateLayout();

        True(SameColour(WindowsTheme.Brush("ControlFill"), textBox.Background));
        True(SameColour(WindowsTheme.Brush("ControlStroke"), textBox.BorderBrush));
        Equal(32.0, textBox.Height);
        Equal(VerticalAlignment.Center, textBox.VerticalContentAlignment);
        Equal(150.0, SettingsWindow.FormLabelWidth);
        var placeholder = (TextBlock)textBox.Template.FindName("Placeholder", textBox);
        Equal(prompt.Placeholder, placeholder.Text);
        True(SameColour(WindowsTheme.Brush("TextTertiary"), placeholder.Foreground));
        Equal(Visibility.Visible, placeholder.Visibility);

        textBox.Text = "Desk";
        window.UpdateLayout();
        Equal(Visibility.Collapsed, placeholder.Visibility);

        textBox.Text = "";
        _ = textBox.Focus();
        textBox.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        var focusBorder = (Border)textBox.Template.FindName("FocusBorder", textBox);
        var controlBorder = (Border)textBox.Template.FindName("ControlBorder", textBox);
        True(SameColour(WindowsTheme.Brush("FocusOuter"), focusBorder.BorderBrush));
        True(SameColour(WindowsTheme.Brush("FocusInner"), controlBorder.BorderBrush));
        window.Close();
    }

    private static void NotificationTranscriptsParse()
    {
        foreach (var name in new[]
        {
            "runtime-banners-en.expected.jsonl",
            "runtime-banners-ru.expected.jsonl",
        })
        {
            var notifications = RuntimeNotifications(name);
            Equal(2, notifications.Count);
            True(notifications.All(notification => notification.Command.Json.Contains("followAlert", StringComparison.Ordinal)));
        }

        foreach (var name in new[]
        {
            "session-settings-en.expected.jsonl",
            "session-settings-ru.expected.jsonl",
        })
        {
            var notifications = SessionNotifications(name);
            Equal(1, notifications.Count);
            Equal("devdeck", notifications[0].Source);
            Equal("{\"installUpdate\":{}}", notifications[0].Command.Json);
        }
    }

    private static void NotificationClicksSendExactCommand()
    {
        var notification = SessionNotifications("session-settings-en.expected.jsonl").Single();
        var platform = new RecordingToastPlatform();
        DeckCommand? sent = null;
        using var controller = new NotificationController(platform, _ => "file:///mark.png", command => sent = command);
        controller.Show([notification]);
        platform.Activate(notification.Id);
        Equal(notification.Command.Json, sent?.Json);
    }

    private static void QuietNotificationsSilenceToastXml()
    {
        var quiet = SessionNotifications("session-settings-en.expected.jsonl").Single();
        var quietDocument = XDocument.Parse(ToastPayload.Build(quiet, "file:///mark.png"));
        Equal("true", quietDocument.Root?.Element("audio")?.Attribute("silent")?.Value);

        var audible = RuntimeNotifications("runtime-banners-en.expected.jsonl").First();
        var audibleDocument = XDocument.Parse(ToastPayload.Build(audible, "file:///mark.png"));
        True(audibleDocument.Root?.Element("audio") is null);
    }

    private static void ToastXmlKeepsTextBeforeSourceMark()
    {
        var notification = RuntimeNotifications("runtime-banners-en.expected.jsonl").First();
        var document = XDocument.Parse(ToastPayload.Build(notification, "file:///mark.png"));
        var children = document.Root?
            .Element("visual")?
            .Element("binding")?
            .Elements()
            .Select(element => element.Name.LocalName)
            .ToArray() ?? [];
        Equal("text,text,text,image", string.Join(',', children));
        Equal(
            "file:///mark.png",
            document.Root?
                .Element("visual")?
                .Element("binding")?
                .Element("image")?
                .Attribute("src")?
                .Value);
    }

    private static void NotificationIdsAreShownOnlyOnce()
    {
        var notification = SessionNotifications("session-settings-en.expected.jsonl").Single();
        var platform = new RecordingToastPlatform();
        using var controller = new NotificationController(platform, _ => "file:///mark.png", _ => { });
        controller.Show([notification]);
        controller.Show([notification]);
        Equal(1, platform.Payloads.Count);
    }

    private static void EveryNotificationSourceHasSharedMark()
    {
        foreach (var source in new[] { "github", "gitlab", "arc", "ddev", "project", "docker", "devdeck" })
        {
            True(BrandMarks.Names.Contains(source, StringComparer.Ordinal));
        }
    }

    private static void NotificationArtworkIsExistingSquareFileUri()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"devdeck-toast-{Guid.NewGuid():N}");
        try
        {
            var value = NotificationArtwork.FileUri("github", directory);
            var uri = new Uri(value);
            True(value.StartsWith("file:///", StringComparison.Ordinal));
            True(value.Contains('\\'));
            True(uri.IsAbsoluteUri);
            True(uri.IsFile);
            True(File.Exists(uri.LocalPath));
            using var stream = File.OpenRead(uri.LocalPath);
            var decoder = BitmapDecoder.Create(
                stream,
                BitmapCreateOptions.PreservePixelFormat,
                BitmapCacheOption.OnLoad);
            var frame = decoder.Frames.Single();
            Equal(256, frame.PixelWidth);
            Equal(frame.PixelWidth, frame.PixelHeight);
            var chunks = PngChunkTypes(File.ReadAllBytes(uri.LocalPath));
            True(!chunks.Contains("gAMA", StringComparer.Ordinal));
            True(!chunks.Contains("pHYs", StringComparer.Ordinal));
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, true);
            }
        }
    }

    private static void ToastRegistrationUsesStableApplicationId()
    {
        Equal("DevDeck.Shell", ToastShortcutRegistration.AppId);
        Equal(
            Path.Combine(
                "profile",
                "Microsoft",
                "Windows",
                "Start Menu",
                "Programs",
                "DevDeck.lnk"),
            ToastShortcutRegistration.ShortcutPath("profile"));
    }

    private static IReadOnlyList<string> PngChunkTypes(byte[] bytes)
    {
        var result = new List<string>();
        var offset = 8;
        while (offset + 12 <= bytes.Length)
        {
            var length = System.Buffers.Binary.BinaryPrimitives.ReadInt32BigEndian(
                bytes.AsSpan(offset, 4));
            var type = System.Text.Encoding.ASCII.GetString(bytes, offset + 4, 4);
            result.Add(type);
            offset += length + 12;
            if (type == "IEND")
            {
                break;
            }
        }
        return result;
    }

    private static Color Pixel(System.Windows.Media.Imaging.BitmapSource image, int x, int y)
    {
        var pixel = new byte[4];
        image.CopyPixels(new Int32Rect(x, y, 1, 1), pixel, 4, 0);
        return Color.FromArgb(pixel[3], pixel[2], pixel[1], pixel[0]);
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

    private static IReadOnlyList<DeckNotification> RuntimeNotifications(string fileName)
    {
        var notifications = new List<DeckNotification>();
        var path = Path.Combine(RepositoryRoot(), "Tests", "EngineTests", "Golden", fileName);
        foreach (var line in File.ReadLines(path))
        {
            using var document = JsonDocument.Parse(line);
            notifications.AddRange(ReplayNotificationAdapter.Parse(document.RootElement.GetProperty("value")));
        }
        return notifications;
    }

    private static IReadOnlyList<DeckNotification> SessionNotifications(string fileName)
    {
        var notifications = new List<DeckNotification>();
        var path = Path.Combine(RepositoryRoot(), "Tests", "EngineTests", "Golden", fileName);
        foreach (var line in File.ReadLines(path))
        {
            var message = DeckEvent.Parse(line);
            if (message.Notifications is { } eventNotifications)
            {
                notifications.AddRange(eventNotifications);
            }
        }
        return notifications;
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
                    phoneTitle = "Open on your phone",
                    phoneNote = "Use the same network.",
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
        return new CardWindow("project.sample", _ => { }, _ => { }, _ => { }, () => { });
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

    private static void LogUpdatesAppendOnlyNewLines()
    {
        var buffer = new LogBuffer();
        var first = buffer.Apply(new DeckLog(["one", "two"], "tail sample.log", null));
        var second = buffer.Apply(new DeckLog(["one", "two", "three"], "tail sample.log", null));
        True(!first.Reset);
        Equal(2, first.Added.Count);
        True(!second.Reset);
        Equal(1, second.Added.Count);
        Equal("three", second.Added[0]);
        Equal(3, buffer.Lines.Count);
    }

    private static void EmptyLogsShowEngineDetail()
    {
        var window = new LogWindow("project.sample");
        window.Update(new DeckLog([], "tail sample.log", "nothing has been started from here yet"));
        True(window.DetailIsVisible);
        window.Close();
    }

    private static void ClosingLogReportsClosed()
    {
        var created = new List<RecordingLogWindow>();
        var registry = new LogWindowRegistry(_ =>
        {
            var window = new RecordingLogWindow();
            created.Add(window);
            return window;
        });
        var changes = new List<LogWindowChange>();
        registry.WindowChanged += changes.Add;
        registry.Open("project.sample");
        registry.Close("project.sample");
        Equal(2, changes.Count);
        True(changes[0].IsOpen);
        True(!changes[1].IsOpen);
        Equal("project.sample", changes[1].Card);
        using var document = JsonDocument.Parse(ProtocolWriter.LogWindowChanged("9", changes[1]));
        Equal("logWindow.changed", document.RootElement.GetProperty("intent").GetString());
        Equal("project.sample", document.RootElement.GetProperty("card").GetString());
        True(!document.RootElement.GetProperty("isOpen").GetBoolean());
    }

    private static void OpeningLogTwiceKeepsOneWindow()
    {
        var created = new List<RecordingLogWindow>();
        var registry = new LogWindowRegistry(_ =>
        {
            var window = new RecordingLogWindow();
            created.Add(window);
            return window;
        });
        registry.Open("project.sample");
        registry.Open("project.sample");
        Equal(1, created.Count);
        Equal(1, registry.Count);
        Equal(1, created[0].Activations);
        registry.CloseAll(false);
    }

    private static void LogSearchUsesUnclippedFluentChevron()
    {
        var window = new LogWindow("project.sample");
        var glyph = window.SearchNextButton.Content as TextBlock ?? throw new Exception();
        Equal(DeckIcons.Text("expand"), glyph.Text);
        Equal(new Thickness(0), window.SearchNextButton.Padding);
        window.Close();
    }

    private static void SummonShortcutsParseAndRoundTrip()
    {
        var shortcut = SummonShortcut.Parse("Shift+Win+Ctrl+F12");
        Equal(
            SummonModifiers.Control | SummonModifiers.Shift | SummonModifiers.Windows,
            shortcut.Modifiers);
        Equal(0x7Bu, shortcut.VirtualKey);
        Equal("Ctrl+Shift+Win+F12", shortcut.ToString());
        Equal(shortcut, SummonShortcut.Parse(shortcut.ToString()));
        Equal(SummonShortcut.DefaultText, SummonShortcut.Parse(null).ToString());
    }

    private static void SummonTapsLatchAndHoldsRelease()
    {
        var state = new SummonState();
        var changes = new List<SummonPresentation>();
        state.Changed += changes.Add;
        state.ApplyPreferences(new SummonPreferences(true, true, null));

        state.Press(1.0);
        state.Release(1.0 + SummonState.LatchThresholdSeconds - 0.001);
        True(state.IsRaised);
        state.Press(2.0);
        True(!state.IsRaised);

        state.Press(3.0);
        state.Release(3.0 + SummonState.LatchThresholdSeconds);
        True(!state.IsRaised);
        Equal(4, changes.Count);
        True(changes[0].IsRaised);
        True(changes[0].Dims);
        True(!changes[1].IsRaised);
        True(changes[2].IsRaised);
        True(!changes[3].IsRaised);
    }

    private static void PresentBehavesLikeSummonTap()
    {
        var state = new SummonState();
        state.ApplyPreferences(new SummonPreferences(true, false, null));
        state.Present();
        True(state.IsRaised);
        state.Press(1.0);
        True(!state.IsRaised);

        state.Press(2.0);
        state.Release(2.1);
        True(state.IsRaised);
        state.Press(3.0);
        True(!state.IsRaised);
    }

    private static void DisabledSummonStaysDown()
    {
        var state = new SummonState();
        state.ApplyPreferences(new SummonPreferences(false, true, null));
        state.Press(1.0);
        state.Release(1.1);
        state.Present();
        True(!state.IsRaised);

        state.ApplyPreferences(new SummonPreferences(true, true, null));
        state.Present();
        True(state.IsRaised);
        state.ApplyPreferences(new SummonPreferences(false, true, null));
        True(!state.IsRaised);
    }

    private static void SummonPreferencesParseFromSettingsAnswers()
    {
        using var document = JsonDocument.Parse(
            "{\"preferences\":{\"_0\":{\"summonEnabled\":true,\"summonDims\":false," +
            "\"summonShortcutWindows\":\"Alt+F12\"}}}");
        True(SummonPreferences.TryParse(document.RootElement, out var preferences));
        True(preferences.Enabled);
        True(!preferences.Dims);
        Equal("Alt+F12", preferences.ShortcutText);

        using var unrelated = JsonDocument.Parse("{\"done\":{}}");
        True(!SummonPreferences.TryParse(unrelated.RootElement, out _));
    }

    private static void DisplayCoordinatesUsePrimaryMonitorDips()
    {
        var displays = DisplayProvider.InPrimaryDisplayDips(
        [
            new PhysicalDisplay("primary", [0, 0, 2880, 1560], true, 1.5),
            new PhysicalDisplay("secondary", [2880, -400, 3840, 2160], false, 2.0),
        ],
        1.5);
        Equal(2, displays.Count);
        Equal("primary", displays[0].Id);
        Equal(1920.0, displays[1].Frame[0]);
        Equal(-400.0 / 1.5, displays[1].Frame[1]);
        Equal(2560.0, displays[1].Frame[2]);
        Equal(1440.0, displays[1].Frame[3]);
        Equal("primary", displays.Single(display => display.IsPrimary).Id);
        Equal(
            469.333,
            Math.Round(DisplayProvider.LocalDipsInPrimaryDisplayDips(352, 2.0, 1.5), 3));
    }

    private static void StableDisplayIdsDoNotUseDisplayIndexes()
    {
        var interfacePath = @"\\?\DISPLAY#SAMPLE#1#{identifier}";
        Equal(
            interfacePath,
            DisplayProvider.StableId(interfacePath, @"DISPLAY\SAMPLE\1", "device key"));
    }

    private static void ProgrammaticPanelPlacementReportsNoMove()
    {
        var moves = new List<CardMove>();
        var window = new CardWindow(
            "project.sample",
            _ => { },
            moves.Add,
            _ => { },
            () => { });
        window.Show();
        window.ApplyFrame([32, 32, 352, 120]);
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        Equal(0, moves.Count);
        window.Close();
    }

    private static void DragReportsOneFinalMove()
    {
        var tracker = new CardMoveTracker();
        tracker.BeginDrag();
        True(!tracker.PositionChanged());
        True(!tracker.PositionChanged());
        True(tracker.EndDrag());
        True(!tracker.EndDrag());
    }

    private static void DpiChangeWaitsForCrossDisplayDrag()
    {
        var tracker = new CardMoveTracker();
        tracker.BeginDrag();
        True(!tracker.DpiChanged());
        True(tracker.EndDrag());
        True(tracker.TakeDelayedDpiChange());
        True(!tracker.TakeDelayedDpiChange());
        True(tracker.DpiChanged());
    }

    private static void WindowSizeRecalculatesWhenDpiChanges()
    {
        const double primaryScale = 2.5;
        const double panelWidth = 352;
        var externalFrameWidth = DisplayProvider.LocalDipsInPrimaryDisplayDips(
            panelWidth,
            1,
            primaryScale);

        Equal(
            panelWidth,
            WindowDpiLayout.LocalDipsForPrimaryDips(
                panelWidth,
                primaryScale,
                primaryScale));
        Equal(
            panelWidth,
            WindowDpiLayout.LocalDipsForPrimaryDips(
                externalFrameWidth,
                primaryScale,
                1));
    }

    private static void SystemMoveReportsOneFinalFrame()
    {
        var moves = new List<CardMove>();
        var window = new CardWindow(
            "project.sample",
            _ => { },
            moves.Add,
            _ => { },
            () => { });
        window.Show();
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        moves.Clear();
        NativeMethods.SetWindowFrame(window.Handle, 48, 48, 352, 120);
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        Equal(1, moves.Count);
        Equal(48.0, moves[0].Frame[0]);
        Equal(48.0, moves[0].Frame[1]);
        window.Close();
    }

    private static void DisplayChangesContainFullCurrentList()
    {
        IReadOnlyList<DisplayModel> current =
        [
            new DisplayModel("first", [0, 0, 1920, 1040], true),
            new DisplayModel("second", [1920, 0, 1280, 720], false),
        ];
        var publisher = new DisplayChangePublisher(() => current);
        IReadOnlyList<DisplayModel>? received = null;
        publisher.Changed += displays => received = displays;
        publisher.Publish();
        Equal(2, received?.Count);
        Equal("first", received?[0].Id);
        Equal("second", received?[1].Id);
        current = [new DisplayModel("first", [0, 0, 1920, 1040], true)];
        publisher.Publish();
        Equal(1, received?.Count);
        Equal("first", received?[0].Id);
    }

    private static void SettingsPagesBuildFromEngineWords()
    {
        var client = new SettingsClient();
        client.Receive("words", Json("{\"words\":{\"_0\":{\"settings.window.title\":\"Settings\",\"settings.general.title\":\"General\",\"settings.deck.title\":\"Deck\",\"settings.cards.title\":\"Cards\",\"settings.notifications.title\":\"Notifications\"}}}"));
        client.Receive("list", Json("{\"list\":{\"_0\":{\"accounts\":[],\"projects\":[]}}}"));
        client.Receive("cards", Json("{\"cards\":{\"_0\":[{\"id\":\"github.pullRequests\",\"title\":\"Pull requests\",\"detail\":\"Reviews\",\"isEnabled\":true}]}}"));
        client.Receive("preferences", Json("{\"preferences\":{\"_0\":{\"language\":\"system\",\"displayMode\":\"desktop\",\"isLocked\":false,\"packsColumns\":false,\"refreshIntervalSeconds\":120,\"notificationsEnabled\":true,\"notifiesUpdates\":true,\"checksForUpdates\":true,\"summonEnabled\":true,\"summonDims\":true,\"actionsRepositories\":[],\"projectsQuietWhenDown\":[],\"projectsQuietWhenStartFails\":[]}}}"));
        var window = TestSettingsWindow(client);
        window.Apply(client.Words, client.List, client.Cards, client.Preferences, null);
        window.Receive(Json("{\"githubAccount\":{\"_0\":{\"id\":\"account\",\"label\":\"Account\",\"apiBaseURL\":\"https://example.invalid\",\"organizations\":[],\"isEnabled\":true,\"browser\":{}}}}"));
        window.Receive(Json("{\"gitlabAccount\":{\"_0\":{\"id\":\"instance\",\"label\":\"Instance\",\"host\":\"https://example.invalid\",\"isEnabled\":true,\"browser\":{}}}}"));
        window.Receive(Json("{\"localProject\":{\"_0\":{\"id\":\"site\",\"title\":\"Site\",\"folder\":\"C:/Sample\",\"startCommand\":\"run\",\"stopCommand\":\"\",\"holdsProcess\":true,\"requiresDocker\":false,\"healthURL\":\"\",\"localSiteURL\":\"\",\"isEnabled\":true,\"browser\":{}}}}"));
        window.Receive(Json("{\"arcProject\":{\"_0\":{\"id\":\"arc\",\"title\":\"Arc\",\"organization\":\"sample\",\"folder\":null,\"startCommand\":\"run\",\"stopCommand\":\"stop\",\"healthPath\":\"/health\",\"localURL\":\"\",\"isEnabled\":true,\"browser\":{}}}}"));
        window.Receive(Json("{\"ddevProject\":{\"_0\":{\"id\":\"shop\",\"name\":\"shop\",\"title\":\"\",\"folder\":\"C:/Sample\",\"showsMailpit\":true,\"showsXhgui\":false,\"isEnabled\":true,\"browser\":{}}}}"));
        foreach (var route in new[]
        {
            new SettingsRoute("general", null),
            new SettingsRoute("deck", null),
            new SettingsRoute("cards", null),
            new SettingsRoute("notifications", null),
            new SettingsRoute("github", "account"),
            new SettingsRoute("gitlab", "instance"),
            new SettingsRoute("project", "site"),
            new SettingsRoute("arc", "arc"),
            new SettingsRoute("ddev", "shop"),
        })
        {
            window.Navigate(route);
            Equal(route.Page, window.CurrentPage);
        }
        window.Close();
    }

    private static void SettingsSourceHasNoVisibleTextLiterals()
    {
        var path = Path.Combine(RepositoryRoot(), "Windows", "DevDeck.Shell", "SettingsWindow.cs");
        var source = File.ReadAllText(path);
        var directText = new Regex("(?:Text|Content|Header|Title|ToolTip)\\s*=\\s*\\\"[A-Za-z]{2}", RegexOptions.CultureInvariant);
        True(!directText.IsMatch(source));
    }

    private static void SettingsTokensLeaveTheFormOnce()
    {
        var token = new TokenSubmission { Typed = "temporary-secret" };
        var account = JsonNode.Parse("{\"id\":\"sample\"}") ?? throw new Exception();
        var request = SettingsJson.Token("checkGitHubToken", account, token.Take());
        Equal(1, Regex.Matches(request, "temporary-secret", RegexOptions.CultureInvariant).Count);
        Equal("", token.Typed);
        Equal("", token.Take());
    }

    private static void SettingsWordsSubstituteNamedValue()
    {
        var words = new SettingsWords();
        words.Replace(Json("{\"words\":{\"_0\":{\"settings.remove.account.title\":\"Remove %@?\"}}}"));
        Equal("Remove Sample?", words.Get("settings.remove.account.title", "Sample"));
    }

    private static void SettingsAnswersStayWithTheirRequest()
    {
        var client = new SettingsClient();
        var first = 0;
        var second = 0;
        var ids = new List<string>();
        client.RequestSent += request => ids.Add(request.Id);
        client.Request(SettingsJson.Empty("checkLocalProject"), _ => first++);
        client.Request(SettingsJson.Empty("checkArcStack"), _ => second++);
        client.Receive(ids[1], Json("{\"check\":{\"_0\":{\"tone\":\"good\",\"state\":\"ok\",\"detail\":\"\"}}}"));
        Equal(0, first);
        Equal(1, second);
    }

    private static void SettingsCardsUseSettingsProtocol()
    {
        var client = new SettingsClient();
        var requests = new List<SettingsWireRequest>();
        client.RequestSent += requests.Add;
        client.BeginSession();
        True(requests.Any(request => request.Json == "{\"cards\":{}}"));
        client.Receive(
            "settings.cards",
            Json("{\"cards\":{\"_0\":[{\"id\":\"github.inbox\",\"title\":\"Inbox\",\"detail\":\"Notifications\",\"isEnabled\":true}]}}"));
        Equal("github.inbox", client.Cards?[0]?["id"]?.GetValue<string>());
        Equal(
            "{\"setCard\":{\"id\":\"github.inbox\",\"isEnabled\":false}}",
            SettingsJson.SetCard("github.inbox", false));
    }

    private static void TokenPageRequestsKeepAccountShape()
    {
        var account = JsonNode.Parse("{\"id\":\"sample\",\"host\":\"https://example.invalid\"}") ?? throw new Exception();
        Equal("{\"openGitHubTokenPage\":{}}", SettingsJson.Empty("openGitHubTokenPage"));
        Equal(
            "{\"openGitLabTokenPage\":{\"_0\":{\"id\":\"sample\",\"host\":\"https://example.invalid\"}}}",
            SettingsJson.Value("openGitLabTokenPage", account));
    }

    private static void DdevNameUsesDisplayTitle()
    {
        var client = new SettingsClient();
        client.Receive("words", Json("{\"words\":{\"_0\":{\"settings.window.title\":\"Settings\",\"account.name\":\"Name\"}}}"));
        client.Receive("list", Json("{\"list\":{\"_0\":{\"accounts\":[],\"projects\":[]}}}"));
        client.Receive("preferences", Json("{\"preferences\":{\"_0\":{\"language\":\"system\"}}}"));
        var window = TestSettingsWindow(client);
        window.Apply(client.Words, client.List, client.Cards, client.Preferences, null);
        window.Receive(Json("{\"ddevProject\":{\"_0\":{\"id\":\"shop\",\"name\":\"sample-shop\",\"title\":\"\",\"folder\":\"C:/Sample\",\"isEnabled\":true,\"browser\":{}}}}"));
        window.Navigate(new SettingsRoute("ddev", "shop"));
        window.Show();
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        True(Descendants((DependencyObject)window.Content).OfType<TextBox>()
            .Any(field => field.Text == "sample-shop"));
        window.Close();
    }

    private static void ChromiumLocalStateYieldsNamedProfiles()
    {
        var profiles = WindowsBrowserCatalog.ParseProfiles("""
            {"profile":{"info_cache":{
              "Profile 10":{"name":"Testing"},
              "Default":{"name":"Personal"},
              "Profile 2":{"name":"Work"},
              "Profile 3":{}
            }}}
            """);
        Equal("Default,Profile 2,Profile 3,Profile 10", string.Join(',', profiles.Select(profile => profile.Directory)));
        Equal("Personal,Work,Profile 3,Testing", string.Join(',', profiles.Select(profile => profile.Name)));
        True(WindowsBrowserCatalog.ParseProfiles("not json").Count == 0);
    }

    private static void BrowserLaunchPlansKeepChosenProfile()
    {
        IReadOnlyList<WindowsBrowserOption> browsers =
        [
            new WindowsBrowserOption("Edge", "MSEdge", @"C:\Program Files\Edge\msedge.exe", @"C:\Profile\Local State"),
        ];
        var profiled = PlatformEffects.BrowserPlan(
            "https://example.invalid", "MSEdge", "Profile 2", browsers);
        Equal(@"C:\Program Files\Edge\msedge.exe", profiled.Executable);
        Equal("--profile-directory=Profile 2,https://example.invalid", string.Join(',', profiled.Arguments));
        True(!profiled.UseShellExecute);

        var plain = PlatformEffects.BrowserPlan(
            "https://example.invalid", "MSEdge", null, browsers);
        Equal("https://example.invalid", string.Join(',', plain.Arguments));
    }

    private static void DockerLaunchesFromProgramFiles()
    {
        var plan = PlatformEffects.DockerPlan(@"C:\Program Files");
        Equal(@"C:\Program Files\Docker\Docker\Docker Desktop.exe", plan.Executable);
        Equal(0, plan.Arguments.Count);
        True(plan.UseShellExecute);
    }

    private static void TerminalPlansEnterWindowsAndWslFolders()
    {
        var windows = PlatformEffects.TerminalPlan(@"C:\Samples\Site", true);
        Equal("wt.exe", windows.Executable);
        Equal(@"-d,C:\Samples\Site", string.Join(',', windows.Arguments));

        var wsl = PlatformEffects.TerminalPlan(
            @"\\wsl.localhost\Ubuntu-24.04\home\sample\site", true);
        Equal("wt.exe", wsl.Executable);
        Equal(
            "wsl.exe,-d,Ubuntu-24.04,--cd,/home/sample/site",
            string.Join(',', wsl.Arguments));

        var fallback = PlatformEffects.TerminalPlan(@"C:\Samples\Site", false);
        Equal("cmd.exe", fallback.Executable);
        Equal(@"/K,cd,/d,C:\Samples\Site", string.Join(',', fallback.Arguments));
    }

    private static void PhoneQrBytesAreStable()
    {
        var first = PhonePopover.QrPng("http://192.168.1.20:3000");
        var second = PhonePopover.QrPng("http://192.168.1.20:3000");
        True(first.SequenceEqual(second));
        True(first.Length > 100);
        Equal("89504E470D0A1A0A", Convert.ToHexString(first[..8]));
    }

    private static void LoginItemUsesRunValueAndQuotedExecutable()
    {
        var registry = new RecordingLoginItemRegistry();
        var loginItem = new WindowsLoginItem(registry, @"C:\Tools\DevDeck\DevDeck.Shell.exe");
        Equal("DevDeck", WindowsLoginItem.ValueName);
        Equal(
            @"Software\Microsoft\Windows\CurrentVersion\Run",
            WindowsLoginItem.RegistryPath);
        True(loginItem.SetEnabled(true));
        Equal("\"C:\\Tools\\DevDeck\\DevDeck.Shell.exe\"", registry.Value);
        True(loginItem.IsEnabled());
    }

    private static void DisablingLoginItemDeletesItsValue()
    {
        var registry = new RecordingLoginItemRegistry
        {
            Value = "\"C:\\Tools\\DevDeck\\DevDeck.Shell.exe\"",
        };
        var loginItem = new WindowsLoginItem(registry, @"C:\Tools\DevDeck\DevDeck.Shell.exe");
        True(loginItem.SetEnabled(false));
        True(registry.Deleted);
        Equal<string?>(null, registry.Value);
    }

    private static void ForeignLoginItemIsOff()
    {
        var registry = new RecordingLoginItemRegistry
        {
            Value = "\"C:\\Old\\DevDeck.Shell.exe\"",
        };
        var loginItem = new WindowsLoginItem(registry, @"C:\Tools\DevDeck\DevDeck.Shell.exe");
        True(!loginItem.IsEnabled());
    }

    private static void FailedLoginItemWriteRestoresSwitch()
    {
        var client = new SettingsClient();
        client.Receive("words", Json("{\"words\":{\"_0\":{\"settings.window.title\":\"Settings\",\"settings.general.title\":\"General\",\"settings.general.startAtLogin\":\"Start at login\"}}}"));
        client.Receive("list", Json("{\"list\":{\"_0\":{\"accounts\":[],\"projects\":[]}}}"));
        client.Receive("preferences", Json("{\"preferences\":{\"_0\":{\"language\":\"system\"}}}"));
        var registry = new RecordingLoginItemRegistry { WriteFails = true };
        var loginItem = new WindowsLoginItem(registry, @"C:\Tools\DevDeck\DevDeck.Shell.exe");
        var window = new SettingsWindow(client, loginItem);
        window.Apply(client.Words, client.List, client.Cards, client.Preferences, null);
        window.Show();
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
        var toggle = Descendants((DependencyObject)window.Content)
            .OfType<CheckBox>()
            .Single(control => AutomationProperties.GetAutomationId(control) == "StartAtLogin");
        toggle.IsChecked = true;
        True(toggle.IsChecked == false);
        window.Close();
    }

    private static void LoginItemInstallerFlagIsParsed()
    {
        var options = ShellOptions.Parse(["--enable-login-item"]);
        True(options.EnableLoginItem);
        Equal<string?>(null, options.ReplayPath);
        Equal<DeveloperRequest?>(null, options.DeveloperRequest);
    }

    private static SettingsWindow TestSettingsWindow(SettingsClient client)
    {
        var loginItem = new WindowsLoginItem(
            new RecordingLoginItemRegistry(),
            @"C:\Tools\DevDeck\DevDeck.Shell.exe");
        return new SettingsWindow(client, loginItem);
    }

    private static JsonElement Json(string text)
    {
        using var document = JsonDocument.Parse(text);
        return document.RootElement.Clone();
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

    private static void SingleInstanceExcludesDuplicates()
    {
        var name = @"Local\DevDeck.Tests." + Guid.NewGuid();
        using (var first = new SingleInstance(name))
        {
            True(first.IsFirst);
            using var second = new SingleInstance(name);
            True(!second.IsFirst);
        }
        using var next = new SingleInstance(name);
        True(next.IsFirst);
    }

    private static void ReplayIgnoresQuit()
    {
        var surface = new RecordingSurface();
        var errors = new StringWriter();
        var previous = Console.Error;
        Console.SetError(errors);
        try
        {
            var coordinator = new ShellCoordinator(Dispatcher.CurrentDispatcher, "unused", surface);
            var golden = Path.Combine(RepositoryRoot(), "Tests", "EngineTests", "Golden", "session-en.expected.jsonl");
            coordinator.StartReplayAsync(golden).GetAwaiter().GetResult();
        }
        finally
        {
            Console.SetError(previous);
        }
        Equal(0, surface.Quits);
        True(errors.ToString().Contains("Replay ignored the quit effect.", StringComparison.Ordinal));
    }

    private static void ReplaySizesItsPanels()
    {
        var path = Path.Combine(Path.GetTempPath(), "devdeck-replay-" + Guid.NewGuid() + ".jsonl");
        File.WriteAllText(path,
            "{\"event\":\"panels.changed\",\"id\":\"1\",\"panels\":[" +
            "{\"card\":\"a\",\"change\":\"open\",\"frame\":[10,20,352,182]}," +
            "{\"card\":\"b\",\"change\":\"open\",\"frame\":[10,214,352,182]}," +
            "{\"card\":\"c\",\"change\":\"open\",\"frame\":[400,20,352,182]}]," +
            "\"protocolVersion\":2,\"revision\":1}\n");
        try
        {
            var surface = new RecordingSurface();
            var coordinator = new ShellCoordinator(Dispatcher.CurrentDispatcher, "unused", surface);
            coordinator.StartReplayAsync(path).GetAwaiter().GetResult();
            surface.Measure(new CardMeasurement("a", [352, 240]));
            var placed = surface.Panels.Last().ToDictionary(change => change.Card, change => change.Frame);
            Equal(240.0, placed["a"][3]);
            Equal(272.0, placed["b"][1]);
            True(!placed.ContainsKey("c"));

            // A later transcript frame with the old height does not undo the measured one.
            coordinator.StartReplayAsync(path).GetAwaiter().GetResult();
            var again = surface.Panels.Last().ToDictionary(change => change.Card, change => change.Frame);
            Equal(240.0, again["a"][3]);
            Equal(272.0, again["b"][1]);
        }
        finally
        {
            File.Delete(path);
        }
    }

    private sealed class RecordingSurface : IShellSurface
    {
        public int Quits { get; private set; }
        public List<IReadOnlyList<PanelChange>> Panels { get; } = [];
        public void Measure(CardMeasurement measurement) => CardMeasured?.Invoke(measurement);
#pragma warning disable CS0067
        public event Action<CardMeasurement>? CardMeasured;
        public event Action<CardMove>? CardMoved;
        public event Action<DeckCommand>? CommandInvoked;
        public event Action<LogWindowChange>? LogWindowChanged;
        public event Action<SettingsWireRequest>? SettingsRequested;
        public event Action<string>? IntentRequested;
        public event Action? DisplayConfigurationChanged;
#pragma warning restore CS0067
        public void BeginSession() { }
        public void ApplyDeck(DeckPresentation presentation) { }
        public void ApplyPanels(IReadOnlyList<PanelChange> panels) => Panels.Add(panels);
        public void UpdateCard(string card, JsonElement model, JsonElement menu, JsonElement stopped) { }
        public void UpdateStatus(JsonElement status) { }
        public void UpdateMenu(JsonElement menu) { }
        public void ShowNotifications(IReadOnlyList<DeckNotification> notifications) { }
        public void UpdateLog(string card, DeckLog log) { }
        public void OpenLogs(string card) { }
        public void CloseLogs(string card) { }
        public void UpdateSettings(string? id, JsonElement answer) { }
        public void UpdateSettingsUpdate(JsonElement update) { }
        public void OpenSettings(JsonElement effect) { }
        public void ApplySummonPreferences(SummonPreferences preferences) { }
        public void PresentDeck() { }
        public void OpenMenu() { }
        public void Quit() => Quits++;
        public void ShowStopped() { }
        public void Dispose() { }
    }

    private static void ProtocolTraceLeavesTokensOut()
    {
        var path = Path.Combine(Path.GetTempPath(), "devdeck-trace-" + Guid.NewGuid() + ".jsonl");
        try
        {
            var options = ShellOptions.Parse(["--trace", path]);
            Equal<string?>(Path.GetFullPath(path), options.TracePath);
            using (var trace = new ProtocolTrace(options.TracePath!))
            {
                trace.Sent("{\"intent\":\"session.start\"}");
                trace.Sent("{\"intent\":\"settings\",\"request\":{\"checkGitHubToken\":{\"typed\":\"secret-value\"}}}");
                trace.Received("{\"event\":\"panels.changed\"}");
            }
            var lines = File.ReadAllLines(path);
            Equal(3, lines.Length);
            True(lines[0].Contains(" > {\"intent\":\"session.start\"}", StringComparison.Ordinal));
            True(!File.ReadAllText(path).Contains("secret-value", StringComparison.Ordinal));
            True(lines[2].Contains(" < {\"event\":\"panels.changed\"}", StringComparison.Ordinal));
        }
        finally
        {
            File.Delete(path);
        }
    }

    private static void SecondLaunchSignalsFirst()
    {
        var name = @"Local\DevDeck.Tests." + Guid.NewGuid();
        using var first = new SingleInstance(name);
        using var received = new System.Threading.ManualResetEventSlim();
        first.OnSignal(received.Set);
        using (var second = new SingleInstance(name))
        {
            True(!second.IsFirst);
            second.SignalFirst();
        }
        True(received.Wait(TimeSpan.FromSeconds(5)));
    }

    private static void ReplayInstanceIsSeparate()
    {
        const string user = "S-1-5-21-0";
        True(SingleInstance.Name(true, user) != SingleInstance.Name(false, user));
        var name = @"Local\DevDeck.Tests." + Guid.NewGuid();
        using var live = new SingleInstance(name + ".Live");
        using var replay = new SingleInstance(name + ".Replay");
        True(live.IsFirst && replay.IsFirst);
    }

    private static void ShutdownKeepsDispatcherResponsive()
    {
        var ready = new System.Threading.Tasks.TaskCompletionSource();
        var exits = 0;
        var previousContext = System.Threading.SynchronizationContext.Current;
        System.Threading.SynchronizationContext.SetSynchronizationContext(
            new DispatcherSynchronizationContext(Dispatcher.CurrentDispatcher));
        var shutdown = new AsyncShutdown(() => ready.Task, () => exits++);
        var completion = shutdown.Request();
        True(ReferenceEquals(completion, shutdown.Request()));
        Equal(0, exits);
        var frame = new DispatcherFrame();
        Dispatcher.CurrentDispatcher.BeginInvoke(() =>
        {
            ready.SetResult();
            Dispatcher.CurrentDispatcher.BeginInvoke(() => frame.Continue = false);
        });
        Dispatcher.PushFrame(frame);
        System.Threading.SynchronizationContext.SetSynchronizationContext(previousContext);
        True(completion.IsCompletedSuccessfully);
        Equal(1, exits);
    }

    private static void ScrollBarsAndComboBoxesFitTheSurface()
    {
        WindowsTheme.EnsureLoaded();
        var bar = new System.Windows.Controls.Primitives.ScrollBar { Orientation = Orientation.Vertical };
        var host = new Border { Width = 40, Height = 200, Child = bar };
        host.Measure(new Size(40, 200));
        host.Arrange(new Rect(0, 0, 40, 200));
        host.UpdateLayout();
        Equal(12.0, bar.ActualWidth);
        var thumb = Descendants(bar).OfType<System.Windows.Controls.Primitives.Thumb>().Single();
        True(Descendants(thumb).OfType<Border>().Any(border => border.CornerRadius.TopLeft == 3));
        var combo = new ComboBox { Style = WindowsTheme.Style("SettingsComboBox") };
        Equal(0.0, combo.Padding.Top);
        Equal(0.0, combo.Padding.Bottom);
    }

    private static void MenuTitlesShareOneLine()
    {
        var presenter = new MenuPresenter(_ => { });
        presenter.Update(RuntimeMenuValue("runtime-menu-en.expected.jsonl", "menu", last: true));
        var items = presenter.View.Items.OfType<MenuItem>().Where(item => item.Tag is DeckMenuItemModel).ToList();
        True(items.Any(item => ((DeckMenuItemModel)item.Tag).IsIndented));
        True(items.All(item => item.Padding.Left == 8));
    }

    private static void DialogButtonsCarryTheirTone()
    {
        Button Confirm(DeckMenuDialogModel model)
        {
            var window = MenuDialogs.Build(model, null, out _, out _);
            var button = Descendants((FrameworkElement)window.Content).OfType<Button>().Single(b => Equals(b.Content, model.Confirm));
            window.Close();
            return button;
        }
        var destructive = Confirm(new DeckMenuDialogModel("Power off", "Every project stops.", "Power off", "Cancel", true));
        True(destructive.IsDefault);
        True(SameColour(WindowsTheme.Tone("alert"), destructive.BorderBrush));
        var primary = Confirm(new DeckMenuDialogModel("Save", "Saves the arrangement.", "Save", "Cancel"));
        True(primary.IsDefault);
        True(!SameColour(WindowsTheme.Brush("ControlFill"), primary.Background));
        True(!SameColour(WindowsTheme.Brush("TextPrimary"), primary.Foreground));
    }

    private static void MenuInputOwnerIsInvisible()
    {
        var owner = MenuPresenter.CreateInputOwner();
        True(owner.AllowsTransparency);
        Equal(WindowStyle.None, owner.WindowStyle);
        Equal(0.0, owner.Opacity);
        True(!owner.ShowInTaskbar);
        owner.Close();
    }

    private static void MenusDismissOutsideApplication()
    {
        var presenter = new MenuPresenter(_ => { });
        presenter.Update(RuntimeMenuValue("runtime-menu-en.expected.jsonl", "menu", last: true));
        presenter.Open();
        True(!presenter.View.StaysOpen);
        // A menu taller than the screen scrolls instead of running off its bottom.
        Equal(SystemParameters.WorkArea.Height, presenter.View.MaxHeight);
        True(Descendants(presenter.View).OfType<ScrollViewer>().Any());
        var source = (System.Windows.Interop.HwndSource)PresentationSource.FromVisual(presenter.View);
        SendMenuMessage(source.Handle, 0x001C, 0, 0);
        PumpMenuDispatcher();
        True(!presenter.View.IsOpen);
        presenter.Close();
    }

    private static void MenuRefreshPreservesOpenPopup()
    {
        PumpMenuDispatcher();
        var presenter = new MenuPresenter(_ => { });
        var first = RuntimeMenuValue("runtime-menu-en.expected.jsonl", "menu", last: false);
        var next = RuntimeMenuValue("runtime-menu-en.expected.jsonl", "menu", last: true);
        presenter.Update(first);
        presenter.Open();
        if (!presenter.View.IsOpen)
        {
            throw new Exception("Popup closed while opening.");
        }
        var item = presenter.View.Items[0];
        presenter.Update(next);
        if (!presenter.View.IsOpen)
        {
            throw new Exception("Popup closed while refreshing.");
        }
        if (!ReferenceEquals(item, presenter.View.Items[0]))
        {
            throw new Exception("Refresh replaced the open menu item.");
        }
        // The deferred refresh runs in the Closed handler, so the test waits for that event
        // rather than for a deadline.
        var closed = new DispatcherFrame();
        presenter.View.Closed += (_, _) => closed.Continue = false;
        presenter.View.IsOpen = false;
        Dispatcher.PushFrame(closed);
        Equal(DeckMenuEntryModel.ParseList(next).Count, presenter.View.Items.Count);
        presenter.Close();
    }

    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SendMessageW")]
    private static extern nint SendMenuMessage(nint window, int message, nint parameter, nint data);

    private static void PumpMenuDispatcher()
    {
        var frame = new DispatcherFrame();
        Dispatcher.CurrentDispatcher.BeginInvoke(
            () => frame.Continue = false,
            DispatcherPriority.ApplicationIdle);
        Dispatcher.PushFrame(frame);
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
            // The first frame names the assertion, since most of them carry no message.
            var frame = exception.StackTrace?.Split('\n')[0].Trim();
            Console.WriteLine($"  fail {name}: {exception.Message} {frame}");
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

    private sealed class RecordingLoginItemRegistry : ILoginItemRegistry
    {
        public string? Value { get; set; }
        public bool Deleted { get; private set; }
        public bool WriteFails { get; init; }

        public string? Read()
        {
            return Value;
        }

        public void Write(string value)
        {
            if (WriteFails)
            {
                throw new UnauthorizedAccessException("denied");
            }
            Value = value;
        }

        public void Delete()
        {
            Deleted = true;
            Value = null;
        }
    }

    private sealed class RecordingLogWindow : ILogWindow
    {
        public event EventHandler? Closed;
        public int Activations { get; private set; }

        public void Show()
        {
        }

        public void Activate()
        {
            Activations++;
        }

        public void Close()
        {
            Closed?.Invoke(this, EventArgs.Empty);
        }

        public void SetTitle(string title)
        {
        }

        public void Update(DeckLog log)
        {
        }
    }

    private sealed class RecordingToastPlatform : IToastPlatform
    {
        public event Action<string>? Activated;
        public List<string> Payloads { get; } = [];

        public void Show(string xml)
        {
            Payloads.Add(xml);
        }

        public void Activate(string id)
        {
            Activated?.Invoke(id);
        }

        public void Dispose()
        {
        }
    }
}
