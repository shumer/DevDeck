using System.Text.Json;
using DevDeck.Windows.Core;

// Pure saved-deck behavior: permanent identities, immutable snapshots and compatible names.
internal static class ArrangementChecks
{
    internal static async Task RunAsync(Func<string,Func<Task>,Task> check)
    {
        await check("arrangement overwrite retains saved spelling and its original menu index",()=>{
            var original=Fixture().SaveArrangement("Morning").SaveArrangement("Work").SaveArrangement("Evening");
            var before=Json(original);
            var changed=original with { Cards=original.Cards.Select(card=>card.Project.Id=="a"?card with { X=789.125,Enabled=false,Collapsed=false }:card).ToArray() };
            var replaced=changed.SaveArrangement("  WORK  ");
            Require(replaced.ArrangementList.Select(item=>item.Name).SequenceEqual(new[]{"Morning","Work","Evening"}),
                "Overwrite moved the saved name or changed its established spelling.");
            var placed=replaced.ArrangementList[1].Cards.Single(card=>card.Id=="a");
            Require(placed.X==789.125 && !placed.Enabled && !placed.Collapsed,"Overwrite did not capture the current preferred state.");
            Require(ReferenceEquals(replaced.ArrangementList[0],original.ArrangementList[0])
                && ReferenceEquals(replaced.ArrangementList[2],original.ArrangementList[2]) && Json(original)==before,
                "Overwrite modified another saved snapshot or mutated the original settings.");
            return Task.CompletedTask;
        });
        await check("arrangement ninth new save evicts the oldest and keeps the remaining order",()=>{
            var settings=Fixture();
            for(var index=1;index<=DeckSettings.ArrangementLimit+3;index++)settings=settings.SaveArrangement("Day "+index);
            Require(DeckSettings.ArrangementLimit==8 && settings.ArrangementList.Length==8
                && settings.ArrangementList.Select(item=>item.Name).SequenceEqual(Enumerable.Range(4,8).Select(index=>"Day "+index)),
                "Explicit new saves did not keep the latest eight in creation order.");
            var order=settings.ArrangementList.Select(item=>item.Name).ToArray();
            Require(settings.SaveArrangement("DAY 7").ArrangementList.Select(item=>item.Name).SequenceEqual(order),
                "Replacing an existing name evicted another arrangement.");
            return Task.CompletedTask;
        });
        await check("arrangement legacy lists load unchanged and truncate only on an explicit new name",()=>{
            var fixture=Fixture();var placements=fixture.SaveArrangement("Template").ArrangementList[0].Cards;
            var original=fixture with { Arrangements=Enumerable.Range(1,12).Select(index=>new Arrangement("Legacy "+index,placements.ToArray())).ToArray() };
            original.Validate();var json=Json(original);
            var loaded=JsonSerializer.Deserialize<DeckSettings>(json,WorkerProtocol.Json)!;loaded.Validate();
            Require(Json(loaded)==json && loaded.ArrangementList.Length==12,"Loading/validation rewrote the legacy schema or dropped names beyond eight.");
            Require(ReferenceEquals(loaded.ForgetArrangement("missing"),loaded) && Json(loaded)==json,"A missing-name operation rewrote a legacy list.");
            var replaced=loaded.SaveArrangement("LEGACY 3");
            Require(replaced.ArrangementList.Length==12 && replaced.ArrangementList[2].Name=="Legacy 3" && Json(loaded)==json,
                "Replacing a legacy name trimmed or mutated its original list.");
            Require(loaded.SaveArrangement("New day").ArrangementList.Select(item=>item.Name)
                .SequenceEqual(Enumerable.Range(6,7).Select(index=>"Legacy "+index).Append("New day")),
                "An explicit new legacy save did not apply the bounded suffix policy.");
            return Task.CompletedTask;
        });
        await check("arrangement captures every configured local and remote chosen state",()=>{
            var original=Fixture();var before=Json(original);var saved=original.SaveArrangement("Snapshot");
            var cards=saved.ArrangementList.Single().Cards;
            Require(cards.Select(card=>card.Id).ToHashSet(StringComparer.Ordinal).SetEquals(new[]{"a","b","legacy.pr","legacy.actions"}),"Snapshot omitted a configured hidden or remote identity.");
            var a=cards.Single(card=>card.Id=="a");var b=cards.Single(card=>card.Id=="b");
            var pull=cards.Single(card=>card.Id=="legacy.pr");var runs=cards.Single(card=>card.Id=="legacy.actions");
            Require(a.X==123.25 && a.Y==456.5 && a.Enabled && a.Collapsed && b.X==222 && b.Y==333 && !b.Enabled && !b.Collapsed,
                "Local placement/visibility/chosen compact flags were not captured.");
            Require(pull.X==777.5 && pull.Y==111.25 && pull.Enabled && !pull.Collapsed && runs.X==888 && runs.Y==222 && !runs.Enabled && runs.Collapsed,
                "Remote placement/visibility/chosen compact flags were not captured.");
            Require(Json(original)==before && Json(saved with { Arrangements=original.Arrangements })==before,"Saving a snapshot changed another configuration field.");
            return Task.CompletedTask;
        });
        await check("arrangement match ignores catalog order and current metadata but keeps permanent IDs",()=>{
            var saved=Fixture().SaveArrangement("Work");
            var reordered=saved with { Cards=saved.Cards.Reverse().Select(card=>card with { Title="Renamed "+card.Project.Id,
                Project=card.Project with { Path="/tmp/renamed-"+card.Project.Id,StartCommand="printf updated" },Browser="edge",BrowserProfile="Profile 2" }).ToArray(),
                RemoteCards=saved.RemoteCardList.Reverse().Select(card=>card with { Title="Renamed remote "+card.Id }).ToArray(),
                Arrangements=[saved.ArrangementList[0] with { Cards=saved.ArrangementList[0].Cards.Reverse().ToArray() }] };
            var before=Json(reordered);
            Require(reordered.ArrangementMatches("WORK"),"Matching used array order/title/folder/browser instead of the full permanent-ID placement state.");
            Require(!reordered.ArrangementMatches("missing") && Json(reordered)==before,"Matching an unknown name changed settings.");
            return Task.CompletedTask;
        });
        await check("arrangement matching changes for each saved coordinate visibility and chosen compact field",()=>{
            var saved=Fixture().SaveArrangement("Work");Require(saved.ArrangementMatches("work"),"Fresh saved arrangement did not match.");
            foreach(var card in saved.Cards){
                foreach(var changed in new[]{card with { X=card.X+0.125 },card with { Y=card.Y+0.125 },card with { Enabled=!card.Enabled },card with { Collapsed=!card.Collapsed }})
                    Require(!(saved with { Cards=saved.Cards.Select(item=>item.Project.Id==card.Project.Id?changed:item).ToArray() }).ArrangementMatches("Work"),
                        "Local drag/visibility/compact change retained the live match tick: "+card.Project.Id);
            }
            foreach(var card in saved.RemoteCardList){
                foreach(var changed in new[]{card with { X=card.X+0.125 },card with { Y=card.Y+0.125 },card with { Enabled=!card.Enabled },card with { Collapsed=!card.Collapsed }})
                    Require(!(saved with { RemoteCards=saved.RemoteCardList.Select(item=>item.Id==card.Id?changed:item).ToArray() }).ArrangementMatches("Work"),
                        "Remote drag/visibility/compact change retained the live match tick: "+card.Id);
            }
            Require(saved.ArrangementMatches("Work"),"Field probes mutated the original arrangement.");
            return Task.CompletedTask;
        });
        await check("arrangement matching requires the whole current identity set including new deleted and replaced IDs",()=>{
            var saved=Fixture().SaveArrangement("Work");var extra=NewLocal("added");
            Require(!(saved with { Cards=saved.Cards.Append(extra).ToArray() }).ArrangementMatches("Work"),"An extra configured identity still matched an older deck.");
            Require(!(saved with { Cards=saved.Cards.Where(card=>card.Project.Id!="b").ToArray() }).ArrangementMatches("Work"),"A deleted local identity still matched.");
            Require(!(saved with { RemoteCards=saved.RemoteCardList.Where(card=>card.Id!="legacy.actions").ToArray() }).ArrangementMatches("Work"),"A deleted remote identity still matched.");
            var sameCount=saved with { Cards=saved.Cards.Select(card=>card.Project.Id=="a"?card with { Project=card.Project with { Id="A" } }:card).ToArray() };
            Require(!sameCount.ArrangementMatches("Work"),"Matching compared just count/geometry or treated distinct permanent IDs as case-insensitive names.");
            return Task.CompletedTask;
        });
        await check("arrangement forget removes only the selected case-insensitive name and is a no-op when missing",()=>{
            var original=Fixture().SaveArrangement("Morning").SaveArrangement("Work").SaveArrangement("Evening");var before=Json(original);
            var forgotten=original.ForgetArrangement("WORK");
            Require(forgotten.ArrangementList.Select(item=>item.Name).SequenceEqual(new[]{"Morning","Evening"})
                && ReferenceEquals(forgotten.ArrangementList[0],original.ArrangementList[0]) && ReferenceEquals(forgotten.ArrangementList[1],original.ArrangementList[2]),
                "Forget removed/reordered another arrangement.");
            Require(Json(forgotten with { Arrangements=original.Arrangements })==before && Json(original)==before,"Forget changed other saved configuration or its source object.");
            Require(ReferenceEquals(forgotten.ForgetArrangement("missing"),forgotten) && ReferenceEquals(forgotten.ForgetArrangement("Work"),forgotten),"Missing forget created a mutation instead of a true no-op.");
            return Task.CompletedTask;
        });
        await check("arrangement apply restores local and remote geometry without rolling back current metadata or recreating deleted cards",()=>{
            var saved=Fixture().SaveArrangement("Work");var oldA=saved.Cards.Single(card=>card.Project.Id=="a");var newCard=NewLocal("new-card");
            var currentA=oldA with { X=900,Y=901,Enabled=false,Collapsed=false,Title="Current name",Project=oldA.Project with {
                Path="/tmp/current-a",StartCommand="npm run current",HealthURL="http://localhost:4321/health" },
                Browser="edge",BrowserProfile="Profile current",Links=[new("TEST","https://example.test/current")],PhoneURL="http://192.0.2.1:4321",NotifiesWhenDown=false };
            var currentPull=saved.RemoteCardList[0] with { X=500,Y=501,Enabled=false,Collapsed=true,Title="Current PR",AccountIDs=["work","second"],UseAllAccounts=true };
            var newRemote=new RemoteCardSettings("remote.new","New remote","inbox","Test Linux",["work"],X:333,Y:444);
            var second=new RemoteAccountSettings("second","Second","github","https://api.github.com",[],[]);
            var current=saved with { Cards=[currentA,newCard],RemoteCards=[currentPull,saved.RemoteCardList[1],newRemote],Accounts=saved.AccountList.Append(second).ToArray(),
                Floating=true,Locked=true,SeenAlerts=["current-episode"],Language="ru",RefreshSeconds=120 };
            var before=Json(current);var restored=current.ApplyArrangement("WORK");var a=restored.Cards.Single(card=>card.Project.Id=="a");var pull=restored.RemoteCardList.Single(card=>card.Id=="legacy.pr");
            Require(a==(currentA with { X=oldA.X,Y=oldA.Y,Enabled=oldA.Enabled,Collapsed=oldA.Collapsed })
                && pull==(currentPull with { X=saved.RemoteCardList[0].X,Y=saved.RemoteCardList[0].Y,Enabled=true,Collapsed=false }),
                "Apply did not restore both layout kinds or rolled back current metadata/account scope.");
            Require(!restored.Cards.Any(card=>card.Project.Id=="b") && ReferenceEquals(restored.Cards.Single(card=>card.Project.Id=="new-card"),newCard)
                && ReferenceEquals(restored.RemoteCardList.Single(card=>card.Id=="remote.new"),newRemote),"Apply recreated a deleted identity or changed an added card.");
            Require(ReferenceEquals(restored.Accounts,current.Accounts) && ReferenceEquals(restored.Workers,current.Workers) && restored.Floating && restored.Locked
                && restored.Language=="ru" && restored.RefreshSeconds==120 && restored.AnnouncedAlerts.SequenceEqual(new[]{"current-episode"}) && Json(current)==before,
                "Apply rolled back runtime/preferences/history/account metadata or mutated current settings.");
            return Task.CompletedTask;
        });
        await check("arrangement empty decks and legacy validation keep the existing schema rules",()=>{
            var empty=DeckSettings.Empty.SaveArrangement("Empty");Require(empty.ArrangementMatches("EMPTY") && empty.ArrangementList[0].Cards.Length==0,"An empty saved deck did not match.");
            Require(empty.ForgetArrangement("empty").ArrangementList.Length==0 && !empty.ArrangementMatches("missing"),"Empty/missing name behavior changed.");
            foreach(var name in new[]{"  ",new string('x',129),"bad\nname"})Invalid(()=>Fixture().SaveArrangement(name));
            var first=Fixture().SaveArrangement("Work");
            Invalid(()=>(first with { Arrangements=[first.ArrangementList[0],first.ArrangementList[0] with { Name="WORK" }] }).Validate());
            var legacy=first with { Arrangements=Enumerable.Range(0,12).Select(index=>first.ArrangementList[0] with { Name="Legacy "+index }).ToArray() };
            legacy.Validate();Require(legacy.ArrangementList.Length==12,"Validate acquired a destructive legacy length limit.");
            return Task.CompletedTask;
        });
    }

    private static DeckSettings Fixture()=>new(1,[new("Test Linux","/tmp/synthetic-arrangements-runtime")],
        [new(new("a","Test Linux","local","/tmp/a",StartCommand:"npm run dev"),"A",X:123.25,Y:456.5,Collapsed:true),
         new(new("b","Test Linux","ddev","/tmp/b"),"B",Enabled:false,X:222,Y:333)],
        Accounts:[new("work","Work","github","https://api.github.com",[],[])],
        RemoteCards:[new("legacy.pr","PR","pullRequests","Test Linux",["work"],X:777.5,Y:111.25),
                     new("legacy.actions","Actions","actions","Test Linux",["work"],Enabled:false,X:888,Y:222,Collapsed:true)],
        SeenAlerts:["original-episode"],Notifications:true,Language:"en");
    private static CardSettings NewLocal(string id)=>new(new(id,"Test Linux","local","/tmp/"+id,StartCommand:"npm run added"),"Added "+id,X:700,Y:800);
    private static string Json(DeckSettings settings)=>JsonSerializer.Serialize(settings,WorkerProtocol.Json);
    private static void Invalid(Action action)
    {
        try { action(); }catch(InvalidDataException){return;}
        throw new IOException("Expected unchanged arrangement validation to reject this input.");
    }
    private static void Require(bool condition,string message){if(!condition)throw new IOException(message);}
}
