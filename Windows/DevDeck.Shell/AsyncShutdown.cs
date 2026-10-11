using System.Threading.Tasks;

namespace DevDeck.Shell;

public sealed class AsyncShutdown(Func<Task> stop, Action exit)
{
    private Task? completion;

    public Task Request()
    {
        return completion ??= RunAsync();
    }

    private async Task RunAsync()
    {
        try
        {
            await stop();
        }
        finally
        {
            exit();
        }
    }
}
