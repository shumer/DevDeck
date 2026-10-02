using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json;
using DevDeck.Windows.Core;

internal static class SettingsSidebarChecks
{
    internal static Task RunRedAsync(Func<string, Func<Task>, Task> check) => check(
        "settings sidebar project titles are globally natural across kinds without rewriting saved arrays", ProjectOrdering);

    internal static async Task RunAsync(Func<string, Func<Task>, Task> check)
    {
        await RunRedAsync(check);
        await check("settings sidebar account titles form one natural group across providers and preserve hidden metadata", AccountOrdering);
        await check("settings sidebar multilingual numbers and Swedish letters use the supplied culture", CultureOrdering);
        await check("settings sidebar case and numeric equivalents preserve saved input ties instead of deck ID ties", StableTies);
        await check("settings sidebar consumes each source once and leaves deck ordering independent", IndependentProjection);
        await check("credential presence accepts bounded and zero-byte metadata without reading token or string pointers", PresentMetadata);
        await check("credential presence reports missing and null allocations safely and frees failed-read allocations", MissingMetadata);
        await check("credential presence reports unreadable metadata safely and frees allocations on native-call exceptions", UnreadableMetadata);
        await check("credential presence rejects oversized stored blobs without touching their contents", OversizedMetadata);
        await check("credential presence rejects nongeneric metadata and still frees its allocation", WrongTypeMetadata);
        await check("credential presence rejects nonempty blobs without a pointer and frees metadata", MissingBlobPointer);
        await check("credential presence uses exact account target and validates configuration before native access", AccountPresenceIdentity);
    }

    private static Task ProjectOrdering()
    {
        var cards = new[] {
            Card("arc.zeta", "arc", "Zeta2"), Card("local.ten", "local", "Site10"),
            Card("ddev.two", "ddev", "Site2"), Card("local.alpha", "local", "Alpha2") with { Enabled=false },
            Card("arc.alpha", "arc", "Alpha10")
        };
        var before = JsonSerializer.Serialize(cards, WorkerProtocol.Json);
        var ordered = SettingsSidebarOrdering.Projects(cards, CultureInfo.GetCultureInfo("en-US"));
        Require(JsonSerializer.Serialize(cards, WorkerProtocol.Json) == before, "Sidebar ordering rewrote saved project metadata/order.");
        Require(ordered.Select(card => card.Project.Id).SequenceEqual(new[] { "local.alpha", "arc.alpha", "ddev.two", "local.ten", "arc.zeta" }),
            "Flat settings sidebar must show Alpha2 before Alpha10 and Site2 before Site10 across Arc/DDEV/local; actual="
            + string.Join(",", ordered.Select(card => card.Project.Id)) + ".");
        Require(ReferenceEquals(ordered[0], cards[3]) && !ordered[0].Enabled && ordered.Length == cards.Length,
            "Sidebar projection recreated or dropped the hidden configured project.");
        return Task.CompletedTask;
    }

    private static Task AccountOrdering()
    {
        var accounts = new[] {
            Account("gitlab.ten", "gitlab", "Site10"), Account("github.zeta", "github", "Zeta2"),
            Account("github.alpha", "github", "Alpha10"), Account("github.two", "github", "Site2"),
            Account("gitlab.alpha", "gitlab", "Alpha2") with { Enabled=false, Browser="firefox", BrowserProfile="Stored legacy profile" }
        };
        var before = JsonSerializer.Serialize(accounts, WorkerProtocol.Json);
        var ordered = SettingsSidebarOrdering.Accounts(accounts, CultureInfo.GetCultureInfo("en-US"));
        Require(ordered.Select(account => account.Id).SequenceEqual(new[] {
            "gitlab.alpha", "github.alpha", "github.two", "gitlab.ten", "github.zeta"
        }), "Account sidebar kept provider groups or lexical numbers.");
        Require(JsonSerializer.Serialize(accounts, WorkerProtocol.Json) == before && ReferenceEquals(ordered[0], accounts[4])
            && !ordered[0].Enabled && ordered[0].BrowserProfile == "Stored legacy profile", "Account projection changed or dropped saved metadata.");
        return Task.CompletedTask;
    }

    private static Task CultureOrdering()
    {
        foreach (var (culture, title) in new[] { ("en-US", "Project"), ("ru-RU", "Проект"), ("de-DE", "Aufgabe"),
            ("fr-FR", "Révision"), ("es-ES", "Revisión"), ("it-IT", "Revisione") })
        {
            var comparison = CultureInfo.GetCultureInfo(culture);
            var cards = new[] { Card("ten", "arc", title + "10"), Card("arabic.two", "local", title + "٢"), Card("two", "ddev", title + "2") };
            var accounts = new[] { Account("ten", "github", title + "10"), Account("arabic.two", "gitlab", title + "٢"), Account("two", "github", title + "2") };
            Require(SettingsSidebarOrdering.Projects(cards, comparison).Select(card => card.Project.Id).SequenceEqual(new[] { "arabic.two", "two", "ten" })
                && SettingsSidebarOrdering.Accounts(accounts, comparison).Select(account => account.Id).SequenceEqual(new[] { "arabic.two", "two", "ten" }),
                culture + " sidebar numbers or equivalent-script stable ties changed.");
        }
        var swedish = new[] { "örebro", "älg", "zebra", "alfa10", "åland", "alfa2" }
            .Select((title, index) => Card("swedish." + index, index % 2 == 0 ? "arc" : "local", title)).ToArray();
        Require(SettingsSidebarOrdering.Projects(swedish, CultureInfo.GetCultureInfo("sv-SE")).Select(card => card.Title)
            .SequenceEqual(new[] { "alfa2", "alfa10", "zebra", "åland", "älg", "örebro" }), "Explicit Swedish letter order was ignored.");
        return Task.CompletedTask;
    }

    private static Task StableTies()
    {
        var culture = CultureInfo.GetCultureInfo("en-US");
        var cards = new[] { Card("z", "local", "Same2"), Card("b", "ddev", "SAME٢"), Card("a", "arc", "same2") };
        var accounts = new[] { Account("z", "gitlab", "Same2"), Account("b", "github", "SAME٢"), Account("a", "gitlab", "same2") };
        foreach (var reverse in new[] { false, true })
        {
            var projectSource = reverse ? cards.Reverse().ToArray() : cards;
            var accountSource = reverse ? accounts.Reverse().ToArray() : accounts;
            var expected = reverse ? new[] { "a", "b", "z" } : new[] { "z", "b", "a" };
            Require(SettingsSidebarOrdering.Projects(projectSource, culture).Select(card => card.Project.Id).SequenceEqual(expected)
                && SettingsSidebarOrdering.Accounts(accountSource, culture).Select(account => account.Id).SequenceEqual(expected),
                "Equivalent titles were reordered by permanent ID, kind or provider rather than saved input.");
        }
        return Task.CompletedTask;
    }

    private static Task IndependentProjection()
    {
        var cards = new[] { Card("local.two", "local", "Site2"), Card("arc.ten", "arc", "Site10") };
        var deckBefore = CardOrdering.Projects(cards).Select(card => card.Project.Id).ToArray();
        var projectSource = new SinglePass<CardSettings>(cards);
        var accountSource = new SinglePass<RemoteAccountSettings>([Account("ten", "github", "Site10"), Account("two", "gitlab", "Site2")]);
        Require(SettingsSidebarOrdering.Projects(projectSource).Select(card => card.Project.Id).SequenceEqual(new[] { "local.two", "arc.ten" })
            && SettingsSidebarOrdering.Accounts(accountSource).Select(account => account.Id).SequenceEqual(new[] { "two", "ten" }),
            "Default current-culture natural order failed.");
        Require(projectSource.Enumerations == 1 && accountSource.Enumerations == 1
            && CardOrdering.Projects(cards).Select(card => card.Project.Id).SequenceEqual(deckBefore)
            && deckBefore.SequenceEqual(new[] { "arc.ten", "local.two" }), "Sidebar ordering mutated deck ordering or enumerated a source repeatedly.");
        Require(SettingsSidebarOrdering.Projects([]).Length == 0 && SettingsSidebarOrdering.Accounts([]).Length == 0,
            "Empty sidebar groups gained invented entries.");
        return Task.CompletedTask;
    }

    private static Task PresentMetadata()
    {
        Require(Marshal.SizeOf<CredentialPresenceHeader>() == (IntPtr.Size == 8 ? 80 : 52)
            && Marshal.OffsetOf<CredentialPresenceHeader>(nameof(CredentialPresenceHeader.BlobSize)).ToInt32() == (IntPtr.Size == 8 ? 32 : 24)
            && Marshal.OffsetOf<CredentialPresenceHeader>(nameof(CredentialPresenceHeader.Blob)).ToInt32() == (IntPtr.Size == 8 ? 40 : 28),
            "Credential metadata does not match the platform CREDENTIALW ABI.");
        foreach (var (size, blob) in new (uint, nint)[] { (0, 0), (0, 1), (1, 1), (2560, 1) })
        {
            // Invalid pointees are intentional: presence may inspect the header, never its content.
            using var native = new FakePresence(Header(size, blob));
            Require(native.Store.HasToken(Account("owned", "github", "Owned")), "Valid bounded stored metadata was not present.");
            Require(native.Reads == 1 && native.Frees == 1 && native.MetadataUnchanged,
                "Presence failed to free once or changed credential metadata/content.");
        }
        return Task.CompletedTask;
    }

    private static Task MissingMetadata()
    {
        foreach (var result in new[] { false, true })
        {
            using var empty = new FakePresence(null, result);
            Require(!empty.Store.HasToken(Account("owned", "github", "Owned")) && empty.Reads == 1 && empty.Frees == 0,
                "Missing/null native allocation was marked present or freed.");
        }
        using var allocated = new FakePresence(Header(1, 1), result:false);
        Require(!allocated.Store.HasToken(Account("owned", "github", "Owned")) && allocated.Frees == 1 && allocated.MetadataUnchanged,
            "Failed native read retained its returned allocation.");
        return Task.CompletedTask;
    }

    private static Task UnreadableMetadata()
    {
        foreach (var error in new Exception[] { new IOException("Owned unreadable"), new UnauthorizedAccessException("Owned denied"),
            new ExternalException("Owned native failure"), new DllNotFoundException("Owned unavailable") })
        {
            using var native = new FakePresence(Header(1, 1), error:error);
            Require(!native.Store.HasToken(Account("owned", "github", "Owned")) && native.Reads == 1 && native.Frees == 1
                && native.MetadataUnchanged, "Unreadable credential was not safely unavailable/freed: " + error.GetType().Name);
        }
        using var empty = new FakePresence(null, error:new UnauthorizedAccessException("Owned denied"));
        Require(!empty.Store.HasToken(Account("owned", "github", "Owned")) && empty.Frees == 0, "Unavailable native read freed an absent allocation.");
        return Task.CompletedTask;
    }

    private static Task OversizedMetadata()
    {
        foreach (var size in new uint[] { 2561, uint.MaxValue })
        {
            using var native = new FakePresence(Header(size, 1));
            Require(!native.Store.HasToken(Account("owned", "github", "Owned")) && native.Frees == 1 && native.MetadataUnchanged,
                "Oversized metadata was read as present or not freed.");
        }
        return Task.CompletedTask;
    }

    private static Task WrongTypeMetadata()
    {
        foreach (var type in new uint[] { 0, 2, uint.MaxValue })
        {
            var header = Header(1, 1); header.Type = type;
            using var native = new FakePresence(header);
            Require(!native.Store.HasToken(Account("owned", "github", "Owned")) && native.Frees == 1 && native.MetadataUnchanged,
                "Nongeneric credential metadata was accepted or not freed.");
        }
        return Task.CompletedTask;
    }

    private static Task MissingBlobPointer()
    {
        foreach (var size in new uint[] { 1, 2560 })
        {
            using var native = new FakePresence(Header(size, 0));
            Require(!native.Store.HasToken(Account("owned", "github", "Owned")) && native.Frees == 1 && native.MetadataUnchanged,
                "Nonempty credential without a blob pointer was accepted or not freed.");
        }
        return Task.CompletedTask;
    }

    private static Task AccountPresenceIdentity()
    {
        var account = Account("owned", "github", "Owned");
        var identities = new[] { account, account with { Label="Renamed", Enabled=false }, account with { Endpoint="https://github.enterprise.example" },
            account with { Provider="gitlab" }, account with { Id="other" } };
        var targets = new List<string>();
        foreach (var identity in identities)
        {
            using var native = new FakePresence(Header(1, 1));
            Require(native.Store.HasToken(identity) && native.Target == identity.CredentialTarget && native.Type == 1 && native.Flags == 0,
                "Presence queried a different credential target/type/flags.");
            targets.Add(native.Target!);
        }
        Require(targets[0] == targets[1] && targets.Distinct(StringComparer.Ordinal).Count() == 4,
            "Account presentation changed credential ownership, or provider/ID/endpoint reused a foreign target.");
        foreach (var invalid in new[] { account with { Id="" }, account with { Provider="unknown" }, account with { Endpoint="http://github.com" } })
        {
            using var native = new FakePresence(Header(1, 1));
            var rejected = false;
            try { native.Store.HasToken(invalid); } catch (InvalidDataException) { rejected = true; }
            Require(rejected && native.Reads == 0 && native.Frees == 0, "Invalid account reached native credential access before validation.");
        }
        return Task.CompletedTask;
    }

    private static CredentialPresenceHeader Header(uint size, nint blob) => new() {
        Type=1, BlobSize=size, Blob=blob, TargetName=1, Comment=1, TargetAlias=1, UserName=1, Attributes=1
    };

    private sealed class FakePresence : IDisposable
    {
        private nint allocation;
        private readonly bool result;
        private readonly Exception? error;
        private readonly byte[] original;
        internal WindowsTokenStore Store { get; }
        internal int Reads { get; private set; }
        internal int Frees { get; private set; }
        internal bool MetadataUnchanged { get; private set; }
        internal string? Target { get; private set; }
        internal uint Type { get; private set; }
        internal uint Flags { get; private set; }

        internal FakePresence(CredentialPresenceHeader? header, bool result=true, Exception? error=null)
        {
            this.result=result; this.error=error;
            original = header.HasValue ? new byte[Marshal.SizeOf<CredentialPresenceHeader>()] : [];
            if (header.HasValue)
            {
                allocation=Marshal.AllocHGlobal(original.Length);
                Marshal.Copy(original, 0, allocation, original.Length);
                Marshal.StructureToPtr(header.Value, allocation, false);
                Marshal.Copy(allocation, original, 0, original.Length);
            }
            Store=new WindowsTokenStore(Read, Free);
        }

        private bool Read(string target, uint type, uint flags, out nint pointer)
        {
            Reads++; Target=target; Type=type; Flags=flags; pointer=allocation;
            if (error is not null) throw error;
            return result;
        }

        private void Free(nint pointer)
        {
            Frees++;
            Require(pointer != 0 && pointer == allocation && Frees == 1, "Credential metadata was freed twice or with a foreign pointer.");
            var after=new byte[original.Length]; Marshal.Copy(pointer, after, 0, after.Length);
            MetadataUnchanged=after.SequenceEqual(original);
            Marshal.FreeHGlobal(pointer); allocation=0;
        }

        public void Dispose() { if (allocation != 0) { Marshal.FreeHGlobal(allocation); allocation=0; } }
    }

    private sealed class SinglePass<T>(T[] items) : IEnumerable<T>
    {
        internal int Enumerations { get; private set; }
        public IEnumerator<T> GetEnumerator()
        {
            Require(++Enumerations == 1, "Sidebar projection enumerated its saved source more than once.");
            return ((IEnumerable<T>)items).GetEnumerator();
        }
        System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator() => GetEnumerator();
    }

    private static CardSettings Card(string id, string kind, string title) => new(new(id, "Owned Linux", kind, "/owned/" + id), title);
    private static RemoteAccountSettings Account(string id, string provider, string label) => new(id, label, provider,
        provider == "github" ? "https://api.github.com" : "https://gitlab.com", [], []);
    private static void Require(bool value, string message) { if (!value) throw new IOException(message); }
}
