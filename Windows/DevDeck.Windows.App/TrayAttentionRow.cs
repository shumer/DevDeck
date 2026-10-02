using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Linq;
using DevDeck.Windows.Core;
using Forms = System.Windows.Forms;

namespace DevDeck.Windows.App;

/// A normal keyboard-operable menu item with a visible second line and an age badge.
internal sealed class TrayAttentionRow : Forms.ToolStripMenuItem
{
    private readonly string primaryTitle;
    private readonly string fullTitle;
    private readonly string fullSubtitle;
    private readonly string? primaryAge;
    private readonly AttentionItem? item;
    private readonly string? alternateTitle;
    private int nativeCaptionWidth;
    private int nativeCaptionDpi;
    private string title;
    private readonly string mark;
    private readonly Bitmap? brand;
    internal string Subtitle { get; }
    private AttentionChoice currentChoice = new("none", false);
    private AttentionChoice? activationChoice;
    internal string? Age => currentChoice.IsAlternate ? null : primaryAge;
    internal AttentionChoice CurrentChoice => activationChoice ?? currentChoice;
    internal void CaptureActivation() { if(!IsDisposed && currentChoice.Enabled)activationChoice=currentChoice; }

    internal TrayAttentionRow(AttentionItem item, DateTimeOffset now)
        : this(item.Title, item.Subtitle, item.Mark, AttentionDigest.Age(item.Since, now, global::DevDeck.Windows.App.Text.Resources))
    {
        this.item = item;
        var alternate = AttentionChoices.Alternate(item);
        alternateTitle = alternate.Kind switch {
            "read" => global::DevDeck.Windows.App.Text.L("menu.markRead", item.Title),
            "dismiss" => global::DevDeck.Windows.App.Text.L("menu.dismiss", item.Title),
            _ => null
        };
        Tag = item;
        SetAlternate(false);
    }

    internal TrayAttentionRow(string title, string subtitle) : this(title, subtitle, "calm", null) { Enabled = false; }

    private TrayAttentionRow(string title, string subtitle, string mark, string? age)
    {
        fullTitle = title;
        fullSubtitle = subtitle;
        this.title = primaryTitle = TrayIcon.Limit(title, 86);
        this.mark = mark;
        Subtitle = AttentionDigest.TrimSubtitle(subtitle);
        primaryAge = age;
        Text = this.title.Replace("&", "&&", StringComparison.Ordinal);
        ToolTipText = subtitle;
        AccessibleName = string.Join(", ", new[] { title, Subtitle, age }.Where(value => !string.IsNullOrEmpty(value)));
        AccessibleDescription = subtitle;
        AutoToolTip = false;
        if (mark is "github" or "gitlab" or "arc" or "ddev" or "docker") brand = BrandBitmap(mark);
    }

    internal void SetAlternate(bool held)
    {
        if (IsDisposed || item is null) return;
        currentChoice = AttentionChoices.Select(item, held);
        var caption = currentChoice.IsAlternate ? alternateTitle! : fullTitle;
        title = currentChoice.IsAlternate ? TrayIcon.Limit(caption, 86) : primaryTitle;
        Enabled = currentChoice.Enabled;
        AccessibleName = string.Join(", ", new[] { caption, Subtitle, Age }.Where(value => !string.IsNullOrEmpty(value)));
        AccessibleDescription = fullSubtitle + (alternateTitle is null ? "" : Environment.NewLine + "Alt: " + alternateTitle);
        ToolTipText = fullSubtitle + (alternateTitle is null ? "" : Environment.NewLine + "Alt: " + alternateTitle);
        // One bounded Text update: publishing the unconstrained caption first would
        // let native layout expand Width before the caption is measured against it.
        if (nativeCaptionWidth > 0) ConstrainNativeTitle((int)Math.Round(nativeCaptionWidth * (Owner?.DeviceDpi ?? 96) / (double)nativeCaptionDpi));
        else if (!AutoSize && Width > 0) ConstrainNativeTitle(Width);
        else Text = title.Replace("&", "&&", StringComparison.Ordinal);
        Invalidate();
    }

    private int Scale(int value) => (int)Math.Round(value * (Owner?.DeviceDpi ?? 96) / 96d);
    private int LineHeight => Font.Height + Scale(2);
    public override Size GetPreferredSize(Size constrainingSize)
    {
        // Reserve the larger presentation before the menu opens. Modifier transitions
        // keep one native row and its selection, mark, subtitle and client geometry.
        var primaryWidth = Measure(primaryTitle) + (primaryAge is null ? 0 : Measure(primaryAge));
        var alternateWidth = alternateTitle is null ? 0 : Measure(TrayIcon.Limit(alternateTitle, 86));
        var width = Math.Max(Math.Max(primaryWidth, alternateWidth), Measure(Subtitle)) + Scale(62);
        return new(Math.Clamp(width, Scale(330), Scale(520)), Math.Max(Scale(48), 2 * LineHeight + Scale(12)));
    }

    internal static void SizeMenu(Forms.ToolStrip menu)
    {
        // WinForms measures menu-item columns from Text alone. Our subtitle and age are
        // painted separately, so their preferred width must also constrain the dropdown.
        _ = menu.Handle;
        foreach (var item in menu.Items.OfType<Forms.ToolStripDropDownItem>().Where(item => item.HasDropDownItems)) {
            if (item.DropDownItems.OfType<TrayAttentionRow>().Any()) SizeMenu(item.DropDown);
        }
        var rows = menu.Items.OfType<TrayAttentionRow>().ToArray();
        menu.AutoSize = true;
        menu.MinimumSize = Size.Empty;
        if (rows.Length == 0) return;
        var ordinary = menu.Items.OfType<Forms.ToolStripMenuItem>().Where(item => item is not TrayAttentionRow).ToArray();
        // Re-measure ordinary rows too when content, font or DPI changes. Their native
        // preferred heights and shortcut/arrow columns remain part of menu measurement.
        foreach (var item in ordinary) item.AutoSize = true;
        var width = rows.Max(row => row.GetPreferredSize(Size.Empty).Width) + menu.Padding.Horizontal;
        menu.MinimumSize = new(width, 0);
        foreach (var row in rows) {
            row.nativeCaptionWidth = width;
            row.nativeCaptionDpi = menu.DeviceDpi;
            row.AutoSize = false;
            row.Size = new(width, row.GetPreferredSize(Size.Empty).Height);
            row.ConstrainNativeTitle(width);
        }
        // Native dropdown columns include their own padding, arrow and border metrics.
        // Measure both presentations while hidden, then reserve their actual maximum.
        // A subsequent caption change must not derive a new budget from expanded bounds.
        var original = rows.Select(row => row.CurrentChoice.IsAlternate).ToArray();
        var measured = new Size(width, 0);
        try {
            foreach (var alternate in new[] { false, true }) {
                foreach (var row in rows) row.SetAlternate(alternate);
                menu.PerformLayout();
                var preferred = menu.GetPreferredSize(Size.Empty);
                measured = new(Math.Max(measured.Width, preferred.Width), Math.Max(measured.Height, preferred.Height));
            }
        } finally {
            for (var index = 0; index < rows.Length; index++) rows[index].SetAlternate(original[index]);
        }
        menu.MinimumSize = new(measured.Width, 0);
        menu.AutoSize = false;
        menu.Size = measured;
        menu.PerformLayout();
        // An autosized ordinary submenu owner follows the current shared text column,
        // even while the dropdown and attention rows retain their reserved maximum.
        // Its changing Bounds would re-anchor an already open child dropdown. Reserve
        // the same native content span for ordinary rows, retaining measured heights.
        var ordinaryHeights = ordinary.Select(item => item.Height).ToArray();
        var contentWidth = Math.Min(rows.Max(row => row.Width), menu.ClientRectangle.Width);
        menu.SuspendLayout();
        try {
            for (var index = 0; index < ordinary.Length; index++) {
                var item = ordinary[index];
                var itemWidth = Math.Max(1, Math.Min(contentWidth, menu.ClientRectangle.Right - item.Bounds.Left));
                item.AutoSize = false;
                item.Size = new(itemWidth, ordinaryHeights[index]);
            }
        } finally { menu.ResumeLayout(true); }
    }

    private void ConstrainNativeTitle(int width)
    {
        var available = Math.Max(Scale(24), width - Scale(62) - (Age is null ? 0 : Measure(Age)));
        var visible = title;
        if (Measure(visible) > available) {
            var elements = new StringInfo(title);
            var low = 0; var high = elements.LengthInTextElements;
            while (low < high) {
                var middle = (low + high + 1) / 2;
                if (Measure(elements.SubstringByTextElements(0, middle) + "…") <= available) low = middle;
                else high = middle - 1;
            }
            visible = elements.SubstringByTextElements(0, low) + "…";
        }
        // Native keyboard navigation keeps the same visible prefix; accessibility keeps the
        // full original title. Native column measurement now matches the painted title budget.
        Text = visible.Replace("&", "&&", StringComparison.Ordinal);
    }

    protected override void OnPaint(Forms.PaintEventArgs e)
    {
        var selected = Selected && Enabled;
        var ink = !Enabled ? SystemColors.GrayText : selected ? SystemColors.HighlightText : SystemColors.MenuText;
        using (var fill = new SolidBrush(selected ? SystemColors.Highlight : SystemColors.Menu)) e.Graphics.FillRectangle(fill, new Rectangle(Point.Empty, Size));
        var visibleWidth = Math.Min(Width, Owner is null ? Width : Owner.ClientRectangle.Right - Bounds.Left);
        var left = Scale(38); var right = visibleWidth - Scale(12); var top = (Height - 2 * LineHeight - Scale(2)) / 2;
        var ageWidth = Age is null ? 0 : Measure(Age) + Scale(8);
        const Forms.TextFormatFlags flags = Forms.TextFormatFlags.NoPrefix | Forms.TextFormatFlags.SingleLine | Forms.TextFormatFlags.EndEllipsis | Forms.TextFormatFlags.VerticalCenter;
        Forms.TextRenderer.DrawText(e.Graphics, title, Font, new Rectangle(left, top, Math.Max(0, right - left - ageWidth), LineHeight), ink, flags);
        if (Age is not null) Forms.TextRenderer.DrawText(e.Graphics, Age, Font, new Rectangle(right - ageWidth, top, ageWidth, LineHeight), ink, flags | Forms.TextFormatFlags.Right);
        using var small = new Font(Font.FontFamily, Math.Max(7, Font.SizeInPoints - 1), FontStyle.Regular);
        Forms.TextRenderer.DrawText(e.Graphics, Subtitle, small, new Rectangle(left, top + LineHeight + Scale(2), Math.Max(0, right - left), LineHeight),
            selected || Forms.SystemInformation.HighContrast ? ink : SystemColors.GrayText, flags);
        var box = new Rectangle(Scale(8), (Height - Scale(24)) / 2, Scale(24), Scale(24));
        if (brand is not null) e.Graphics.DrawImage(brand, box);
        else DrawSymbol(e.Graphics, box, ink);
    }

    private int Measure(string text) => Forms.TextRenderer.MeasureText(text, Font, Size.Empty, Forms.TextFormatFlags.NoPrefix | Forms.TextFormatFlags.SingleLine).Width;

    private void DrawSymbol(Graphics drawing, Rectangle box, Color ink)
    {
        var saved = drawing.Save();
        try {
            drawing.SmoothingMode = SmoothingMode.AntiAlias;
            drawing.TranslateTransform(box.X + box.Width / 6f, box.Y + box.Height / 6f);
            drawing.ScaleTransform(box.Width / 24f, box.Height / 24f);
            using var pen = new Pen(ink, 1.4f) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round };
            void Lines(params PointF[] points) => drawing.DrawLines(pen, points);
            if (mark == "token") {
                drawing.DrawEllipse(pen, 1, 4, 7, 7); Lines(new(8, 7.5f), new(15, 7.5f), new(15, 11)); Lines(new(12, 7.5f), new(12, 10));
            } else if (mark == "rateLimit") {
                Lines(new(3, 1), new(13, 1), new(13, 3), new(3, 13), new(3, 15), new(13, 15), new(13, 13), new(3, 3), new(3, 1));
            } else if (mark == "network") {
                drawing.DrawArc(pen, 0, 3, 16, 14, 220, 100); drawing.DrawArc(pen, 3, 6, 10, 10, 220, 100);
                drawing.DrawEllipse(pen, 7, 13, 2, 2); Lines(new(14, 8), new(14, 12)); drawing.DrawEllipse(pen, 13.6f, 14, .8f, .8f);
            } else if (mark is "update" or "unpushed") {
                drawing.DrawEllipse(pen, 1, 1, 14, 14);
                if (mark == "update") { Lines(new(8, 4), new(8, 12)); Lines(new(5, 9), new(8, 12), new(11, 9)); }
                else { Lines(new(8, 12), new(8, 4)); Lines(new(5, 7), new(8, 4), new(11, 7)); }
            } else if (mark == "calm") {
                drawing.DrawEllipse(pen, 1, 1, 14, 14); Lines(new(4, 8), new(7, 11), new(12, 5));
            } else {
                drawing.DrawEllipse(pen, 2, 1, 4, 4); drawing.DrawEllipse(pen, 2, 11, 4, 4); drawing.DrawEllipse(pen, 10, 1, 4, 4);
                Lines(new(4, 5), new(4, 11)); drawing.DrawBezier(pen, new PointF(4, 9), new PointF(9, 9), new PointF(12, 8), new PointF(12, 5));
            }
        } finally { drawing.Restore(saved); }
    }

    private static Bitmap BrandBitmap(string mark)
    {
        var element = (System.Windows.FrameworkElement)BrandMarks.Create(mark, 12, tile: true);
        element.Measure(new(24, 24)); element.Arrange(new(0, 0, 24, 24)); element.UpdateLayout();
        var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap(96, 96, 384, 384, System.Windows.Media.PixelFormats.Pbgra32);
        bitmap.Render(element);
        var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder(); encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream(); encoder.Save(stream); stream.Position = 0;
        using var decoded = new Bitmap(stream); return new Bitmap(decoded);
    }

    protected override void OnClick(EventArgs e)
    {
        // WinForms closes the dropdown before raising the item's Click event.
        // Its earlier ItemClicked event captures the permitted shown choice.
        if(IsDisposed || activationChoice is null && Owner?.Visible!=true)return;
        try { base.OnClick(e); }
        finally { activationChoice=null; }
    }

    protected override void Dispose(bool disposing) { if (disposing) {activationChoice=null;brand?.Dispose();} base.Dispose(disposing); }
}
