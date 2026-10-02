using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Interop;
using Forms = System.Windows.Forms;

namespace DevDeck.Windows.App;

/// Only the current owned menu chain observes keyboard messages, on its UI thread.
internal sealed class TrayAttentionModifiers : Forms.IMessageFilter
{
    private static readonly ConditionalWeakTable<Forms.ContextMenuStrip,TrayAttentionModifiers> hosts=new();
    private readonly Forms.ContextMenuStrip menu;
    private readonly Func<bool> initialHeld;
    private readonly List<Forms.ToolStrip> activationOwners = new();
    private bool active;
    private bool held;
    internal bool Active => active;
    internal bool Held => held;
    internal int ObservedKeyboardMessages { get; private set; }
    internal static TrayAttentionModifiers Attach(Forms.ContextMenuStrip menu, Func<bool>? initialHeld=null) =>
        hosts.GetValue(menu,key=>new(key,initialHeld));

    internal TrayAttentionModifiers(Forms.ContextMenuStrip menu,Func<bool>? initialHeld=null)
    {
        this.menu=menu;
        this.initialHeld=initialHeld??(()=> (Keyboard.IsKeyDown(Key.LeftAlt)||Keyboard.IsKeyDown(Key.RightAlt))
            && !Keyboard.IsKeyDown(Key.LeftCtrl) && !Keyboard.IsKeyDown(Key.RightCtrl));
        menu.Opened+=(_,_)=>Start();
        menu.Closed+=(_,_)=>Stop();
        menu.Disposed+=(_,_)=>Stop();
    }
    private IEnumerable<Forms.ToolStrip> Menus(Forms.ToolStrip current)
    {
        yield return current;
        foreach(var child in current.Items.OfType<Forms.ToolStripDropDownItem>().Where(child=>child.HasDropDownItems))
            foreach(var descendant in Menus(child.DropDown)) yield return descendant;
    }
    private void SetHeld(bool value)
    {
        held=value;
        var chain=Menus(menu).ToArray();
        var shown=chain.Where(owner=>owner.Visible).Select(owner=>(Owner:owner,owner.Location)).ToArray();
        foreach(var owner in chain)owner.SuspendLayout();
        try {
            foreach(var row in chain.SelectMany(owner=>owner.Items.OfType<TrayAttentionRow>())) row.SetAlternate(value);
        } finally {
            foreach(var owner in chain)if(!owner.IsDisposed)owner.ResumeLayout(true);
            // Native text-column layout can reanchor an already open child dropdown.
            // Keep the same shown chain in place after its current captions are laid out.
            foreach(var (owner,location) in shown)if(!owner.IsDisposed && owner.Visible)owner.Location=location;
        }
    }
    private void Start()
    {
        if(active)return;
        active=true;
        // Opening rebuilds the items, while the root menu and this host are retained.
        // Subscribe only to this opening's actual chain and release every owner on close.
        foreach(var owner in Menus(menu)) {
            owner.ItemClicked+=CaptureActivation;
            activationOwners.Add(owner);
        }
        SetHeld(initialHeld());
        ComponentDispatcher.ThreadFilterMessage+=FilterWpf;
        Forms.Application.AddMessageFilter(this);
    }
    private void CaptureActivation(object? sender,Forms.ToolStripItemClickedEventArgs eventArgs)
    {
        if(active && sender is Forms.ToolStrip {Visible:true} && eventArgs.ClickedItem is TrayAttentionRow row)
            row.CaptureActivation();
    }
    private void Stop()
    {
        if(!active)return;
        active=false;
        ComponentDispatcher.ThreadFilterMessage-=FilterWpf;
        Forms.Application.RemoveMessageFilter(this);
        foreach(var owner in activationOwners)owner.ItemClicked-=CaptureActivation;
        activationOwners.Clear();
        if(!menu.IsDisposed)SetHeld(false);
    }
    private bool Filter(nint hwnd,int message,nint key)
    {
        if(!active || !menu.Visible || !Menus(menu).Any(owner=>owner.Visible && owner.IsHandleCreated && owner.Handle==hwnd))return false;
        if(message is not (0x100 or 0x101 or 0x104 or 0x105))return false;
        if(key==(nint)0x12 || key==(nint)0xA4 || key==(nint)0xA5) {
            ObservedKeyboardMessages++;
            SetHeld((message is 0x100 or 0x104) && (Forms.Control.ModifierKeys & Forms.Keys.Control)==0);
            return true; // Keep WinForms' Alt menu dismissal from replacing the shown variant.
        }
        if(held && key==(nint)0x0D && message is 0x100 or 0x104) {
            var row=Menus(menu).Where(owner=>owner.Visible).Reverse().SelectMany(owner=>owner.Items.OfType<TrayAttentionRow>())
                .FirstOrDefault(row=>row.Selected);
            if(row is{Enabled:true}) {row.PerformClick();if(menu.Visible)menu.Close(Forms.ToolStripDropDownCloseReason.ItemClicked);}
            return true;
        }
        return false;
    }
    private void FilterWpf(ref MSG message,ref bool handled)
    {
        if(!handled && Filter(message.hwnd,message.message,message.wParam))handled=true;
    }
    public bool PreFilterMessage(ref Forms.Message message) => Filter(message.HWnd,message.Msg,message.WParam);
}
