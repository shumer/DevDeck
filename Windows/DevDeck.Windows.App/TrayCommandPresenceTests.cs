using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using DevDeck.Windows.Core;
using Forms = System.Windows.Forms;

namespace DevDeck.Windows.App;

/// Own synthetic controller/menu/settings only. No clicks, visible tray or external service.
internal static class TrayCommandPresenceTests
{
    internal static Task RunAsync(Application application,List<object> checks)
    {
        var path=Path.Combine(Path.GetTempPath(),"devdeck-tray-commands-"+Guid.NewGuid().ToString("N")+".json");
        var store=new SettingsStore(path);
        store.Save(new(1,[new("Test Linux","/tmp/devdeck-tray-command-runtime")],[],
            Accounts:[new("synthetic","Synthetic GitHub","github","https://api.github.com",[],[])],
            RemoteCards:[new("legacy.pulls","Synthetic pull requests","pullRequests","Test Linux",["synthetic"])],
            Language:"en",Notifications:false));
        var controller=new DeckController(application,store,live:false);
        var previousLanguage=Text.Language;
        try {
            var build=typeof(DeckController).GetMethod("BuildMenu",BindingFlags.Instance | BindingFlags.NonPublic)
                ?? throw new IOException("Production tray menu producer is missing.");
            var persisted=File.ReadAllBytes(store.Path);
            var original=JsonSerializer.Serialize(controller.Settings,WorkerProtocol.Json);
            // Expected strings come from the frozen Mac menu resources, independently of
            // production Text.L lookups. Top-level tags distinguish actions from card labels.
            var labels=new Dictionary<string,string[]>(StringComparer.Ordinal) {
                ["en"]=["Open pull requests in browser","Refresh now","Arrangements"],
                ["ru"]=["Открыть pull requests в браузере","Обновить сейчас","Раскладки"],
                ["de"]=["Pull Requests im Browser öffnen","Jetzt aktualisieren","Anordnungen"],
                ["fr"]=["Ouvrir les pull requests dans le navigateur","Actualiser maintenant","Dispositions"],
                ["es"]=["Abrir los pull requests en el navegador","Actualizar ahora","Disposiciones"],
                ["it"]=["Apri i pull request nel browser","Aggiorna ora","Disposizioni"]
            };
            foreach(var language in DevDeck.Windows.Core.Localization.Languages) {
                Text.Use(language);
                using var menu=new Forms.ContextMenuStrip();
                build.Invoke(controller,[menu]);
                var top=menu.Items.OfType<Forms.ToolStripMenuItem>().ToArray();
                // This is the first production assertion. The old menu has no open-pulls
                // action at all; a settings/card/dashboard lookalike cannot satisfy it.
                var pulls=top.Where(item=>item.Tag as string=="tray.openPulls").ToArray();
                Require(pulls.Length==1,"Main tray is missing its own open-pull-requests browser action (tray.openPulls).");
                var refresh=top.Where(item=>item.Tag as string=="tray.refresh").ToArray();
                var arrangements=top.Where(item=>item.Tag as string=="tray.arrangements").ToArray();
                Require(refresh.Length==1 && arrangements.Length==1,
                    "Main tray is missing global refresh or arrangements, or duplicates a deck command.");
                Require(new[] { pulls[0].Text,refresh[0].Text,arrangements[0].Text }.SequenceEqual(labels[language]),
                    "Main tray command labels differ from the original Mac menu: "+language);
                Require(!controller.LocalPollEnabled && controller.AllLocalViews.Length==0 && controller.AllRemoteViews.Length==0
                    && File.ReadAllBytes(store.Path).SequenceEqual(persisted)
                    && JsonSerializer.Serialize(controller.Settings,WorkerProtocol.Json)==original,
                    "Building the synthetic tray starts a widget/poller or changes saved settings.");
                checks.Add(new { name=language+".tray.deckCommandPresence", actualBuildMenu=true,
                    topLevelStableTags=true, originalThreeLocalizedLabels=true, noDuplicateCommands=true,
                    noActionClicks=true, noVisibleTrayBrowserWorkerOrCredential=true, settingsUnchanged=true });
            }
            return Task.CompletedTask;
        } finally {
            controller.CloseViews();
            foreach(var file in new[] { path,path+".bak" }) if(File.Exists(file)) File.Delete(file);
            Text.Use(previousLanguage);
        }
    }

    private static void Require(bool condition,string message) { if(!condition) throw new IOException(message); }
}
