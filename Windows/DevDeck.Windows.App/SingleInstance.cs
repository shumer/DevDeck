using System;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace DevDeck.Windows.App;

/// A normal deck has one owner; a second launch summons the first deck.
internal sealed class SingleInstance : IDisposable
{
    private readonly Mutex mutex;
    private readonly EventWaitHandle signal;
    private RegisteredWaitHandle? waiting;
    internal bool Acquired { get; }
    internal SingleInstance(string settingsPath)
    {
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(System.IO.Path.GetFullPath(settingsPath).ToUpperInvariant())));
        signal = new EventWaitHandle(false, EventResetMode.AutoReset, "Local\\DevDeck.Summon." + key);
        mutex = new Mutex(false, "Local\\DevDeck.Owner." + key);
        try { Acquired = mutex.WaitOne(0); } catch (AbandonedMutexException) { Acquired = true; }
        if (!Acquired) signal.Set();
    }
    internal void Listen(Action summon) => waiting = ThreadPool.RegisterWaitForSingleObject(signal, (_, _) => summon(), null, Timeout.Infinite, executeOnlyOnce: false);
    public void Dispose()
    {
        waiting?.Unregister(null); if (Acquired) mutex.ReleaseMutex(); mutex.Dispose(); signal.Dispose();
    }
}
