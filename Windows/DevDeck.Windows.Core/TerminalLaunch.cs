using System.Diagnostics;

namespace DevDeck.Windows.Core;

public static class TerminalLaunch
{
    public static ProcessStartInfo Create(string distribution, string path, bool preferWindowsTerminal = true)
        => CreateCommand(distribution, path, null, preferWindowsTerminal);

    public static string? ContainerFromSource(string? source)
    {
        const string prefix = "docker logs ";
        var value = source?.StartsWith(prefix, StringComparison.Ordinal) == true ? source[prefix.Length..] : null;
        return value is not null && System.Text.RegularExpressions.Regex.IsMatch(value, @"\A[A-Za-z0-9][A-Za-z0-9_.-]{0,255}\z") ? value : null;
    }
    public static ProcessStartInfo CreateLogs(ProjectReference project, string? filePath = null, bool preferWindowsTerminal = true, string? containerName = null)
    {
        if (filePath is not null && !LinuxPath.IsAbsolute(filePath)) throw new ArgumentException("An absolute Linux log path is required.", nameof(filePath));
        var command = project.Kind switch {
            "ddev" => "ddev logs -s web -f",
            "arc" when containerName is not null && ContainerFromSource("docker logs " + containerName) == containerName => "docker logs --tail 400 --follow " + Quote(containerName),
            "local" when filePath is not null => "tail -n 400 -F -- " + Quote(filePath),
            _ => throw new HostFailure("logFileUnavailable", "This project has no log file to follow yet.")
        };
        return CreateCommand(project.Distribution, project.Path, "exec ${SHELL:-/bin/bash} -lic " + Quote(command), preferWindowsTerminal);
    }

    private static string Quote(string value) => "'" + value.Replace("'", "'\"'\"'") + "'";

    private static ProcessStartInfo CreateCommand(string distribution, string path, string? command, bool preferWindowsTerminal)
    {
        _ = WorkerClient.WslStart(distribution, path);
        // WT initializes its Windows process before WSL applies --cd. Never inherit a
        // versioned application directory or the cwd of an already-running Terminal.
        var windowsDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (!Directory.Exists(windowsDirectory)) windowsDirectory = Environment.SystemDirectory;
        // Windows Terminal has its own ';' command grammar even without a shell.
        // Use direct WSL for those literal names rather than encoding them into WT commands.
        var terminal = preferWindowsTerminal && !windowsDirectory.Contains(';') && !distribution.Contains(';') && !path.Contains(';') && !path.Contains('"')
            && command?.Contains(';') != true && command?.Contains('"') != true;
        var start = new ProcessStartInfo(terminal ? "wt.exe" : "wsl.exe") {
            UseShellExecute = false, CreateNoWindow = false, WorkingDirectory = windowsDirectory
        };
        if (terminal) foreach (var argument in new[] { "new-tab", "--startingDirectory", windowsDirectory, "wsl.exe" }) start.ArgumentList.Add(argument);
        foreach (var argument in new[] { "--distribution", distribution, "--cd", path }) start.ArgumentList.Add(argument);
        if (command is not null) foreach (var argument in new[] { "--exec", "/bin/sh", "-c", command }) start.ArgumentList.Add(argument);
        return start;
    }
}
