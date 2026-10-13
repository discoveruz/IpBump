using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using H.NotifyIcon;
using H.NotifyIcon.Core;

namespace IpBump;

/// <summary>
/// The taskbar (notification area) icon, and the address written next to it.
/// Double-click = new free IP, right-click = menu.
/// </summary>
public class TrayApp : IDisposable
{
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT point);
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    static readonly int[] MouseButtons = [1, 2, 4];   // left, right, middle

    readonly UserSettings _s = UserSettings.Load();
    readonly TaskbarIcon _tray = new() { NoLeftClickDelay = true };
    readonly MenuItem _status = new() { IsHitTestVisible = false, Focusable = false };   // first menu line: a read-only status
    readonly FileSystemWatcher _changes;
    TaskbarLabel _label;   // the address written beside the tray icons, while the user wants it there
    System.Drawing.Icon _icon;
    bool _busy;
    string _problem;   // why the last change failed; stays on the icon and in the menu until something works
    SettingsWindow _settingsOpen;
    DateTime _reported = DateTime.UtcNow;

    public TrayApp()
    {
        var menu = new ContextMenu();
        menu.Items.Add(_status);
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Change IP now", () => _ = ChangeIp()));
        menu.Items.Add(Item("Switch back to automatic (DHCP)", () => _ = UseDhcp()));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Settings…", OpenSettings));
        menu.Items.Add(Item("Exit", () => Application.Current.Shutdown()));
        menu.Opened += (_, _) => CloseOnClickElsewhere(menu);

        _tray.ContextMenu = menu;
        _tray.TrayMouseDoubleClick += (_, _) => _ = ChangeIp();
        UpdateIcon();
        _tray.ForceCreate(enablesEfficiencyMode: false);

        // The icon shows the adapter's real address, whoever changed it
        NetworkChange.NetworkAddressChanged += OnAddressChanged;

        // Changes made by an AI agent happen in another process; it leaves a note here
        Directory.CreateDirectory(UserSettings.Folder);
        _changes = new FileSystemWatcher(UserSettings.Folder, LastChange.FileName) { EnableRaisingEvents = true };
        _changes.Created += (_, _) => OnUi(ReportAgentChange);
        _changes.Changed += (_, _) => OnUi(ReportAgentChange);
        _changes.Renamed += (_, _) => OnUi(ReportAgentChange);

        // First run for this user: open settings once the message loop is running
        if (string.IsNullOrEmpty(_s.Adapter)) OnUi(OpenSettings);
    }

    /// <summary>
    /// Normally Windows makes an opened menu's window the active one, and the menu goes away when another window
    /// takes over. But Windows can refuse (when the click that opened the menu first had to close another program's
    /// menu, say), and such a menu would stay on screen. Until Windows agrees, the mouse buttons are watched from here.
    /// </summary>
    static async void CloseOnClickElsewhere(ContextMenu menu)
    {
        foreach (int button in MouseButtons) GetAsyncKeyState(button);   // forget the click that opened it
        while (menu.IsOpen)
        {
            if (PresentationSource.FromVisual(menu) is HwndSource popup)
            {
                if (GetForegroundWindow() == popup.Handle) return;
                SetForegroundWindow(popup.Handle);
                if (PressedOutside(menu))
                {
                    menu.IsOpen = false;
                    return;
                }
            }
            await Task.Delay(30);
        }
    }

    static bool PressedOutside(ContextMenu menu)
    {
        bool pressed = false;
        foreach (int button in MouseButtons) pressed |= (GetAsyncKeyState(button) & 0x8001) != 0;   // down now, or pressed since the last look
        return pressed && GetCursorPos(out POINT mouse)
            && menu.InputHitTest(menu.PointFromScreen(new Point(mouse.X, mouse.Y))) == null;
    }

    static MenuItem Item(string text, Action run)
    {
        var item = new MenuItem { Header = text };
        item.Click += (_, _) => run();
        return item;
    }

    static void OnUi(Action action) => Application.Current.Dispatcher.BeginInvoke(action);

    void OnAddressChanged(object sender, EventArgs e) => OnUi(UpdateIcon);

    Task ChangeIp()
    {
        if (string.IsNullOrEmpty(_s.Adapter)) { OpenSettings(); return Task.CompletedTask; }
        return Run("Could not change IP", () =>
        {
            var r = IpChanger.ToFreeAddress(_s, IpChanger.Tray, step => OnUi(() => _tray.ToolTipText = step));
            return ("IP changed", $"{r.Adapter}: {r.OldIp} → {r.NewIp}");
        });
    }

    Task UseDhcp() => Run("Could not switch to automatic", () =>
    {
        IpChanger.UseDhcp(_s);
        return ("Automatic address", $"{_s.Adapter} now gets its address from the network (DHCP).");
    });

    /// <summary>Runs a change off the UI thread and reports how it went.</summary>
    async Task Run(string failed, Func<(string Title, string Text)> change)
    {
        if (_busy) return;
        _busy = true;
        UpdateIcon();
        try
        {
            var done = await Task.Run(change);
            _problem = null;
            if (_s.ShowNotifications) _tray.ShowNotification(done.Title, done.Text, NotificationIcon.Info);
        }
        catch (Exception ex)
        {
            // Windows notifications can be switched off, so the icon and menu carry the reason too
            _problem = $"{failed}: {ex.Message}";
            _tray.ShowNotification(failed, ex.Message, NotificationIcon.Error);
        }
        finally
        {
            _busy = false;
            UpdateIcon();
        }
    }

    void ReportAgentChange()
    {
        var last = LastChange.Load();
        if (last == null || last.Source == IpChanger.Tray || last.At <= _reported) return;
        _reported = last.At;
        _problem = null;
        UpdateIcon();
        if (_s.ShowNotifications)
            _tray.ShowNotification($"IP changed by {last.Source}", $"{last.From} → {last.To}", NotificationIcon.Info);
    }

    public void OpenSettings()
    {
        if (_settingsOpen != null) { _settingsOpen.Activate(); return; }
        bool firstRun = string.IsNullOrEmpty(_s.Adapter);
        _settingsOpen = new SettingsWindow(_s);
        _settingsOpen.Closed += (_, _) =>
        {
            _settingsOpen = null;
            _problem = null;
            UpdateIcon();
            // Windows tucks new tray icons away, so say where this one went
            if (firstRun && !string.IsNullOrEmpty(_s.Adapter))
                _tray.ShowNotification("IpBump is ready", "Double-click its icon near the clock for a new IP address. "
                    + "Windows may hide the icon under the ^ arrow: drag it onto the taskbar to keep it in view.", NotificationIcon.Info);
        };
        _settingsOpen.Show();
        _settingsOpen.Activate();
    }

    void UpdateIcon()
    {
        string ip = string.IsNullOrEmpty(_s.Adapter) ? "" : NetApply.ReadCurrent(_s.Adapter)?.Ip ?? "";

        var icon = _busy ? TrayBadge.Draw("…", TrayBadge.Orange)
                 : _problem != null ? TrayBadge.Draw("!", TrayBadge.Red)
                 : ip == "" ? TrayBadge.Draw("–", TrayBadge.Grey)
                 : TrayBadge.Draw(ip.Split('.')[3], TrayBadge.Orange);
        _tray.Icon = icon;
        _icon?.Dispose();
        _icon = icon;
        ShowLabel(ip);

        string state = _problem ?? (ip == "" ? "No address" : $"{ip}  ·  {_s.Adapter}");
        _status.Header = new TextBlock { Text = state, TextWrapping = TextWrapping.Wrap, MaxWidth = 280 };
        if (!_busy) _tray.ToolTipText = Fit($"IpBump  {state}\nDouble-click: new IP   Right-click: menu");
    }

    /// <summary>The full address on the taskbar; the icon only has room for its last number.</summary>
    void ShowLabel(string ip)
    {
        bool wanted = _s.ShowOnTaskbar && !string.IsNullOrEmpty(_s.Adapter);
        if (wanted && _label == null)
        {
            // It behaves like the icon: double-click for a new IP, right-click for the same menu
            _label = new TaskbarLabel();
            _label.DoubleClicked += () => _ = ChangeIp();
            _label.RightClicked += _tray.ShowContextMenu;
        }
        else if (!wanted && _label != null)
        {
            _label.Dispose();
            _label = null;
        }
        _label?.Show(ip, _busy, _problem != null);
    }

    // Windows cuts tray tooltips at 127 characters
    static string Fit(string text) => text.Length <= 127 ? text : text[..126] + "…";

    public void Dispose()
    {
        NetworkChange.NetworkAddressChanged -= OnAddressChanged;
        _changes.Dispose();
        _label?.Dispose();
        _tray.Dispose();
        _icon?.Dispose();
    }
}
