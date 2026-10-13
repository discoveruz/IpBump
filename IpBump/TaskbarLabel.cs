using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Automation;
using System.Windows.Threading;
using Microsoft.Win32;

namespace IpBump;

/// <summary>
/// The current IP address written on the taskbar, beside the notification area (Windows 11 only).
/// It is a small see-through window placed inside the taskbar, so it slides, hides and scales with it.
/// Double-click and right-click work as they do on the tray icon.
/// <para>
/// The window has a thread to itself. Windows makes a thread whose window sits inside another program's window
/// share that program's keyboard focus and mouse capture. On the app's own thread that let the taskbar close
/// IpBump's menu the moment it opened, and let an open menu swallow clicks meant for the taskbar.
/// </para>
/// </summary>
sealed class TaskbarLabel : IDisposable
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string className, string title);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string title);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern ushort RegisterClassEx(ref WNDCLASSEX windowClass);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateWindowEx(int exStyle, string className, string title, int style,
        int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr DefWindowProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr LoadCursor(IntPtr instance, IntPtr name);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool SetWindowText(IntPtr hwnd, string text);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr hwnd);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc each, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool TrackMouseEvent(ref TRACKMOUSEEVENT track);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
    [DllImport("user32.dll")] static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr screenDc, IntPtr position, ref SIZE size,
        IntPtr sourceDc, ref POINT source, int colorKey, ref BLENDFUNCTION blend, int flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetMessage(out MSG message, IntPtr hwnd, uint first, uint last);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool PeekMessage(out MSG message, IntPtr hwnd, uint first, uint last, uint remove);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr DispatchMessage(ref MSG message);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool PostThreadMessage(uint thread, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern UIntPtr SetTimer(IntPtr hwnd, UIntPtr id, uint milliseconds, IntPtr callback);
    [DllImport("user32.dll")] static extern bool KillTimer(IntPtr hwnd, UIntPtr id);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);

    delegate IntPtr WndProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    struct RECT
    {
        public int Left, Top, Right, Bottom;
        public readonly int Width => Right - Left;
        public readonly int Height => Bottom - Top;
    }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct SIZE { public int Width, Height; }
    [StructLayout(LayoutKind.Sequential)] struct BLENDFUNCTION { public byte Op, Flags, Alpha, Format; }
    [StructLayout(LayoutKind.Sequential)] struct TRACKMOUSEEVENT { public int Size, Flags; public IntPtr Window; public int HoverTime; }
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr Window; public uint Message; public IntPtr WParam, LParam; public uint Time; public POINT Point; public uint Private; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WNDCLASSEX
    {
        public int Size, Style;
        public IntPtr Proc;
        public int ClassExtra, WindowExtra;
        public IntPtr Instance, Icon, Cursor, Background;
        public string MenuName, ClassName;
        public IntPtr SmallIcon;
    }

    const int WS_POPUP = unchecked((int)0x80000000), WS_CHILD = 0x40000000, WS_CLIPSIBLINGS = 0x04000000;
    const int WS_EX_LAYERED = 0x80000, WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000;
    const int GWL_STYLE = -16, GWL_EXSTYLE = -20, CS_DBLCLKS = 8, SW_HIDE = 0, IDC_ARROW = 32512;
    const uint SWP_NOSIZE = 1, SWP_NOMOVE = 2, SWP_NOACTIVATE = 0x10, SWP_FRAMECHANGED = 0x20, SWP_SHOWWINDOW = 0x40;
    const uint WM_NCDESTROY = 0x82, WM_MOUSEACTIVATE = 0x21, WM_MOUSEMOVE = 0x200, WM_LBUTTONDBLCLK = 0x203,
               WM_RBUTTONUP = 0x205, WM_MOUSELEAVE = 0x2A3, WM_TIMER = 0x113, WM_QUIT = 0x12,
               WM_WAKE = 0x8000;       // WM_APP: there is something new to show
    const uint PM_NOREMOVE = 0;
    const int MA_NOACTIVATE = 3, TME_LEAVE = 2, ULW_ALPHA = 2, AC_SRC_ALPHA = 1;
    static readonly IntPtr HWND_TOP = IntPtr.Zero;

    const string WindowClass = "IpBumpTaskbarLabel";
    // The Windows 11 taskbar draws its buttons inside this child window; Windows 10 has none, and no spare room either
    const string ButtonHost = "Windows.UI.Composition.DesktopWindowContentBridge";
    const string WidestAddress = "000.000.000.000";

    // One window class for the life of the process; its messages go to whichever label is alive
    static readonly WndProc s_proc = WindowProc;
    static ushort s_class;
    static TaskbarLabel s_live;
    static readonly string s_typeface = Typeface();

    readonly Dispatcher _ui = Dispatcher.CurrentDispatcher;   // the app's thread: clicks are reported there
    readonly Thread _thread;                                  // the label's own; everything below that touches the window runs on it
    readonly ManualResetEventSlim _started = new();
    uint _threadId;
    IntPtr _hwnd, _refusedBy;          // _refusedBy: the taskbar that would not take the label in
    int _refusals;
    long _askAgainAt;                  // on the Environment.TickCount64 clock
    volatile bool _closed;
    volatile Extent[] _buttons = [];   // where the taskbar's own buttons are, as last seen by the watcher thread
    volatile State _wanted = new("", false, false);   // what the app asked for last

    State _shown = new("", false, false);             // what the picture shows
    bool _hover, _light;
    bool _stale = true;                // the picture no longer matches what should be shown
    float _scale = 1;
    int _width, _height, _room;

    /// <summary>A stretch of the taskbar that something occupies, in screen pixels.</summary>
    internal readonly record struct Extent(int Left, int Right);

    /// <param name="Address">Empty when the adapter has no address.</param>
    record State(string Address, bool Busy, bool Problem);

    public event Action DoubleClicked;
    /// <summary>Carries the mouse position in the units WPF menus are placed with.</summary>
    public event Action<Point> RightClicked;

    public TaskbarLabel()
    {
        s_live = this;
        new Thread(WatchButtons) { IsBackground = true, Name = "IpBump taskbar buttons" }.Start();
        _thread = new Thread(Run) { IsBackground = true, Name = "IpBump taskbar label" };
        _thread.Start();
        _started.Wait();   // from here on Show and Dispose can reach it
    }

    /// <param name="address">Empty when the adapter has no address.</param>
    public void Show(string address, bool busy, bool problem)
    {
        var state = new State(address, busy, problem);
        if (state == _wanted) return;
        _wanted = state;
        PostThreadMessage(_threadId, WM_WAKE, 0, 0);
    }

    void Run()
    {
        _threadId = GetCurrentThreadId();
        PeekMessage(out _, 0, 0, 0, PM_NOREMOVE);   // a thread gets its message queue the first time it asks for a message
        _started.Set();
        // The taskbar rearranges itself without telling anyone (a new tray icon, another widget moving,
        // Explorer restarting), so the label simply checks its place once a second
        UIntPtr timer = SetTimer(0, 0, 1000, 0);
        TryPlace();
        while (GetMessage(out MSG message, 0, 0, 0) > 0)
        {
            if (message.Window == 0 && message.Message is WM_TIMER or WM_WAKE) TryPlace();
            else DispatchMessage(ref message);
        }
        KillTimer(0, timer);
        if (_hwnd != 0) DestroyWindow(_hwnd);
    }

    void TryPlace()
    {
        try
        {
            Place();
        }
        catch (Exception)
        {
            // Nothing here is worth taking the tray app down for; the next second gets another try
        }
    }

    /// <summary>Puts the label where it belongs, or hides it when there is no good place for it.</summary>
    void Place()
    {
        if (_closed) return;
        var wanted = _wanted;
        if (wanted != _shown) (_shown, _stale) = (wanted, true);
        IntPtr taskbar = FindWindow("Shell_TrayWnd", null);
        if (taskbar == 0 || FindWindowEx(taskbar, 0, ButtonHost, null) == 0
            || !GetWindowRect(taskbar, out RECT bar) || bar.Width < bar.Height * 4)   // not while it stands upright either
        {
            Hide();
            return;
        }

        if (taskbar == _refusedBy && _refusals >= 3 && Environment.TickCount64 < _askAgainAt) return;
        if (_hwnd == 0 && !Create()) return;
        if (GetParent(_hwnd) != taskbar && !MoveInto(taskbar)) return;

        float scale = GetDpiForWindow(taskbar) / 96f;
        bool light = TaskbarIsLight();
        if (_stale || scale != _scale || light != _light || bar.Height != _height)
        {
            (_scale, _light, _height, _stale) = (scale, light, bar.Height, false);
            Paint();
        }

        IntPtr tray = FindWindowEx(taskbar, 0, "TrayNotifyWnd", null);
        int trayLeft = tray != 0 && GetWindowRect(tray, out RECT area) ? area.Left : bar.Right;
        int? right = Dock(bar.Left, bar.Width, trayLeft, _room, OtherWidgets(taskbar, bar).Concat(_buttons));
        if (right == null)
        {
            Hide();
            return;
        }

        int left = right.Value - _width;
        if (!IsWindowVisible(_hwnd) || !GetWindowRect(_hwnd, out RECT now) || now.Left != left || now.Top != bar.Top)
            SetWindowPos(_hwnd, HWND_TOP, left - bar.Left, 0, _width, _height, SWP_NOACTIVATE | SWP_SHOWWINDOW);   // relative to the taskbar's corner
    }

    /// <summary>
    /// Where the label's right edge goes: against the notification area, or to the left of whatever is in the way there.
    /// Null when that would take it further than half a taskbar away, which is what a taskbar crowded with apps does.
    /// </summary>
    /// <param name="room">The width to keep free. Wider than a short address, so the label doesn't change sides as the address changes.</param>
    internal static int? Dock(int barLeft, int barWidth, int trayLeft, int room, IEnumerable<Extent> taken)
    {
        var all = taken.ToList();
        int right = trayLeft, limit = Math.Max(barLeft, trayLeft - barWidth / 2);
        while (true)
        {
            int left = right - room;
            if (left < limit) return null;
            var inTheWay = all.Where(t => t.Left < right && t.Right > left).ToList();
            if (inTheWay.Count == 0) return right;
            right = inTheWay.Min(t => t.Left);
        }
    }

    /// <summary>Other programs' widgets inside the taskbar: a usage meter, a network speed display and the like.</summary>
    List<Extent> OtherWidgets(IntPtr taskbar, RECT bar)
    {
        var found = new List<Extent>();
        GetWindowThreadProcessId(taskbar, out uint shell);
        EnumChildWindows(taskbar, (child, _) =>
        {
            GetWindowThreadProcessId(child, out uint owner);
            if (child != _hwnd && owner != shell && GetParent(child) == taskbar && IsWindowVisible(child)
                && GetWindowRect(child, out RECT r) && r.Width > 0 && r.Width < bar.Width / 2)
                found.Add(new Extent(r.Left, r.Right));
            return true;
        }, 0);
        return found;
    }

    // Runs on its own thread: the question goes to Explorer and takes a few milliseconds to answer
    void WatchButtons()
    {
        while (!_closed)
        {
            try
            {
                IntPtr taskbar = FindWindow("Shell_TrayWnd", null);
                IntPtr host = taskbar == 0 ? 0 : FindWindowEx(taskbar, 0, ButtonHost, null);
                if (host != 0) _buttons = ReadButtons(taskbar, host);
            }
            catch (Exception)
            {
                // Explorer is restarting or busy: the last answer stands
            }
            Thread.Sleep(5000);
        }
    }

    /// <summary>The Start button, search box, app buttons and so on: everything the label must not cover.</summary>
    static Extent[] ReadButtons(IntPtr taskbar, IntPtr host)
    {
        if (!GetWindowRect(taskbar, out RECT bar)) return [];
        var root = AutomationElement.FromHandle(host);
        // Fetch the rectangles together with the search: one round trip to Explorer instead of one per button
        var request = new CacheRequest { AutomationElementMode = AutomationElementMode.None, TreeScope = TreeScope.Element };
        request.Add(AutomationElement.BoundingRectangleProperty);
        AutomationElementCollection buttons;
        using (request.Activate())
            buttons = root.FindAll(TreeScope.Descendants,
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button));

        var found = new List<Extent>();
        foreach (AutomationElement button in buttons)
        {
            var r = button.Cached.BoundingRectangle;
            if (!r.IsEmpty && r.Width > 0 && r.Width < bar.Width / 2)
                found.Add(new Extent((int)r.Left, (int)Math.Ceiling(r.Right)));
        }
        return [.. found];
    }

    bool Create()
    {
        IntPtr instance = GetModuleHandle(null);
        if (s_class == 0)
        {
            var windowClass = new WNDCLASSEX
            {
                Size = Marshal.SizeOf<WNDCLASSEX>(),
                Style = CS_DBLCLKS,
                Proc = Marshal.GetFunctionPointerForDelegate(s_proc),
                Instance = instance,
                Cursor = LoadCursor(0, IDC_ARROW),
                ClassName = WindowClass,
            };
            s_class = RegisterClassEx(ref windowClass);
            if (s_class == 0) return false;
        }
        _hover = false;   // a new window has not met the mouse yet
        _hwnd = CreateWindowEx(WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, WindowClass, "IpBump", WS_POPUP,
            0, 0, 1, 1, 0, 0, instance, 0);
        return _hwnd != 0;
    }

    bool MoveInto(IntPtr taskbar)
    {
        SetWindowLongPtr(_hwnd, GWL_STYLE, WS_CHILD | WS_CLIPSIBLINGS);
        SetParent(_hwnd, taskbar);
        if (GetParent(_hwnd) != taskbar)
        {
            // Refused. While the Start menu is open the taskbar takes no new windows; if Explorer runs with
            // other rights it never does. So try a few more times, then ask only every ten seconds.
            DestroyWindow(_hwnd);
            _refusals = taskbar == _refusedBy ? _refusals + 1 : 1;
            _refusedBy = taskbar;
            _askAgainAt = Environment.TickCount64 + 10_000;
            return false;
        }
        _refusedBy = 0;
        // Windows 11 can leave a window that was moved into the taskbar underneath the taskbar's own picture.
        // Taking the "layered" style off and on again brings it to the front; the picture must be sent again afterwards.
        long style = GetWindowLongPtr(_hwnd, GWL_EXSTYLE).ToInt64();
        SetWindowLongPtr(_hwnd, GWL_EXSTYLE, (IntPtr)(style & ~WS_EX_LAYERED));
        SetWindowLongPtr(_hwnd, GWL_EXSTYLE, (IntPtr)style);
        SetWindowPos(_hwnd, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
        _stale = true;
        return true;
    }

    void Hide()
    {
        if (_hwnd != 0 && IsWindowVisible(_hwnd)) ShowWindow(_hwnd, SW_HIDE);
    }

    void Paint()
    {
        using var picture = Draw(_shown.Address, _shown.Busy, _shown.Problem, _hover, _light, _scale, _height);
        _width = picture.Width;
        _room = Math.Max(_width, Measure(WidestAddress, false, _scale));

        IntPtr screen = GetDC(0), memory = CreateCompatibleDC(screen);
        IntPtr bitmap = picture.GetHbitmap(Color.FromArgb(0)), before = SelectObject(memory, bitmap);
        var size = new SIZE { Width = picture.Width, Height = picture.Height };
        var origin = new POINT();
        var blend = new BLENDFUNCTION { Alpha = 255, Format = AC_SRC_ALPHA };
        UpdateLayeredWindow(_hwnd, screen, 0, ref size, memory, ref origin, 0, ref blend, ULW_ALPHA);
        SelectObject(memory, before);
        DeleteObject(bitmap);
        DeleteDC(memory);
        ReleaseDC(0, screen);

        // For screen readers, which see this window as part of the taskbar
        SetWindowText(_hwnd, "IP address " + (_shown.Address == "" ? "none" : _shown.Address)
            + (_shown.Busy ? ", changing" : "") + (_shown.Problem ? ", the last change failed" : ""));
    }

    /// <summary>The label's picture: a dim "IP", then the address. See-through apart from the text.</summary>
    internal static Bitmap Draw(string address, bool busy, bool problem, bool hover, bool light, float scale, int height)
    {
        string tag = problem ? "!" : "IP", value = address == "" ? "no address" : address;
        Color ink = light ? Color.Black : Color.White;
        Color strong = Color.FromArgb(light ? 228 : 255, ink), dim = Color.FromArgb(light ? 150 : 160, ink);
        Color alarm = light ? TrayBadge.Red : Color.FromArgb(255, 153, 164);   // the same red, lightened for a dark taskbar

        var picture = new Bitmap(Measure(address, problem, scale), height, PixelFormat.Format32bppPArgb);
        using var g = Graphics.FromImage(picture);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        // Almost, not fully, transparent: Windows lets clicks fall through fully transparent pixels
        g.Clear(Color.FromArgb(1, 0, 0, 0));

        if (hover)
        {
            // The same faint plate the tray icons get under the mouse
            using var plate = new SolidBrush(Color.FromArgb(light ? 12 : 20, ink));
            using var shape = TrayBadge.Rounded(new RectangleF(2 * scale, 4 * scale, picture.Width - 4 * scale, height - 8 * scale), 4 * scale);
            g.FillPath(plate, shape);
        }

        using var tagFont = TextFont(scale, bold: problem);
        using var valueFont = TextFont(scale, bold: false);
        using var format = TextFormat();
        using var tagInk = new SolidBrush(problem ? alarm : dim);
        using var valueInk = new SolidBrush(busy || address == "" ? dim : strong);
        float tagWidth = g.MeasureString(tag, tagFont, PointF.Empty, format).Width;
        float top = -scale;   // digits and capitals have nothing below the line, so centred text looks low without this
        g.DrawString(tag, tagFont, tagInk, new RectangleF(Padding * scale, top, picture.Width, height), format);
        g.DrawString(value, valueFont, valueInk, new RectangleF((Padding + Gap) * scale + tagWidth, top, picture.Width, height), format);
        return picture;
    }

    const float Padding = 10, Gap = 6, TextSize = 12;   // at 100% scaling, like the taskbar clock

    /// <summary>How wide the label is for this address, in pixels.</summary>
    internal static int Measure(string address, bool problem, float scale)
    {
        using var ruler = new Bitmap(1, 1);
        using var g = Graphics.FromImage(ruler);
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        using var tagFont = TextFont(scale, bold: problem);
        using var valueFont = TextFont(scale, bold: false);
        using var format = TextFormat();
        float text = g.MeasureString(problem ? "!" : "IP", tagFont, PointF.Empty, format).Width
                   + g.MeasureString(address == "" ? "no address" : address, valueFont, PointF.Empty, format).Width;
        return (int)Math.Ceiling(text + (Padding * 2 + Gap) * scale);
    }

    static Font TextFont(float scale, bool bold) =>
        new(s_typeface, TextSize * scale, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Pixel);

    // Exact widths with no extra margin, one line, centred on the taskbar's height
    static StringFormat TextFormat()
    {
        using var exact = StringFormat.GenericTypographic;
        return new StringFormat(exact)
        {
            LineAlignment = StringAlignment.Center,
            FormatFlags = exact.FormatFlags | StringFormatFlags.NoWrap | StringFormatFlags.NoClip,
        };
    }

    // The taskbar's own font; Windows 10 and Windows Server don't have it
    static string Typeface()
    {
        const string wanted = "Segoe UI Variable Text";
        using var probe = new Font(wanted, 12);
        return probe.Name == wanted ? wanted : "Segoe UI";
    }

    // The taskbar has its own dark/light switch, separate from the one apps follow.
    // High-contrast themes ignore that switch and give the taskbar the theme's background colour.
    static bool TaskbarIsLight() =>
        System.Windows.SystemParameters.HighContrast
            ? SystemColors.Window.GetBrightness() > 0.5f
            : Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", 0) is int on && on != 0;

    static IntPtr WindowProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam)
    {
        var label = s_live;
        if (label != null && hwnd == label._hwnd)
        {
            try
            {
                switch (message)
                {
                    case WM_LBUTTONDBLCLK:
                        label._ui.BeginInvoke(() => label.DoubleClicked?.Invoke());
                        return 0;
                    case WM_RBUTTONUP:
                        GetCursorPos(out POINT mouse);
                        var where = new Point((int)(mouse.X / label._scale), (int)(mouse.Y / label._scale));
                        label._ui.BeginInvoke(() => label.RightClicked?.Invoke(where));
                        return 0;
                    case WM_MOUSEMOVE:
                        label.Hover(true);
                        return 0;
                    case WM_MOUSELEAVE:
                        label.Hover(false);
                        return 0;
                    case WM_MOUSEACTIVATE:
                        return MA_NOACTIVATE;   // a click here must not take the keyboard away from the app in use
                    case WM_NCDESTROY:
                        label._hwnd = 0;        // Explorer restarted and took the taskbar, and this window, with it
                        break;
                }
            }
            catch (Exception)
            {
                // Nothing here is worth taking the tray app down for, and an exception must not travel back into Windows
            }
        }
        return DefWindowProc(hwnd, message, wParam, lParam);
    }

    void Hover(bool over)
    {
        if (over == _hover) return;
        _hover = over;
        if (over)
        {
            // Ask to be told when the mouse leaves again
            var track = new TRACKMOUSEEVENT { Size = Marshal.SizeOf<TRACKMOUSEEVENT>(), Flags = TME_LEAVE, Window = _hwnd };
            TrackMouseEvent(ref track);
        }
        Paint();
    }

    public void Dispose()
    {
        _closed = true;
        PostThreadMessage(_threadId, WM_QUIT, 0, 0);
        _thread.Join(2000);   // it takes its window with it; no longer than this if Explorer has it waiting
        if (s_live == this) s_live = null;
    }
}
