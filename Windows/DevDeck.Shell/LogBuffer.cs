namespace DevDeck.Shell;

public sealed record LogBufferChange(bool Reset, IReadOnlyList<string> Added);

public sealed class LogBuffer
{
    private readonly List<string> lines = [];

    public IReadOnlyList<string> Lines => lines;
    public string? Source { get; private set; }
    public string? Detail { get; private set; }

    public LogBufferChange Apply(DeckLog model)
    {
        Source = model.Source;
        Detail = model.Detail;
        var prefix = model.Lines.Count >= lines.Count;
        for (var index = 0; prefix && index < lines.Count; index++)
        {
            prefix = string.Equals(lines[index], model.Lines[index], StringComparison.Ordinal);
        }

        if (!prefix)
        {
            lines.Clear();
            lines.AddRange(model.Lines);
            return new LogBufferChange(true, lines.ToArray());
        }

        var added = model.Lines.Skip(lines.Count).ToArray();
        lines.AddRange(added);
        return new LogBufferChange(false, added);
    }
}
