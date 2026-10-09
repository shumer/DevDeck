using System.Text.Json;
using System.Windows;
using System.Windows.Controls;

namespace DevDeck.Shell;

public static class CardRenderer
{
    public static bool CanRender(JsonElement model)
    {
        if (model.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        var kinds = model.EnumerateObject().ToArray();
        return kinds.Length == 1 && kinds[0].Name is
            "reviewList" or "inbox" or "actions" or "workInFlight" or "project";
    }

    public static FrameworkElement Create(JsonElement model, Action<DeckCommand> command)
    {
        var kind = model.EnumerateObject().Single();
        return kind.Name switch
        {
            "reviewList" => WindowsCardRenderer.ReviewList(kind.Value, command),
            "inbox" => WindowsCardRenderer.Inbox(kind.Value, command),
            "actions" => WindowsCardRenderer.ActionRuns(kind.Value, command),
            "workInFlight" => WindowsCardRenderer.WorkInFlight(kind.Value, command),
            "project" => WindowsCardRenderer.Project(kind.Value, command),
            _ => new Grid(),
        };
    }

    public static FrameworkElement CreateStopped(JsonElement stopped, JsonElement? status)
    {
        var content = WindowsCardRenderer.Stopped(stopped, _ => { });
        if (status is { } stoppedStatus)
        {
            content.ToolTip = JsonModel.String(stoppedStatus, "tooltip");
            content.SetValue(
                System.Windows.Automation.AutomationProperties.NameProperty,
                JsonModel.String(stoppedStatus, "accessibilityValue"));
        }

        return content;
    }
}
