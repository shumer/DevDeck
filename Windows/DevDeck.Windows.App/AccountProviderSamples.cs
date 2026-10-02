using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Only owned synthetic form/page data. Does not discover WSL, profiles or credentials.
internal static class AccountProviderSamples
{
    internal static Task<Window> WindowAsync(Application application,string variant)
    {
        if(variant is not ("existing-github" or "existing-gitlab" or "new-github" or "new-gitlab" or "notifications"))
            throw new ArgumentException("Unknown synthetic account-provider variant.",nameof(variant));
        var path=Path.Combine(Path.GetTempPath(),"devdeck-account-provider-render-"+Guid.NewGuid().ToString("N")+".json");
        var store=new SettingsStore(path);
        var github=new RemoteAccountSettings("render.github","Northwind · GitHub","github","https://api.github.com",
            ["northwind","team-platform"],["northwind/site","team-platform/api"],Browser:"edge",BrowserProfile:"Profile 7",NotifiesFailedRuns:true);
        var gitlab=new RemoteAccountSettings("render.gitlab","Customer · GitLab","gitlab","https://gitlab.example.test/team",
            ["retained unsupported legacy scope"],["retained/legacy/repository"],Browser:"edge",BrowserProfile:"Profile 7",NotifiesBlocked:true,NotifiesFailedRuns:true);
        store.Save(new(1,[new("Owned Linux","/owned/account-render",Text.Language)],[],Accounts:[github,gitlab],
            RemoteCards:RemoteCardCatalog.All.Select(item=>new RemoteCardSettings(item.Id,item.Kind,item.Kind,"Owned Linux",
                [item.Provider=="gitlab"?gitlab.Id:github.Id],Enabled:false)).ToArray(),Language:Text.Language,Notifications:true));
        var controller=new DeckController(application,store,live:false);
        AccountSettingsForm? form=null;
        UIElement content;
        if(variant=="notifications")content=NotificationSettingsWindow.CreateContent(controller);
        else {
            var kind=variant.EndsWith("gitlab",StringComparison.Ordinal)?"gitlab":"github";
            var original=variant.StartsWith("existing",StringComparison.Ordinal)?(kind=="gitlab"?gitlab:github):null;
            form=new(controller,original,live:false,changed:_=>{},newProvider:kind,
                discoverDistributions:_=>Task.FromResult(new[]{"Owned Linux"}),browserOpener:(_,_,_)=>{},
                browserPickerFactory:(id,profile)=>new BrowserPicker(id,profile,[new("edge","Owned Edge","C:/owned/msedge.exe",true)],
                    _=>[new("Profile 7","Customer work")]));
            if(original is null) {
                Field<TextBox>(form,"label").Text=kind=="gitlab"?"New customer GitLab":"New GitHub account";
                if(kind=="github"){Field<TextBox>(form,"organizations").Text="northwind";Field<TextBox>(form,"repositories").Text="northwind/site";}
                form.TokenDraft="Owned synthetic draft";
            }
            foreach(var expander in ((Panel)form.Content).Children.OfType<Expander>())expander.IsExpanded=true;
            content=form;
        }
        var window=new Window {Title="DevDeck · "+Text.L("account.section.account"),Width=880,Height=720,
            FontSize=variant is "existing-gitlab" or "notifications"?18:13,ShowInTaskbar=false,
            Content=new ScrollViewer {Content=content,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled}};
        SettingsStyles.AddTo(window.Resources);
        window.Closed+=(_,_)=>{
            form?.Dispose();controller.CloseViews();
            foreach(var file in new[]{path,path+".bak"})if(File.Exists(file))File.Delete(file);
        };
        return Task.FromResult(window);
    }
    private static T Field<T>(object owner,string name)=>(T)owner.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(owner)!;
}
