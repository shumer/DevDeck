using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Input;
using System.Windows.Media;
using DevDeck.Shell;

namespace DevDeck.Shell.Tests;

public static class StatePreview
{
    public static int Show(Application application, string fixturePath, string state)
    {
        var card = ProjectCard(fixturePath);
        card.Width = 352;
        var window = new Window
        {
            Title = "DevDeck style state preview",
            WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize,
            SizeToContent = SizeToContent.WidthAndHeight,
            ShowInTaskbar = false,
            Background = new SolidColorBrush(Color.FromRgb(11, 20, 36)),
            Content = card,
            Left = 100,
            Top = 100,
        };
        if (state == "focus")
        {
            window.Loaded += (_, _) => FocusStartWithKeyboardTraversal(window);
        }
        else if (state is "hover" or "pressed")
        {
            window.Loaded += (_, _) => SetButtonsFocusable(card, false);
        }
        return application.Run(window);
    }

    private static FrameworkElement ProjectCard(string fixturePath)
    {
        foreach (var line in File.ReadLines(fixturePath))
        {
            var message = DeckEvent.Parse(line);
            if (message.Card == "project.windows" && message.Model is { } model)
            {
                return CardRenderer.Create(model, _ => { });
            }
        }
        throw new InvalidDataException("The Windows sample project was not found.");
    }

    private static void FocusStartWithKeyboardTraversal(Window window)
    {
        var focused = Keyboard.FocusedElement as UIElement;
        if (focused is null)
        {
            window.MoveFocus(new TraversalRequest(FocusNavigationDirection.First));
            focused = Keyboard.FocusedElement as UIElement;
        }
        for (var index = 0; index < 12 && focused is not null; index++)
        {
            if (focused is DependencyObject dependencyObject &&
                AutomationProperties.GetName(dependencyObject) == "Start")
            {
                return;
            }
            focused.MoveFocus(new TraversalRequest(FocusNavigationDirection.Next));
            focused = Keyboard.FocusedElement as UIElement;
        }
    }

    private static void SetButtonsFocusable(DependencyObject root, bool focusable)
    {
        if (root is System.Windows.Controls.Button button)
        {
            button.Focusable = focusable;
        }
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            SetButtonsFocusable(VisualTreeHelper.GetChild(root, index), focusable);
        }
    }
}
