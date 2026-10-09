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
        _ = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        if (arguments.Length == 4 && arguments[0] == "--capture-reference")
        {
            ReferenceScreenshots.Generate(
                Path.GetFullPath(arguments[1]),
                Path.GetFullPath(arguments[2]),
                double.Parse(arguments[3], System.Globalization.CultureInfo.InvariantCulture));
            Application.Current.Shutdown();
            return 0;
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
        foreach (var style in new[] { "FluentButton", "HeaderIconButton", "RowButton", "ChipButton" })
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
}
