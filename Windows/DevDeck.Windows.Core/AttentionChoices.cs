namespace DevDeck.Windows.Core;

/// One logical attention row; selection never performs its action.
public sealed record AttentionChoice(string Kind, bool Enabled, AttentionAction? Action = null, InboxReadTarget? InboxRead = null)
{
    public bool IsAlternate => Kind is "read" or "dismiss";
}

public static class AttentionChoices
{
    public static AttentionChoice Primary(AttentionItem item) => new("primary",
        item.Enabled && item.Action is { Kind: not "none" }, item.Action);

    public static AttentionChoice Alternate(AttentionItem item)
    {
        // A URL-less notification still has a permitted read action.
        if (item.InboxRead is { } target) return new("read", true, InboxRead: target);
        if (item.Dismissible && item.Action is { Kind: "showCard", CardID: { } id }
            && !string.IsNullOrWhiteSpace(id) && id.Length <= 128 && !id.Any(char.IsControl))
            return new("dismiss", true, item.Action);
        return new("none", false);
    }

    public static AttentionChoice Select(AttentionItem item, bool alternate)
    {
        var choice = alternate ? Alternate(item) : null;
        return choice is { Kind: not "none" } ? choice : Primary(item);
    }
}
