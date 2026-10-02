using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Owned synthetic token states. Rendering never reads a credential or launches a worker/browser.
internal static class AccountTokenSamples
{
    internal static Task<Window> WindowAsync(Application application,string variant)
    {
        if (variant=="enterprise") return Task.FromResult<Window>(new EnterpriseTokenAddressDialog("https://enterprise.example.test/Company/api/v3") {FontSize=18});
        if (variant is not ("github-present" or "gitlab-present" or "missing" or "new-github"))
            throw new ArgumentException("Unknown synthetic account-token variant.",nameof(variant));
        var provider=variant=="gitlab-present"?"gitlab":"github";
        var path=Path.Combine(Path.GetTempPath(),"devdeck-account-token-render-"+Guid.NewGuid().ToString("N")+".json");
        var store=new SettingsStore(path);
        var account=new RemoteAccountSettings("render.token","Northwind · "+(provider=="gitlab"?"GitLab":"GitHub"),provider,
            provider=="gitlab"?"https://gitlab.example.test/Company":"https://api.github.com",
            ["northwind"],["northwind/site"],Browser:"edge",BrowserProfile:"Profile 7");
        store.Save(new(1,[new("Owned Linux","/owned/token-render",Text.Language)],[],Accounts:[account],
            RemoteCards:RemoteCardCatalog.All.Select(item=>new RemoteCardSettings(item.Id,item.Kind,item.Kind,"Owned Linux",[],Enabled:false)).ToArray(),Language:Text.Language));
        var controller=new DeckController(application,store,live:false);
        var form=new AccountSettingsForm(controller,variant=="new-github"?null:account,live:false,changed:_=>{},newProvider:provider,
            discoverDistributions:_=>Task.FromResult(new[]{"Owned Linux"}),browserOpener:(_,_,_)=>{},
            browserPickerFactory:(id,profile)=>new(id,profile,[new("edge","Owned Edge","C:/owned/msedge.exe",true)],_=>[new("Profile 7","Customer work")]),
            tokenPresent:variant is "github-present" or "gitlab-present",storedCredentialReader:_=>throw new IOException("Synthetic render must not read credentials."),
            acquireStoredVerifier:(_,_)=>throw new IOException("Synthetic render must not acquire a worker."),enterpriseAddressPrompt:(_,_)=>Task.FromResult<string?>(null));
        if(variant=="new-github")form.TokenDraft="Owned synthetic replacement";
        var window=new Window {Title="DevDeck · "+Text.L("account.section.token"),Width=880,Height=720,
            FontSize=variant=="gitlab-present"?18:13,ShowInTaskbar=false,
            Content=new ScrollViewer {Content=form,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled}};
        SettingsStyles.AddTo(window.Resources);
        window.Closed+=(_,_)=>{form.Dispose();controller.CloseViews();foreach(var file in new[]{path,path+".bak"})if(File.Exists(file))File.Delete(file);};
        return Task.FromResult(window);
    }
}
