using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;

namespace IpBump;

/// <summary>Draws the tray icon: the app's orange tile with the last number of the current IP on it.</summary>
static class TrayBadge
{
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr handle);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    const int SM_CXSMICON = 49;

    public static readonly Color Orange = Color.FromArgb(232, 122, 80);   // normal
    public static readonly Color Grey = Color.FromArgb(128, 128, 128);    // no address
    public static readonly Color Red = Color.FromArgb(196, 43, 28);       // the last change failed

    /// <param name="text">Up to three characters: "189", "…", "–", "!".</param>
    public static Icon Draw(string text, Color tileColor)
    {
        // Drawn at the exact tray size for this screen's scaling, so the digits stay sharp
        int size = Math.Max(16, GetSystemMetrics(SM_CXSMICON));
        using var bmp = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;

            using var tile = Rounded(new RectangleF(0, 0, size, size), size * 0.2f);
            using var fill = new SolidBrush(tileColor);
            g.FillPath(fill, tile);

            float em = size * (text.Length >= 3 ? 0.56f : 0.74f);
            using var font = new Font("Segoe UI", em, FontStyle.Bold, GraphicsUnit.Pixel);
            using var center = new StringFormat(StringFormatFlags.NoWrap | StringFormatFlags.NoClip)
            {
                Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center,
            };
            // Wider than the tile so three digits are never squeezed or wrapped; nudged down because digits have no descenders
            g.DrawString(text, font, Brushes.White, new RectangleF(-size, size * 0.03f, size * 3, size), center);
        }

        IntPtr handle = bmp.GetHicon();
        using var borrowed = Icon.FromHandle(handle);
        var icon = (Icon)borrowed.Clone();   // the clone owns its own copy, so the temporary handle can go
        DestroyIcon(handle);
        return icon;
    }

    public static GraphicsPath Rounded(RectangleF box, float radius)
    {
        float d = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(box.Left, box.Top, d, d, 180, 90);
        path.AddArc(box.Right - d, box.Top, d, d, 270, 90);
        path.AddArc(box.Right - d, box.Bottom - d, d, d, 0, 90);
        path.AddArc(box.Left, box.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
