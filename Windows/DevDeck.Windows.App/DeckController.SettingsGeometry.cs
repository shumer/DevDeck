using System;
using System.Windows;
using System.Windows.Interop;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal sealed partial class DeckController
{
    private readonly Action<DeckSettings> settingsGeometryCommit;

    internal bool SaveSettingsWindowGeometry(SettingsWindow owner, SettingsWindowGeometry geometry, nint expectedHwnd)
    {
        // A completed resize belongs to this current, visible, normal HWND. This
        // precise write never enters the project-action gate or rebuilds owners.
        if (!application.Dispatcher.CheckAccess() || closing || shuttingDown
            || !ReferenceEquals(settingsWindow, owner) || owner.GeometryOwnerClosed
            || !owner.GeometryPersistenceEnabled || !owner.IsVisible || owner.WindowState != WindowState.Normal
            || expectedHwnd == 0 || new WindowInteropHelper(owner).Handle != expectedHwnd) return false;
        if (geometry is null || !SettingsGeometry.Valid(geometry))
            throw new ArgumentException("Invalid settings window size.", nameof(geometry));
        if (Settings.SettingsWindow == geometry) return true;
        var value = Settings with { SettingsWindow = geometry };
        settingsGeometryCommit(value);
        Settings = value;
        return true;
    }
}
