using System.Security.Principal;
using System.Threading;

namespace DevDeck.Shell;

public sealed class SingleInstance : IDisposable
{
    private readonly Mutex mutex;
    private readonly EventWaitHandle present;
    private RegisteredWaitHandle? registration;

    public SingleInstance(string name)
    {
        // The handle keeps the instance alive without thread ownership.
        mutex = new Mutex(false, name, out var created);
        present = new EventWaitHandle(false, EventResetMode.AutoReset, name + ".Present");
        IsFirst = created;
    }

    public bool IsFirst { get; }

    // A replay has its own instance, so it neither blocks nor is blocked by the live deck.
    public static SingleInstance For(bool replay)
    {
        return new SingleInstance(Name(replay, WindowsIdentity.GetCurrent().User?.Value));
    }

    public static string Name(bool replay, string? user)
    {
        return (replay ? @"Local\DevDeck.Shell.Replay." : @"Local\DevDeck.Shell.") + user;
    }

    public void SignalFirst()
    {
        present.Set();
    }

    public void OnSignal(Action received)
    {
        // A signal sent before this registration stays set and arrives here.
        registration?.Unregister(null);
        registration = ThreadPool.RegisterWaitForSingleObject(
            present,
            (_, _) => received(),
            null,
            Timeout.Infinite,
            executeOnlyOnce: false);
    }

    public void Dispose()
    {
        registration?.Unregister(null);
        present.Dispose();
        mutex.Dispose();
    }
}
