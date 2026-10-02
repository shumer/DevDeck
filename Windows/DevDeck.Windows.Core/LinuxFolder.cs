namespace DevDeck.Windows.Core;

public static class LinuxFolder
{
    public static string? FromWindows(string distribution, string folder)
    {
        foreach (var host in new[] { "wsl.localhost", "wsl$" })
        {
            var prefix = @"\\" + host + @"\" + distribution;
            if (folder.Equals(prefix, StringComparison.OrdinalIgnoreCase)) return "/";
            if (folder.StartsWith(prefix + @"\", StringComparison.OrdinalIgnoreCase))
            {
                var path = "/" + folder[(prefix.Length + 1)..].Replace('\\','/');
                return LinuxPath.IsAbsolute(path) ? path : null;
            }
        }
        return null;
    }
}
