using System.Text;

namespace DevDeck.Shell;

// A developer's record of every protocol line, for questions only the timing of the lines answers.
public sealed class ProtocolTrace : IDisposable
{
    private const string LeftOut = "{\"traced\":\"a request carrying a typed token is left out\"}";
    private readonly StreamWriter writer;
    private readonly object gate = new();

    public ProtocolTrace(string path)
    {
        writer = new StreamWriter(path, append: true, new UTF8Encoding(false)) { AutoFlush = true };
    }

    public void Received(string line)
    {
        Write('<', line);
    }

    public void Sent(string line)
    {
        Write('>', Redact(line));
    }

    // A token travels once, typed, inside a check request; that line never reaches a file.
    public static string Redact(string line)
    {
        return line.Contains("\"typed\"", StringComparison.Ordinal) ? LeftOut : line;
    }

    public void Dispose()
    {
        lock (gate)
        {
            writer.Dispose();
        }
    }

    private void Write(char direction, string line)
    {
        lock (gate)
        {
            writer.WriteLine($"{DateTimeOffset.Now:O} {direction} {line}");
        }
    }
}
