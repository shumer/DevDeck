using System;
using System.Linq;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

/// Synthetic rendering only; no checkout or terminal operation is admitted.
internal static class WorkInFlightSamples
{
    internal static WorkInFlightCard Card(DeckController controller,string variant="mixed",bool collapsed=false)
    {
        var card=new WorkInFlightCard(controller,new(true,48,80,collapsed),live:false);
        card.ApplySnapshot(Snapshot(variant));
        if (variant=="expanded") card.SetExpanded(true);
        return card;
    }
    internal static WorkInFlightSnapshot Snapshot(string variant="mixed")
    {
        const double time=1790928000;
        CheckoutEntry[] entries=variant=="empty" ? [] : Enumerable.Range(0,variant=="expanded" ? 13 : 4).Select(index=>Entry(index,time)).ToArray();
        if (variant=="unicode") entries=[entries[0] with {
            Reference=entries[0].Reference with { Title="長い見出し · Очень длинный проект · "+new string('Ж',80) },
            Result=entries[0].Result with { State=entries[0].State! with { Branch="feature/長い名前/очень-длинная-ветка/"+new string('界',70) } }
        }];
        if (variant is "partial" or "failed") entries=entries.Select((entry,index)=>variant=="failed" || index==1
            ? entry with { Result=entry.Result with { State=null,Failure=new("status","statusFailed") } } : entry).ToArray();
        return new(entries,entries.Length,time,Checking:variant=="checking",Stale:variant=="stale");
    }
    private static CheckoutEntry Entry(int index,double time)
    {
        var titles=new[] { "NasdaqIR", "Il Tempo", "Governance", "DrupalContrib12" };
        var reference=new CheckoutReference("owned-render-"+index,index%2==0 ? "Ubuntu-24.04" : "Debian","/owned/render/checkout-"+index,
            index<titles.Length ? titles[index] : "Project "+(index+1));
        var dirty=index+1; var ahead=index%2==0 ? index+1 : 0;
        CheckoutSummaryFact[] facts=ahead>0 ? [new("changed",dirty),new("unpushed",ahead)] : [new("changed",dirty)];
        var state=new CheckoutState(index%2==0 ? "develop" : "fix/ILT-210-header-trailing-slash",dirty,ahead,0,true,ahead,
            ahead>0 ? time-3600 : null,true,ahead>0,facts);
        return new(reference,new(CheckoutCatalog.CardID,"owned-render-pass",reference.ProjectID,reference.Path,time,state,null,[]));
    }
}
