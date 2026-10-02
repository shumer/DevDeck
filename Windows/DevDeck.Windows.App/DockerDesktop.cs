using System;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace DevDeck.Windows.App;

internal static class DockerDesktop
{
    internal static void Open()
    {
        var executable = new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData) }
            .Select(root => Path.Combine(root, "Docker", "Docker", "Docker Desktop.exe")).FirstOrDefault(File.Exists)
            ?? throw new IOException(Text.L("windows.dockerMissing"));
        Process.Start(new ProcessStartInfo(executable) { UseShellExecute = false });
    }
}
