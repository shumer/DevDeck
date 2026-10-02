using System;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Controls;
using System.Windows.Media;

namespace DevDeck.Windows.App;

// Synthetic startup facts only; no machine/user path or disk metadata is exported into artwork.
internal static class SettingsProvenanceSamples
{
    internal static readonly string[] Variants = ["native", "hosted", "unknown", "long", "assembly"];
    internal static Task<SettingsWindow> CreateAsync(DeckController controller, string variant)
    {
        var facts = Facts(variant);
        var window = new SettingsWindow(controller, live:false, tokenAvailable:_ => false,
            runningBuildInfoProvider:() => facts) {
            Width=880, Height=variant=="long" ? 440 : 720, FontSize=variant=="long" ? 18 : 13
        };
        // The owned renderer supplies Show/layout. Center the new block without changing settings.
        window.Loaded += (_, _) => {
            window.UpdateLayout();
            var first = Descendants(window.Page).OfType<TextBox>()
                .FirstOrDefault(field => Equals(field.Tag, "settings.runningBuild.version"));
            first?.BringIntoView();
        };
        return Task.FromResult(window);
    }
    internal static RunningBuildInfo Facts(string variant)
    {
        var module = Guid.Parse("4471848b-8f81-49ab-a5c6-3fed049148dc");
        const string version = "0.0.0-windows-dev+owned-synthetic-copy";
        return variant switch {
            "native" => new(version, "1.0.0.0", module, @"C:\Fixture\DevDeck\DevDeck.Windows.exe", @"C:\Fixture\DevDeck\DevDeck.Windows.dll"),
            "hosted" => new(version, "1.0.0.0", module, @"C:\Fixture\dotnet\dotnet.exe", @"C:\Fixture\Hosted\DevDeck.Windows.dll"),
            "unknown" => RunningBuildInfo.Unknown,
            "long" => new(version, "1.0.0.0", module,
                @"C:\Fixture\" + string.Concat(Enumerable.Repeat("Разработка-日本語-é-🧭\\", 35)) + "DevDeck.Windows.exe",
                @"C:\Fixture\" + string.Concat(Enumerable.Repeat("Модули-日本語-é-🧭\\", 35)) + "DevDeck.Windows.dll"),
            "assembly" => new(null, "7.6.5.4", module, @"C:\Fixture\Fallback\DevDeck.Windows.exe", ""),
            _ => throw new ArgumentException("Unknown synthetic running-copy variant.", nameof(variant))
        };
    }
    private static System.Collections.Generic.IEnumerable<System.Windows.DependencyObject> Descendants(System.Windows.DependencyObject root)
    {
        yield return root;
        for (var index=0; index<VisualTreeHelper.GetChildrenCount(root); index++)
            foreach (var child in Descendants(VisualTreeHelper.GetChild(root,index))) yield return child;
    }
}
