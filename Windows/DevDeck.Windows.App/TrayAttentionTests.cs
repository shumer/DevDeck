using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using DevDeck.Windows.Core;
using Forms = System.Windows.Forms;

namespace DevDeck.Windows.App;

/// Native synthetic menus only. No worker, browser, credential or real attention action.
internal static class TrayAttentionTests
{
    internal static Task RunAsync(Application application, List<object> checks)
    {
        var path = Path.Combine(Path.GetTempPath(), "devdeck-tray-attention-" + Guid.NewGuid().ToString("N") + ".json");
        var store = new SettingsStore(path);
        store.Save(new DeckSettings(1,[],[],Notifications:false));
        var controller = new DeckController(application,store,live:false);
        var persisted = File.ReadAllBytes(path);
        try {
            Text.Use("en");
            var now = DateTimeOffset.UtcNow;
            var waiting = Enumerable.Range(0,5).Select(index => new AttentionItem("waiting-" + index,"waiting-" + index,"waiting","github",
                "Waiting example " + index,"Example work account · example/shop",now.AddDays(-5 + index).ToUnixTimeSeconds(),
                new("open",Url:"https://example.test/review/" + index,AccountID:"sample"),Enabled:true,Dismissible:false)).ToArray();
            controller.ObserveAttention(new("synthetic:tray",waiting,[]));
            using var menu = Build(controller);
            var section = Section(menu);
            var direct = section.OfType<Forms.ToolStripMenuItem>().Where(row => waiting.Any(item => row.Text == item.Title)).ToArray();
            var overflow = section.OfType<Forms.ToolStripMenuItem>().SingleOrDefault(row => row.DropDownItems.Count > 0);
            // Deliberately first: the old menu uses Take(5), with no direct overflow actions.
            Require(direct.Length == 3 && overflow?.DropDownItems.Count == 2,
                "Five waiting signals must expose three named rows and retain two direct actions in the tier overflow menu.");
            checks.Add(new { name="tray.attention.overflow", visiblePerTier=3, waitingCount=5, overflowCount=2, noRealActions=true });
            foreach(var language in DevDeck.Windows.Core.Localization.Languages){
                Text.Use(language);
                CheckSections(controller,language,checks);
                CheckRows(controller,language,checks);
                CheckAgeAndSubtitle(language,checks);
                CheckCalm(controller,language,checks);
                CheckGeometry(language,checks);
                CheckNativeMenuGeometry(controller,language,checks);
                CheckRebuild(controller,language,checks);
            }
            Require(!controller.LocalPollEnabled && WorkerCount(controller)==0,"Synthetic tray inspection started a worker or local poll.");
            Require(File.ReadAllBytes(path).SequenceEqual(persisted),"Synthetic tray inspection changed its persisted settings.");
            checks.Add(new { name="tray.attention.isolation", allSixLanguages=true, noWorkerStarted=true, noRealActionExecuted=true, noCredentialAccess=true });
            return Task.CompletedTask;
        } finally {
            controller.CloseViews();
            foreach(var file in new[]{path,path+".bak"})if(File.Exists(file))File.Delete(file);
            Text.Use("en");
        }
    }

    private static void CheckSections(DeckController controller,string language,List<object> checks)
    {
        foreach(var tier in new[]{"waiting","needsFixing","stuck","goodToKnow"}){
            var cap=tier=="goodToKnow"?2:3;
            foreach(var count in new[]{0,1,cap,cap+1,cap+2}){
                var items=Enumerable.Range(0,count).Select(index=>Item(tier+"-"+index,tier,index)).ToArray();
                controller.ObserveAttention(new("synthetic:tray",items,[]));
                using var menu=Build(controller);
                var section=Section(menu);
                var direct=section.OfType<TrayAttentionRow>().Where(row=>row.Tag is AttentionItem).ToArray();
                var more=section.OfType<Forms.ToolStripMenuItem>().Where(row=>row.DropDownItems.Count>0).ToArray();
                var ordered=tier=="waiting"?items:items.Reverse().ToArray();
                var visible=count>cap+1?cap:count;
                Require(direct.Select(row=>((AttentionItem)row.Tag!).Id).SequenceEqual(ordered.Take(visible).Select(item=>item.Id)),"Tray attention tier loses its original visible cap, single-leftover exception or reading order.");
                Require(more.Length==(count>cap+1?1:0),"Tray attention hides a single remaining row behind a submenu or omits overflow.");
                if(more.Length>0){
                    var rest=more[0].DropDownItems.OfType<TrayAttentionRow>().ToArray();
                    Require(rest.Select(row=>((AttentionItem)row.Tag!).Id).SequenceEqual(ordered.Skip(visible).Select(item=>item.Id)),"Tray attention overflow drops or reorders original actions.");
                    var key=tier switch{"waiting"=>"waiting","needsFixing"=>"toFix","stuck"=>"stuck",_=>"other"};
                    Require(more[0].Text==Text.LN("attention.more."+key,count-visible),"Tray attention overflow count lacks the original localized plural caption.");
                }
                if(count>0)Require(section.OfType<Forms.ToolStripMenuItem>().Any(row=>row.Text==Text.L("attention.tier."+tier)&&!row.Enabled&&row.Tag is null),"Tray attention tier has no quiet localized heading.");
            }
            checks.Add(new { name=language+".tray.attention.sections."+tier, originalVisibleCap=cap, capPlusOneStaysDirect=true, allOverflowActionsRetained=true, localizedPlural=true });
        }
    }

    private static void CheckRows(DeckController controller,string language,List<object> checks)
    {
        var items=new[]{"waiting","needsFixing","stuck","goodToKnow"}.SelectMany(tier=>Enumerable.Range(0,5).Select(index=>Item(tier+"-"+index,tier,index))).ToArray();
        items[3]=items[3] with{Action=new("none"),Enabled=true};
        items[6]=items[6] with{Enabled=false};
        controller.ObserveAttention(new("synthetic:tray",items,[]));
        using var menu=Build(controller);
        var rows=AllRows(menu).ToArray();
        Require(rows.Length==items.Length&&rows.Select(row=>((AttentionItem)row.Tag!).Id).Distinct(StringComparer.Ordinal).Count()==items.Length,"Tray visible/overflow rows lose or duplicate attention identities.");
        Require(Section(menu).OfType<TrayAttentionRow>().Where(row=>row.Tag is AttentionItem).Select(row=>((AttentionItem)row.Tag!).Tier)
            .SequenceEqual(new[]{"waiting","waiting","waiting","needsFixing","needsFixing","needsFixing","stuck","stuck","stuck","goodToKnow","goodToKnow"}),
            "Native tray sections no longer follow waiting, needs fixing, stuck and information priority.");
        foreach(var row in rows){
            var tagged=(AttentionItem)row.Tag!;
            var expected=items.Single(item=>item.Id==tagged.Id);
            Require(tagged==expected&&tagged.Action==expected.Action,"Tray row replaces a promised account/project/browser action.");
            Require(row.Enabled==(expected.Enabled&&expected.Action.Kind!="none"),"Tray row enables a status-only action or disables a permitted action.");
            Require(row.AccessibleName is{ } accessible&&accessible.Contains(expected.Title,StringComparison.Ordinal)&&accessible.Contains(row.Subtitle,StringComparison.Ordinal)
                &&(row.Age is null||accessible.Contains(row.Age,StringComparison.Ordinal)),"Accessible tray row loses its plain title, account/project subtitle or age.");
            Require(row.ToolTipText is{} tooltip&&tooltip.Contains(expected.Subtitle,StringComparison.Ordinal),"Tray tooltip loses the complete diagnostic subtitle.");
            if(row.Enabled)Require(HasClickHandler(row),"An enabled visible/overflow attention row has no click handler.");
        }
        checks.Add(new { name=language+".tray.attention.rows", allFourTiers=true, originalTierPriority=true, visibleAndOverflowIdentities=true, promisedActionsAndEnabledState=true, statusOnlyDisabled=true, accessibleTitleSubtitleAge=true, clickHandlersPresent=true });
    }

    private static void CheckAgeAndSubtitle(string language,List<object> checks)
    {
        var now=new DateTimeOffset(2026,10,2,16,30,0,TimeSpan.Zero);
        foreach(var (since,key,amount) in new(double? Since,string? Key,int Amount)[]{
            (null,null,0),(now.AddHours(1).ToUnixTimeSeconds(),"now",0),(now.AddSeconds(-59).ToUnixTimeSeconds(),"now",0),
            (now.AddMinutes(-2).ToUnixTimeSeconds(),"minutes",2),(now.AddHours(-3).ToUnixTimeSeconds(),"hours",3),(now.AddDays(-4).ToUnixTimeSeconds(),"days",4)}){
            using var row=new TrayAttentionRow(Item("age","waiting",0) with{Since=since},now);
            var expected=key is null?null:Text.L("attention.age."+key,amount);
            Require(row.Age==expected,"Native tray age differs from the original localized now/minute/hour/day policy.");
        }
        using var longRow=new TrayAttentionRow(Item("subtitle","waiting",0) with{Title="Review & deployment",Subtitle=new string('Ж',80)},now);
        var accessible=longRow.AccessibleName??"";
        Require(longRow.Subtitle==new string('Ж',71)+"…"&&accessible.Contains("Review & deployment",StringComparison.Ordinal)
            &&!accessible.Contains("Review && deployment",StringComparison.Ordinal),"Tray subtitle is not bounded to 72 characters or accessible text shows menu escapes.");
        using var unicode=new TrayAttentionRow(Item("unicode","waiting",0) with{Subtitle=string.Concat(Enumerable.Repeat("e\u0301😀",50))},now);
        Require(StringInfo.ParseCombiningCharacters(unicode.Subtitle).Length<=72&&!HasBrokenSurrogate(unicode.Subtitle),"Bounded tray subtitle splits a grapheme or surrogate pair.");
        checks.Add(new { name=language+".tray.attention.ageSubtitle", nowMinutesHoursDays=true, missingAgeOmitted=true, futureClampedToNow=true, subtitleMaximumCharacters=72, unicodeBoundariesPreserved=true, accessibleAmpersandUnescaped=true });
    }

    private static void CheckCalm(DeckController controller,string language,List<object> checks)
    {
        controller.ObserveAttention(new("synthetic:tray",[],[]));
        var recorded=controller.LastCheckedAt;
        Require(recorded is not null,"Observed empty attention snapshot has no last-check time.");
        var fixedTime=new DateTimeOffset(2026,10,2,13,47,0,DateTimeOffset.Now.Offset);
        var field=typeof(DeckController).GetField("lastCheckedAt",BindingFlags.Instance|BindingFlags.NonPublic)!;
        field.SetValue(controller,fixedTime);
        using(var menu=Build(controller)){
            var calm=Section(menu).OfType<TrayAttentionRow>().Single();
            var expected=Text.L("menu.checkedAt",fixedTime.ToLocalTime().ToString("HH:mm",CultureInfo.InvariantCulture));
            Require(calm.Text==Text.L("menu.calm")&&!calm.Enabled&&calm.Tag is null&&calm.Age is null&&calm.Subtitle==expected
                &&calm.AccessibleName!.Contains(expected,StringComparison.Ordinal),"Calm tray confirmation loses its localized last-check subtitle or becomes actionable.");
            Require(controller.LastCheckedAt==fixedTime,"Opening the tray rewrites the observed last-check time.");
        }
        field.SetValue(controller,null);
        using(var menu=Build(controller)){
            var calm=Section(menu).OfType<TrayAttentionRow>().Single();
            Require(calm.Subtitle.StartsWith(Text.L("menu.checkedAt",""),StringComparison.Ordinal)&&controller.LastCheckedAt is null,"Initial calm confirmation fails to show the current-clock fallback or marks a menu opening as a completed check.");
        }
        var before=DateTimeOffset.UtcNow;
        controller.ObserveAttention(new("synthetic:tray",[Item("observed","waiting",0) with{Since=1}],[]));
        Require(controller.LastCheckedAt>=before&&controller.LastCheckedAt<=DateTimeOffset.UtcNow,"Last check is taken from a signal age rather than the latest observed response.");
        checks.Add(new { name=language+".tray.attention.calm", quietLocalizedConfirmation=true, actualObservedLastCheck=true, currentClockFallbackBeforeFirstCheck=true, menuOpeningDoesNotChangeTime=true, signalAgeIndependent=true });
    }

    private static void CheckGeometry(string language,List<object> checks)
    {
        var now=DateTimeOffset.UtcNow;
        foreach(var scale in new[]{1f,1.5f,2f}){
            using var menu=new Forms.ContextMenuStrip();
            var menuFont=Forms.SystemInformation.MenuFont??System.Drawing.SystemFonts.DefaultFont;
            using var font=new Font(menuFont.FontFamily,menuFont.Size*scale,System.Drawing.FontStyle.Regular);
            menu.Font=font;
            var item=Item("geometry","waiting",0) with{Title=string.Concat(Enumerable.Repeat("Long review Ж😀 & ",24)),Subtitle=string.Concat(Enumerable.Repeat("Synthetic account · example/repository · ",10))};
            var row=new TrayAttentionRow(item,now);menu.Items.Add(row);menu.PerformLayout();
            var preferred=row.GetPreferredSize(System.Drawing.Size.Empty);
            Require(preferred.Width>=200&&preferred.Width<=Math.Max(320,Forms.SystemInformation.WorkingArea.Width-32)&&preferred.Height>row.Font.Height
                &&preferred.Height<row.Font.Height*5+40,"Long native tray rows have unbounded width or lack room for the subtitle at larger menu fonts.");
            Require(row.Subtitle.Length>0&&row.Age is not null&&row.AccessibleName!.Contains(item.Title,StringComparison.Ordinal),"Bounded row geometry loses the original accessible action title or secondary information.");
        }
        checks.Add(new { name=language+".tray.attention.geometry", longTitlesAndSubtitles=true, boundedWidth=true, twoLineSpace=true, fontScales=new[]{1,1.5,2}, noActualDesktopCapture=true });
    }

    private static void CheckNativeMenuGeometry(DeckController controller,string language,List<object> checks)
    {
        foreach(var scale in new[]{1f,1.5f,2f}){
            var items=Enumerable.Range(0,5).Select(index=>Item("native-geometry-"+index,"waiting",index) with{
                Title=index==0?"Review & short":string.Concat(Enumerable.Repeat("Long review Ж😀 & ",8)),
                Subtitle=string.Concat(Enumerable.Repeat("Synthetic account · example/repository · ",4))
            }).ToArray();
            controller.ObserveAttention(new("synthetic:tray",items,[]));
            var menuFont=Forms.SystemInformation.MenuFont??System.Drawing.SystemFonts.DefaultFont;
            using var font=new Font(menuFont.FontFamily,menuFont.Size*scale,System.Drawing.FontStyle.Regular);
            using var menu=new Forms.ContextMenuStrip { Font=font };
            // Exercise the production consumer; do not call the sizing helper directly.
            Rebuild(controller,menu);
            var overflow=Section(menu).OfType<Forms.ToolStripMenuItem>().Single(row=>row.DropDownItems.Count>0).DropDown;
            foreach(var surface in new Forms.ToolStrip[]{menu,overflow}){
                _=surface.Handle; surface.PerformLayout(); surface.Size=surface.GetPreferredSize(System.Drawing.Size.Empty); surface.PerformLayout();
                var rows=surface.Items.OfType<TrayAttentionRow>().ToArray();
                Require(rows.Length==(ReferenceEquals(surface,menu)?3:2),"Native attention geometry fixture lost its direct or overflow rows.");
                void CheckBounds(){
                    foreach(var row in rows){
                        Require(row.Bounds.Left>=surface.ClientRectangle.Left&&row.Bounds.Right<=surface.ClientRectangle.Right,
                            "Native attention row extends beyond its menu client: "+language+" / "+scale+" / "+row.Bounds.Right+" > "+surface.ClientRectangle.Right);
                        Require(row.Bounds.Top>=surface.ClientRectangle.Top&&row.Bounds.Bottom<=surface.ClientRectangle.Bottom
                            &&row.Bounds.Height>=row.Font.Height*2,"Native attention menu clips a row or lacks its actual two-line height.");
                        var nativeTitle=(row.Text??"").Replace("&&","&",StringComparison.Ordinal);
                        var nativeWidth=Forms.TextRenderer.MeasureText(nativeTitle,row.Font,System.Drawing.Size.Empty,Forms.TextFormatFlags.NoPrefix|Forms.TextFormatFlags.SingleLine).Width;
                        Require(nativeTitle.Length>0&&nativeWidth<=row.Bounds.Width&& !HasBrokenSurrogate(nativeTitle),
                            "Native title-only column grows beyond the bounded visible row or loses a usable Unicode keyboard prefix.");
                    }
                }
                CheckBounds();
                var before=rows.Select(row=>row.Bounds).ToArray(); var dpi=surface.DeviceDpi;
                using var bitmap=new Bitmap(surface.Width,surface.Height);
                surface.DrawToBitmap(bitmap,new System.Drawing.Rectangle(0,0,bitmap.Width,bitmap.Height));
                CheckBounds();
                Require(surface.DeviceDpi==dpi&&rows.Select(row=>row.Bounds).SequenceEqual(before),"Drawing a hidden native attention menu changes its DPI/row geometry after measuring.");
            }
        }
        checks.Add(new { name=language+".tray.attention.nativeGeometry", actualProductionMenu=true, mainAndOverflow=true, rowsWithinNativeClient=true,
            fontScales=new[]{1,1.5,2}, twoLineHeight=true, drawDoesNotChangeMeasuredGeometry=true, noActualDesktopCapture=true });
    }

    private static void CheckRebuild(DeckController controller,string language,List<object> checks)
    {
        var before=Enumerable.Range(0,5).Select(index=>Item("before-"+index,"waiting",index)).ToArray();
        controller.ObserveAttention(new("synthetic:tray",before,[]));
        using var menu=Build(controller);
        var old=AllRows(menu).ToArray();
        var after=new[]{Item("after","waiting",0) with{Title="Updated & current",Subtitle="New account · new/repository"}};
        controller.ObserveAttention(new("synthetic:tray",after,[]));
        Rebuild(controller,menu);
        var fresh=AllRows(menu).ToArray();
        Require(old.All(row=>row.IsDisposed),"Reopened tray retains undisposed prior rows: "+old.Count(row=>!row.IsDisposed));
        Require(fresh.Length==1,"Reopened tray retains an incorrect signal count: "+fresh.Length);
        Require(fresh[0].Tag is AttentionItem tagged&&tagged==after[0],"Reopened tray replaces the current signal identity or action.");
        Require(fresh[0].Subtitle==after[0].Subtitle,"Reopened tray keeps a stale account subtitle.");
        Require(!Section(menu).OfType<Forms.ToolStripMenuItem>().Any(row=>row.DropDownItems.Count>0),"Reopened tray retains an obsolete overflow menu.");
        checks.Add(new { name=language+".tray.attention.rebuild", sameNativeMenuRepopulated=true, oldRowsDisposed=true, currentSubtitleActionAndIdentity=true, staleOverflowRemoved=true });
    }

    private static AttentionItem Item(string id,string tier,int index)=>new(id,id,tier,"github","Example & review "+id,"Synthetic work account · example/shop",
        DateTimeOffset.UtcNow.AddDays(-10+index).ToUnixTimeSeconds(),(index%5) switch{
            0=>new("open",Url:"https://example.test/review/"+id,Service:"github",AccountID:"synthetic-work"),
            1=>new("accountSettings",Service:"gitlab",AccountID:"synthetic-lab"),2=>new("showCard",CardID:"synthetic-project"),
            3=>new("startDocker"),_=>new("openTerminal",Path:"/tmp/synthetic-checkout")},Enabled:true,Dismissible:false);
    private static IEnumerable<TrayAttentionRow> AllRows(Forms.ContextMenuStrip menu)=>Section(menu).OfType<TrayAttentionRow>().Where(row=>row.Tag is AttentionItem)
        .Concat(Section(menu).OfType<Forms.ToolStripMenuItem>().SelectMany(row=>row.DropDownItems.OfType<TrayAttentionRow>()).Where(row=>row.Tag is AttentionItem));
    private static bool HasClickHandler(Forms.ToolStripItem row)
    {
        var events=(EventHandlerList)typeof(Component).GetProperty("Events",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(row)!;
        return typeof(Forms.ToolStripItem).GetFields(BindingFlags.Static|BindingFlags.NonPublic).Where(field=>field.FieldType==typeof(object)
            &&field.Name.Contains("click",StringComparison.OrdinalIgnoreCase)&&!field.Name.Contains("double",StringComparison.OrdinalIgnoreCase))
            .Any(field=>events[field.GetValue(null)!] is Delegate);
    }
    private static bool HasBrokenSurrogate(string value){for(var index=0;index<value.Length;index++){if(char.IsHighSurrogate(value[index])){if(index+1==value.Length||!char.IsLowSurrogate(value[++index]))return true;}else if(char.IsLowSurrogate(value[index]))return true;}return false;}
    private static int WorkerCount(DeckController controller)=>typeof(DeckController).GetFields(BindingFlags.Instance|BindingFlags.NonPublic)
        .Where(field=>field.FieldType==typeof(WorkerManager)).Select(field=>(WorkerManager)field.GetValue(controller)!)
        .Sum(manager=>((System.Collections.IDictionary)typeof(WorkerManager).GetField("workers",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(manager)!).Count);

    private static Forms.ContextMenuStrip Build(DeckController controller)
    {
        var menu = new Forms.ContextMenuStrip();
        try {
            Rebuild(controller,menu);
            return menu;
        } catch { menu.Dispose();throw; }
    }
    private static void Rebuild(DeckController controller,Forms.ContextMenuStrip menu)=>typeof(DeckController).GetMethod("BuildMenu",BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(controller,[menu]);
    private static Forms.ToolStripItem[] Section(Forms.ContextMenuStrip menu) => menu.Items.Cast<Forms.ToolStripItem>()
        .TakeWhile(item => item is not Forms.ToolStripSeparator).ToArray();
    private static void Require(bool condition,string message){if(!condition)throw new IOException(message);}
}
