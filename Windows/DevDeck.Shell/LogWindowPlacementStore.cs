using System.Text.Json;

namespace DevDeck.Shell;

public sealed record LogWindowPlacement(double Left, double Top, double Width, double Height);

public sealed class LogWindowPlacementStore
{
    private readonly string path;

    public LogWindowPlacementStore()
    {
        path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "DevDeck",
            "shell-log-windows.json");
    }

    public LogWindowPlacement? Read(string card)
    {
        try
        {
            if (!File.Exists(path))
            {
                return null;
            }
            var values = JsonSerializer.Deserialize<Dictionary<string, LogWindowPlacement>>(File.ReadAllText(path));
            return values is not null && values.TryGetValue(card, out var value) ? value : null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public void Write(string card, LogWindowPlacement placement)
    {
        try
        {
            var values = File.Exists(path)
                ? JsonSerializer.Deserialize<Dictionary<string, LogWindowPlacement>>(File.ReadAllText(path)) ?? []
                : [];
            values[card] = placement;
            Directory.CreateDirectory(Path.GetDirectoryName(path) ?? throw new IOException());
            File.WriteAllText(path, JsonSerializer.Serialize(values));
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
        catch (JsonException)
        {
        }
    }
}
