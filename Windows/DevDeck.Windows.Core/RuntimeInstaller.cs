using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;

namespace DevDeck.Windows.Core;

/// The Windows application provisions its packaged runtime; the user never opens a Linux terminal.
public static class RuntimeInstaller
{
    public static async Task<string> PackageNameAsync(string distribution, CancellationToken cancellation = default)
    {
        _ = WorkerClient.WslStart(distribution, "/validation");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        deadline.CancelAfter(TimeSpan.FromSeconds(15));
        return PackageName((await RunAsync(distribution, ["uname", "-m"], null, deadline.Token)).Trim());
    }
    public static string PackageName(string architecture) => architecture switch {
        "aarch64" or "arm64" => "worker-linux-arm64.tar",
        "x86_64" or "amd64" => "worker-linux-x64.tar",
        _ => throw new HostFailure("workerArchitectureUnsupported", "This WSL architecture does not have a supported DevDeck worker package.")
    };
    public static async Task<WorkerSettings> InstallAsync(string distribution, string archive, CancellationToken cancellation = default)
    {
        _ = WorkerClient.WslStart(distribution, "/validation");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        deadline.CancelAfter(TimeSpan.FromMinutes(2));
        var home = (await RunAsync(distribution, ["printenv", "HOME"], null, deadline.Token)).Trim();
        if (!LinuxPath.IsAbsolute(home)) throw new HostFailure("workerHomeInvalid", "WSL did not return an absolute home directory.");
        using var source = File.OpenRead(archive);
        var digest = Convert.ToHexString(await SHA256.HashDataAsync(source, deadline.Token)).ToLowerInvariant();
        source.Position = 0;
        var directory = home.TrimEnd('/') + "/.local/share/devdeck/workers/" + digest[..20];
        const string installed = "if [ -f \"$1/.installed\" ] && [ -x \"$1/run-worker\" ]; then printf installed; fi";
        if (await RunAsync(distribution, ["sh", "-c", installed, "devdeck-runtime", directory], null, deadline.Token) == "installed")
            return new WorkerSettings(distribution, directory);
        // Literal shell source, with all variable values in argv; never interpolate paths into shell code.
        const string install = "set -eu; mkdir -p -- \"$1\"; tar --no-same-owner -xf - -C \"$1\"; chmod +x \"$1/run-worker\" \"$1/DevDeckWorker\"; touch \"$1/.installed\"";
        await RunAsync(distribution, ["sh", "-c", install, "devdeck-runtime", directory], source, deadline.Token);
        return new WorkerSettings(distribution, directory);
    }

    private static async Task<string> RunAsync(string distribution, string[] arguments, Stream? input, CancellationToken cancellation)
    {
        var start = new ProcessStartInfo("wsl.exe") { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "--distribution", distribution, "--cd", "~", "--exec" }.Concat(arguments)) start.ArgumentList.Add(argument);
        Process process;
        try { process = Process.Start(start) ?? throw new HostFailure("workerSetupFailed", "Cannot provision the WSL runtime."); }
        catch (System.ComponentModel.Win32Exception) { throw new HostFailure("wslUnavailable", "WSL could not be launched."); }
        using var owned = process;
        var output = new MemoryStream();
        var reading = process.StandardOutput.BaseStream.CopyToAsync(output, cancellation);
        var draining = process.StandardError.BaseStream.CopyToAsync(Stream.Null, cancellation);
        try
        {
            if (input is not null) await input.CopyToAsync(process.StandardInput.BaseStream, cancellation);
            process.StandardInput.Close();
            await process.WaitForExitAsync(cancellation);
            await Task.WhenAll(reading, draining);
            if (process.ExitCode != 0) throw new HostFailure("workerSetupFailed", "Cannot install the worker runtime in the selected WSL distribution.");
            if (output.Length > 4096) throw new HostFailure("workerSetupInvalid", "Unexpected runtime setup response.");
            return Encoding.UTF8.GetString(output.ToArray());
        }
        catch (OperationCanceledException)
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            throw;
        }
        finally { output.Dispose(); }
    }
}
