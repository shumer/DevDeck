using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace DevDeck.Shell;

public sealed class EngineClient : IAsyncDisposable
{
    private readonly Process process;
    private readonly SemaphoreSlim inputLock = new(1, 1);
    private readonly TaskCompletionSource completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private bool started;
    private bool stopping;

    public EngineClient(string executablePath)
    {
        process = new Process
        {
            StartInfo = new ProcessStartInfo
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
            },
            EnableRaisingEvents = true,
        };
        process.Exited += (_, _) => completion.TrySetResult();
    }

    public event Action<DeckEvent>? EventReceived;

    public Task Completion => completion.Task;

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

    public async Task SendAsync(string line)
    {
        if (!started || stopping || process.HasExited)
        {
            return;
        }

        await inputLock.WaitAsync();
        try
        {
            if (stopping || process.HasExited)
            {
                return;
            }

            await process.StandardInput.WriteLineAsync(line);
            await process.StandardInput.FlushAsync();
        }
        catch (IOException) when (stopping || process.HasExited)
        {
        }
        catch (InvalidOperationException) when (stopping || process.HasExited)
        {
        }
        finally
        {
            inputLock.Release();
        }
    }

    public async ValueTask DisposeAsync()
    {
        stopping = true;
        if (started && !process.HasExited)
        {
            process.StandardInput.Close();
            try
            {
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
                await process.WaitForExitAsync(timeout.Token);
            }
            catch (OperationCanceledException)
            {
                process.Kill();
            }
        }

        process.Dispose();
        inputLock.Dispose();
    }

    private async Task ReadOutputAsync()
    {
        try
        {
            while (await process.StandardOutput.ReadLineAsync() is { } line)
            {
                try
                {
                    EventReceived?.Invoke(DeckEvent.Parse(line));
                }
                catch (JsonException)
                {
                    Console.Error.WriteLine("Invalid engine event.");
                }
            }
        }
        finally
        {
            completion.TrySetResult();
        }
    }
}
