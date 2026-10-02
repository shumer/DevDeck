using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// <summary>One shared installed-browser and friendly Chromium-profile selector.</summary>
internal sealed class BrowserPicker
{
    private sealed record Choice(string ID, string Label);
    private sealed record ProfileChoice(string? Directory, string Label);
    private readonly Func<string, BrowserProfile[]> readProfiles;
    private string? profileValue;
    private bool updating;

    internal ComboBox Picker { get; } = new() { DisplayMemberPath = "Label", SelectedValuePath = "ID", Padding = new(5,3,5,3), MinHeight = 28 };
    internal ComboBox Profile { get; } = new() { DisplayMemberPath = "Label", SelectedValuePath = "Directory", Padding = new(5,3,5,3), MinHeight = 28 };
    internal string BrowserID => Picker.SelectedValue as string ?? "system";
    // Preserve a saved profile even when the selected browser cannot offer it. Merely editing
    // another setting must not erase an absent browser/profile, or an old Firefox profile.
    internal string? SelectedProfile => profileValue;
    internal event EventHandler? ValueChanged;

    internal BrowserPicker(string browserID, string? profile, IEnumerable<InstalledBrowser>? browsers = null, Func<string, BrowserProfile[]>? profiles = null)
    {
        readProfiles = profiles ?? BrowserCatalog.Profiles;
        var installed = (browsers ?? BrowserCatalog.InstalledBrowsers()).ToArray();
        var choices = installed.Select(browser => new Choice(browser.ID, browser.Name)).ToList();
        choices.Insert(0, new("system", Text.L("windows.defaultBrowser")));
        if (browserID != "system" && !choices.Any(choice => choice.ID == browserID))
            choices.Add(new(browserID, BrowserCatalog.Name(browserID) + " · " + Text.L("windows.unavailable")));
        Picker.ItemsSource = choices;
        Picker.SelectedValue = browserID;
        System.Windows.Automation.AutomationProperties.SetName(Picker, Text.L("account.openLinksIn"));
        System.Windows.Automation.AutomationProperties.SetName(Profile, Text.L("windows.profile"));
        ReloadProfiles(profile);
        Picker.SelectionChanged += (_, _) => {
            if (updating) return;
            ReloadProfiles(null);
            ValueChanged?.Invoke(this, EventArgs.Empty);
        };
        Profile.SelectionChanged += (_, _) => {
            if (updating) return;
            profileValue = (Profile.SelectedItem as ProfileChoice)?.Directory;
            ValueChanged?.Invoke(this, EventArgs.Empty);
        };
    }

    private void ReloadProfiles(string? selecting)
    {
        updating = true;
        try {
            profileValue = selecting;
            var profiles = BrowserCatalog.SupportsProfiles(BrowserID) ? readProfiles(BrowserID) : [];
            var choices = profiles.Select(profile => new ProfileChoice(profile.Directory, profile.Name)).ToList();
            if (BrowserCatalog.SupportsProfiles(BrowserID) && !string.IsNullOrWhiteSpace(selecting) && !choices.Any(choice => choice.Directory == selecting))
                choices.Add(new(selecting, selecting + " · " + Text.L("windows.unavailable")));
            choices.Insert(0, new(null, Text.L("windows.lastUsedProfile")));
            Profile.ItemsSource = choices;
            Profile.SelectedItem = choices.FirstOrDefault(choice => choice.Directory == selecting) ?? choices[0];
            Profile.Visibility = BrowserCatalog.SupportsProfiles(BrowserID) && choices.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
        }
        finally { updating = false; }
    }
}
