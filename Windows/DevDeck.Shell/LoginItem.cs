using Microsoft.Win32;
using System.Security;

namespace DevDeck.Shell;

public interface ILoginItemRegistry
{
    string? Read();
    void Write(string value);
    void Delete();
}

public sealed class WindowsLoginItem
{
    public const string RegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public const string ValueName = "DevDeck";

    private readonly ILoginItemRegistry registry;
    private readonly string executablePath;

    public WindowsLoginItem(ILoginItemRegistry registry, string executablePath)
    {
        this.registry = registry;
        this.executablePath = Path.GetFullPath(executablePath);
    }

    public static WindowsLoginItem Current()
    {
        var executable = Environment.ProcessPath
            ?? throw new InvalidOperationException("The executable path is unavailable.");
        return new WindowsLoginItem(new CurrentUserLoginItemRegistry(), executable);
    }

    public static string Command(string executablePath)
    {
        return $"\"{Path.GetFullPath(executablePath)}\"";
    }

    public bool IsEnabled()
    {
        try
        {
            return string.Equals(
                registry.Read(),
                Command(executablePath),
                StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception exception) when (IsRegistryError(exception))
        {
            Console.Error.WriteLine($"Start at login could not be read: {exception.Message}");
            return false;
        }
    }

    public bool SetEnabled(bool enabled)
    {
        try
        {
            if (enabled)
            {
                registry.Write(Command(executablePath));
            }
            else
            {
                registry.Delete();
            }
            return true;
        }
        catch (Exception exception) when (IsRegistryError(exception))
        {
            Console.Error.WriteLine($"Start at login could not be changed: {exception.Message}");
            return false;
        }
    }

    private static bool IsRegistryError(Exception exception)
    {
        return exception is IOException or UnauthorizedAccessException or SecurityException;
    }
}

internal sealed class CurrentUserLoginItemRegistry : ILoginItemRegistry
{
    public string? Read()
    {
        using var root = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
        using var key = root.OpenSubKey(WindowsLoginItem.RegistryPath);
        return key?.GetValue(WindowsLoginItem.ValueName) as string;
    }

    public void Write(string value)
    {
        using var root = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
        using var key = root.CreateSubKey(WindowsLoginItem.RegistryPath, writable: true)
            ?? throw new IOException("The startup registry key could not be opened.");
        key.SetValue(WindowsLoginItem.ValueName, value, RegistryValueKind.String);
    }

    public void Delete()
    {
        using var root = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
        using var key = root.OpenSubKey(WindowsLoginItem.RegistryPath, writable: true);
        key?.DeleteValue(WindowsLoginItem.ValueName, throwOnMissingValue: false);
    }
}
