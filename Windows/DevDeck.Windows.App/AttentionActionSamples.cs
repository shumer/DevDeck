using System;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Owned synthetic rendering; all dispatch is a fake without credentials or providers.
internal static class AttentionActionSamples
{
    internal static AttentionItem[] Items()
    {
        var now=DateTimeOffset.UtcNow;
        var personal=Enumerable.Range(1,5).Select(index=>new AttentionItem("sample.inbox."+index,"sample.inbox."+index,
            "waiting","github",Text.L("attention.inbox.review.prefix")+": Example_shop & review "+index,
            "example/shop · Example work account",now.AddHours(-index*13).ToUnixTimeSeconds(),
            index==1?new("none"):new("open","https://example.invalid/owned/review/"+index,"github","sample.account"),true,false,
            new("sample.inbox","sample.account",index.ToString(),"https://api.example.invalid")));
        return new[] {
            new AttentionItem("sample.project","sample.project","needsFixing","project","Example shop",
                Text.L("card.state.stopped"),now.AddDays(-2).ToUnixTimeSeconds(),new("showCard",CardID:"sample.project"),true,true),
            new AttentionItem("sample.status","sample.status","needsFixing","token",Text.L("attention.account.rejected.title","GitHub","Example account"),
                Text.L("attention.account.rejected.subtitle","HTTP 401"),null,new("none"),false,false)
        }.Concat(personal).ToArray();
    }

    internal static AttentionWindow Window(DeckController controller,string variant)
    {
        var pending=new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var window=new AttentionWindow(controller,Items(),(_,_)=>variant switch {
            "pending"=>pending.Task,
            "failed"=>Task.FromException<bool>(new WorkerException("disconnected","Owned synthetic read failure")),
            _=>Task.FromResult(false)
        });
        window.Height=820;
        window.Closed+=(_,_)=>pending.TrySetResult(false);
        if(variant is "pending" or "failed") {
            var panel=(Panel)((ScrollViewer)window.Content).Content;
            var button=panel.Children.OfType<Button>().First(item=>item.Tag is AttentionChoice {Kind:"read"});
            button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        }
        return window;
    }
}
