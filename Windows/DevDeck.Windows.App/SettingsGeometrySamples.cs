using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal static class SettingsGeometrySamples
{
    // The existing sample renderer supplies its synthetic controller/configuration.
    // live:false makes every layout change inert; availability is also explicitly fake.
    internal static async Task<SettingsWindow> CreateAsync(DeckController controller,string scene)
    {
        var window=new SettingsWindow(controller,live:false,tokenAvailable:_=>false) {
            Width=SettingsGeometry.MinimumWidth,Height=SettingsGeometry.MinimumHeight,FontSize=18
        };
        var page=scene switch {
            "deck"=>"deck",
            "project"=>controller.Settings.Cards.FirstOrDefault(card=>card.Project.Kind=="local") is{} project
                ?"project:"+project.Project.Id:"new-project",
            "account" or "failure"=>controller.Settings.AccountList.FirstOrDefault() is{} account
                ?"account:"+account.Id:"new-account",
            _=>"general"
        };
        await window.SelectPageAsync(page);
        if(scene=="failure")window.PresentGeometryFailure(new IOException("Owned synthetic size-save failure."));
        return window;
    }
}
