using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace DevDeck.Shell;

public sealed class EngineClient : IAsyncDisposable
{
    private readonly Process process;
    private readonly SemaphoreSlim inputLock = new(1, 1);
    private readonly JsonSerializerOptions jsonOptions = new(JsonSerializerDefaults.Web);
    private int nextId;
    private volatile bool started;
    private volatile bool stopping;

    public EngineClient(string executablePath, string? configurationPath)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = executablePath,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardInputEncoding = new UTF8Encoding(false),
            StandardOutputEncoding = new UTF8Encoding(false),
            StandardErrorEncoding = new UTF8Encoding(false),
        };
        if (configurationPath is not null)
        {
            startInfo.ArgumentList.Add("--config");
            startInfo.ArgumentList.Add(configurationPath);
        }
        process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        process.Exited += (_, _) =>
        {
            if (!stopping)
            {
                Exited?.Invoke();
            }
        };
    }

    public event Action<EngineEvent>? EventReceived;
    public event Action? Exited;

    public void Start()
    {
        if (!process.Start())
        {
            throw new InvalidOperationException();
        }
        started = true;
        _ = ReadOutputAsync();
        _ = process.StandardError.ReadToEndAsync();
    }

    public async Task SendAsync(string intent, object? fields = null)
    {
        if (!started || stopping || process.HasExited)
        {
            return;
        }
        var payload = new Dictionary<string, object?>
        {
            ["protocolVersion"] = 2,
            ["id"] = Interlocked.Increment(ref nextId).ToString(),
            ["intent"] = intent,
        };
        if (fields is not null)
        {
            foreach (var property in fields.GetType().GetProperties())
            {
                payload[JsonNamingPolicy.CamelCase.ConvertName(property.Name)] = property.GetValue(fields);
            }
        }
        var line = JsonSerializer.Serialize(payload, jsonOptions);
        await inputLock.WaitAsync();
        try
        {
            if (stopping || process.HasExited)
            {
                return;
            }
            try
            {
                await process.StandardInput.WriteLineAsync(line);
                await process.StandardInput.FlushAsync();
            }
            catch (IOException) when (stopping || process.HasExited)
            {
            }
            catch (InvalidOperationException) when (stopping || process.HasExited)
            {
            }
        }
        finally
        {
            inputLock.Release();
        }
    }

    private async Task ReadOutputAsync()
    {
        while (await process.StandardOutput.ReadLineAsync() is { } line)
        {
            try
            {
                var message = JsonSerializer.Deserialize<EngineEvent>(line, jsonOptions);
                if (message is not null)
                {
                    EventReceived?.Invoke(message);
                }
            }
            catch (JsonException)
            {
            }
        }
    }

    public async ValueTask DisposeAsync()
    {
        stopping = true;
        if (!started)
        {
            process.Dispose();
            inputLock.Dispose();
            return;
        }
        try
        {
            process.StandardInput.Close();
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            await process.WaitForExitAsync(timeout.Token);
        }
        catch
        {
            if (!process.HasExited)
            {
                process.Kill();
            }
        }
        process.Dispose();
        inputLock.Dispose();
    }
}
