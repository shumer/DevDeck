using System.Security.Principal;
using System.Threading;

namespace DevDeck.Shell;

public sealed class SingleInstance : IDisposable
{
    private readonly Mutex mutex;

    public SingleInstance(string? name = null)
    {
        // The handle keeps the per user instance alive without thread ownership.
        name ??= @"Local\DevDeck.Shell." + WindowsIdentity.GetCurrent().User?.Value;
        mutex = new Mutex(false, name, out var created);
        IsFirst = created;
    }

    public bool IsFirst { get; }

    public void Dispose()
    {
        mutex.Dispose();
    }
}
