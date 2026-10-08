using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace DevDeck.Shell;

public static class CredentialTarget
{
    public static string ForAccount(string account)
    {
        if (string.IsNullOrWhiteSpace(account)
            || account.Any(character => !char.IsAsciiLetterOrDigit(character) && character is not '-' and not '_'))
        {
            throw new ArgumentException(nameof(account));
        }
        return "DevDeck/" + account;
    }
}

public static class CredentialManager
{
    private const int GenericCredential = 1;
    private const int LocalMachinePersistence = 2;

    public static string? Read(string account)
    {
        if (!CredRead(CredentialTarget.ForAccount(account), GenericCredential, 0, out var pointer))
        {
            return Marshal.GetLastWin32Error() == 1168 ? null : throw new Win32Exception();
        }
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(pointer);
            return credential.CredentialBlobSize == 0
                ? ""
                : Marshal.PtrToStringUni(credential.CredentialBlob, credential.CredentialBlobSize / 2);
        }
        finally
        {
            CredFree(pointer);
        }
    }

    public static void Write(string account, ReadOnlySpan<char> secret)
    {
        var characters = secret.ToArray();
        var bytes = Encoding.Unicode.GetBytes(characters);
        Array.Clear(characters);
        var blob = Marshal.AllocCoTaskMem(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new Credential
            {
                Type = GenericCredential,
                TargetName = CredentialTarget.ForAccount(account),
                CredentialBlobSize = bytes.Length,
                CredentialBlob = blob,
                Persist = LocalMachinePersistence,
                UserName = account,
            };
            if (!CredWrite(ref credential, 0))
            {
                throw new Win32Exception();
            }
        }
        finally
        {
            Array.Clear(bytes);
            Marshal.FreeCoTaskMem(blob);
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public int Flags;
        public int Type;
        public string TargetName;
        public string? Comment;
        public long LastWritten;
        public int CredentialBlobSize;
        public nint CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public nint Attributes;
        public string? TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredRead(string target, int type, int flags, out nint credential);

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredWrite(ref Credential credential, int flags);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(nint credential);
}

public static class CredentialCommand
{
    public static bool Matches(string[] arguments) => arguments.Length == 2 && arguments[0] == "--set-token";

    public static int Run(string account)
    {
        var characters = new List<char>();
        while (true)
        {
            var key = Console.ReadKey(intercept: true);
            if (key.Key == ConsoleKey.Enter)
            {
                break;
            }
            if (key.Key == ConsoleKey.Backspace)
            {
                if (characters.Count > 0)
                {
                    characters.RemoveAt(characters.Count - 1);
                }
                continue;
            }
            if (key.KeyChar != '\0' && !char.IsControl(key.KeyChar))
            {
                characters.Add(key.KeyChar);
            }
        }
        try
        {
            if (characters.Count == 0)
            {
                return 2;
            }
            CredentialManager.Write(account, CollectionsMarshal.AsSpan(characters));
            return 0;
        }
        finally
        {
            CollectionsMarshal.AsSpan(characters).Clear();
        }
    }
}
