using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;

namespace DevDeck.Windows.App;

internal enum DeckTrayState { Calm, Stuck, NeedsFixing, Waiting }

/// The original Mac DeckIcon geometry, in a square notification-area slot with transparent DD lettering.
internal static class DeckTrayArtwork
{
    internal static readonly int[] Sizes = [16, 20, 24, 32, 48];

    internal static DeckTrayState FromTiers(IEnumerable<string> tiers)
    {
        var present = tiers.ToHashSet(StringComparer.Ordinal);
        return present.Contains("waiting") ? DeckTrayState.Waiting : present.Contains("needsFixing") ? DeckTrayState.NeedsFixing
            : present.Contains("stuck") ? DeckTrayState.Stuck : DeckTrayState.Calm;
    }

    internal static Color Ink(bool light) => light ? Color.FromArgb(32, 32, 32) : Color.FromArgb(242, 242, 242);

    internal static Bitmap Render(int edge, DeckTrayState state, Color ink)
    {
        if (edge is < 16 or > 256) throw new ArgumentOutOfRangeException(nameof(edge));
        const int sampling = 4;
        using var large = new Bitmap(edge * sampling, edge * sampling, PixelFormat.Format32bppArgb);
        using (var drawing = Graphics.FromImage(large)) {
            drawing.SmoothingMode = SmoothingMode.AntiAlias;
            drawing.TranslateTransform(0, edge * sampling / 12f);
            drawing.ScaleTransform(edge * sampling / 18f, edge * sampling / 18f);
            using var paint = new SolidBrush(ink);
            using var back = Rounded(4, .2f, 10, 2.8f, 1.4f);
            drawing.FillPath(paint, back);
            using var front = Rounded(.5f, 4.9f, 17, 10.1f, 2.5f);
            using var letters = new GraphicsPath();
            using var font = new FontFamily("Segoe UI");
            letters.AddString("DD", font, (int)FontStyle.Bold, 7.2f, PointF.Empty, StringFormat.GenericTypographic);
            var bounds = letters.GetBounds();
            using var positioning = new Matrix();
            positioning.Translate(9 - bounds.Left - bounds.Width / 2, 9.95f - bounds.Top - bounds.Height / 2);
            letters.Transform(positioning);
            front.FillMode = FillMode.Alternate;
            front.AddPath(letters, false);
            drawing.FillPath(paint, front);
            if (state != DeckTrayState.Calm) {
                // A transparent clearance separates the badge from the stack, including on a tinted taskbar.
                drawing.CompositingMode = CompositingMode.SourceCopy;
                using var clear = new SolidBrush(Color.Transparent);
                drawing.FillEllipse(clear, 11.75f, .15f, 6.3f, 6.3f);
                drawing.CompositingMode = CompositingMode.SourceOver;
                if (state == DeckTrayState.Stuck) {
                    using var ring = new Pen(ink, 1.1f);
                    drawing.DrawEllipse(ring, 13.2f, 1.6f, 3.4f, 3.4f);
                } else {
                    using var badge = new SolidBrush(state == DeckTrayState.Waiting ? Color.FromArgb(255, 69, 58) : ink);
                    drawing.FillEllipse(badge, 12.65f, 1.05f, 4.5f, 4.5f);
                }
            }
        }
        var bitmap = new Bitmap(edge, edge, PixelFormat.Format32bppArgb);
        using (var drawing = Graphics.FromImage(bitmap)) {
            drawing.CompositingMode = CompositingMode.SourceCopy;
            drawing.InterpolationMode = InterpolationMode.HighQualityBicubic;
            drawing.PixelOffsetMode = PixelOffsetMode.HighQuality;
            drawing.DrawImage(large, new Rectangle(0, 0, edge, edge));
        }
        return bitmap;
    }

    internal static Icon Create(DeckTrayState state, Color ink, int selectedSize)
    {
        var frames = Sizes.Append(selectedSize).Distinct().Order().Select(edge => {
            using var bitmap = Render(edge, state, ink);
            using var bytes = new MemoryStream(); bitmap.Save(bytes, ImageFormat.Png);
            return (edge, bytes: bytes.ToArray());
        }).ToArray();
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream, System.Text.Encoding.UTF8, leaveOpen: true);
        writer.Write((ushort)0); writer.Write((ushort)1); writer.Write((ushort)frames.Length);
        var offset = 6 + frames.Length * 16;
        foreach (var frame in frames) {
            writer.Write((byte)frame.edge); writer.Write((byte)frame.edge); writer.Write((byte)0); writer.Write((byte)0);
            writer.Write((ushort)1); writer.Write((ushort)32); writer.Write(frame.bytes.Length); writer.Write(offset); offset += frame.bytes.Length;
        }
        foreach (var frame in frames) writer.Write(frame.bytes);
        writer.Flush(); stream.Position = 0;
        // Clone while the stream is open: the tray owns its HICON independently of temporary rendering buffers.
        using var decoded = new Icon(stream, selectedSize, selectedSize);
        return (Icon)decoded.Clone();
    }

    internal static void WritePreview(string path)
    {
        using var sheet = new Bitmap(620, 250);
        using var drawing = Graphics.FromImage(sheet);
        using var caption = new Font("Segoe UI",10);
        for (var theme = 0; theme < 2; theme++) {
            var light = theme == 0;
            using var background = new SolidBrush(light ? Color.FromArgb(245,245,245) : Color.FromArgb(30,30,30));
            using var label = new SolidBrush(Ink(light)); drawing.FillRectangle(background,0,theme * 125,620,125);
            drawing.DrawString(light ? "Light taskbar" : "Dark taskbar",caption,label,12,theme * 125 + 8);
            var column = 0;
            foreach (var state in Enum.GetValues<DeckTrayState>()) {
                drawing.DrawString(state.ToString(),caption,label,12 + column * 150,theme * 125 + 33);
                var x = 12 + column * 150;
                foreach (var edge in new[] { 16,24,48 }) {
                    using var bitmap = Render(edge,state,Ink(light)); drawing.DrawImageUnscaled(bitmap,x,theme * 125 + 62); x += edge + 12;
                }
                column++;
            }
        }
        sheet.Save(path,ImageFormat.Png);
    }

    private static GraphicsPath Rounded(float x, float y, float width, float height, float radius)
    {
        var path = new GraphicsPath(); var diameter = radius * 2;
        path.AddArc(x, y, diameter, diameter, 180, 90); path.AddArc(x + width - diameter, y, diameter, diameter, 270, 90);
        path.AddArc(x + width - diameter, y + height - diameter, diameter, diameter, 0, 90);
        path.AddArc(x, y + height - diameter, diameter, diameter, 90, 90); path.CloseFigure(); return path;
    }
}
