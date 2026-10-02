using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace DevDeck.Windows.Core;

/// <summary>Per-user Generic Credentials, persisted only on this Windows machine.</summary>
public sealed class WindowsTokenStore
{
    private readonly CredentialPresenceRead? presenceRead;
    private readonly Action<nint>? presenceFree;

    public WindowsTokenStore() { }
    internal WindowsTokenStore(CredentialPresenceRead read, Action<nint> free)
    {
        presenceRead = read ?? throw new ArgumentNullException(nameof(read));
        presenceFree = free ?? throw new ArgumentNullException(nameof(free));
    }

    /// <summary>Checks bounded credential metadata without decoding or copying token contents.</summary>
    public bool HasToken(RemoteAccountSettings account)
    {
        account.Validate();
        if (presenceRead is null && !OperatingSystem.IsWindows()) return false;
        nint pointer = 0;
        try
        {
            CredentialPresenceRead read = presenceRead ?? CredRead;
            if (!read(account.CredentialTarget, 1, 0, out pointer) || pointer == 0) return false;
            // Blittable pointers deliberately avoid marshaling credential strings or blob bytes.
            var credential = Marshal.PtrToStructure<CredentialPresenceHeader>(pointer);
            return credential.Type == 1 && credential.BlobSize <= 2560
                && (credential.BlobSize == 0 || credential.Blob != 0);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ExternalException
            or ArgumentException or InvalidOperationException or DllNotFoundException or EntryPointNotFoundException
            or PlatformNotSupportedException)
        {
            return false;
        }
        finally
        {
            if (pointer != 0)
            {
                Action<nint> free = presenceFree ?? CredFree;
                free(pointer);
            }
        }
    }

    public string? Read(RemoteAccountSettings account)
    {
        account.Validate();
        if (!CredRead(account.CredentialTarget, 1, 0, out var pointer))
        {
            if (Marshal.GetLastWin32Error() == 1168) return null;
            throw new HostFailure("credentialReadFailed", "Windows Credential Manager could not read this account token.");
        }
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(pointer);
            if (credential.BlobSize > 2560) throw new HostFailure("credentialTooLarge", "The stored account token exceeds the supported size.");
            var bytes = new byte[credential.BlobSize];
            try { Marshal.Copy(credential.Blob, bytes, 0, bytes.Length); return Encoding.UTF8.GetString(bytes); }
            finally { CryptographicOperations.ZeroMemory(bytes); Marshal.Copy(bytes, 0, credential.Blob, bytes.Length); }
        }
        finally { CredFree(pointer); }
    }
    public void Write(RemoteAccountSettings account, string? token)
    {
        account.Validate();
        if (token is null)
        {
            if (!CredDelete(account.CredentialTarget, 1, 0) && Marshal.GetLastWin32Error() != 1168)
                throw new HostFailure("credentialDeleteFailed", "Windows Credential Manager could not remove this account token.");
            return;
        }
        var bytes = Encoding.UTF8.GetBytes(token);
        if (bytes.Length == 0 || bytes.Length > 2560 || token.Any(char.IsControl))
        {
            CryptographicOperations.ZeroMemory(bytes);
            throw new HostFailure("tokenInvalid", "Enter a nonempty account token of at most 2560 bytes without control characters.");
        }
        var pointer = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, pointer, bytes.Length);
            var credential = new Credential { Type = 1, TargetName = account.CredentialTarget, BlobSize = (uint)bytes.Length,
                Blob = pointer, Persist = 2, UserName = "DevDeck" };
            if (!CredWrite(ref credential, 0)) throw new HostFailure("credentialWriteFailed", "Windows Credential Manager could not save this account token.");
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes); Marshal.Copy(bytes, 0, pointer, bytes.Length); Marshal.FreeHGlobal(pointer);
        }
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public uint Flags; public uint Type;
        public string? TargetName; public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint BlobSize; public nint Blob; public uint Persist; public uint AttributeCount;
        public nint Attributes; public string? TargetAlias; public string? UserName;
    }
    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CredRead(string target, uint type, uint flags, out nint credential);
    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CredWrite(ref Credential credential, uint flags);
    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CredDelete(string target, uint type, uint flags);
    [DllImport("advapi32.dll")] private static extern void CredFree(nint credential);
}

internal delegate bool CredentialPresenceRead(string target, uint type, uint flags, out nint credential);

// CREDENTIALW ABI, with pointer fields rather than string marshaling. No pointee is read.
[StructLayout(LayoutKind.Sequential)]
internal struct CredentialPresenceHeader
{
    public uint Flags; public uint Type;
    public nint TargetName; public nint Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public uint BlobSize; public nint Blob; public uint Persist; public uint AttributeCount;
    public nint Attributes; public nint TargetAlias; public nint UserName;
}
