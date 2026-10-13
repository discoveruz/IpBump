using System.Windows;
using System.Windows.Controls;
using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;

namespace IpBump;

/// <summary>Per-user settings window, modelled on Windows 11's "Edit IP settings".</summary>
public partial class SettingsWindow : FluentWindow
{
    readonly UserSettings _s;

    public SettingsWindow(UserSettings s)
    {
        _s = s;
        InitializeComponent();
        SystemThemeWatcher.Watch(this, WindowBackdropType.None);   // restyles the title bar if Windows switches dark/light
        Height = Math.Min(Height, SystemParameters.WorkArea.Height - 40);   // fits small laptop screens; the form scrolls
        About.Text = "IpBump " + Program.Version + "  ·  settings are saved for your Windows account only";

        foreach (var name in NetApply.AdapterNames()) Adapter.Items.Add(name);
        bool firstRun = string.IsNullOrEmpty(s.Adapter);
        Adapter.SelectedItem = firstRun ? NetApply.DefaultAdapter() : s.Adapter;   // fills the fields on first run
        if (Adapter.SelectedIndex < 0 && Adapter.Items.Count > 0) Adapter.SelectedIndex = 0;

        if (!firstRun)
        {
            Mask.Text = s.Mask; Gateway.Text = s.Gateway; Dns1.Text = s.Dns1; Dns2.Text = s.Dns2;
            // IpBump moves the address around, so show the one in use rather than the one saved
            var live = NetApply.ReadCurrent(s.Adapter);
            Ip.Text = live != null && SameNetwork(live.Ip, s.Ip, s.Mask) ? live.Ip : s.Ip;
        }
        RangeStart.Text = s.RangeStart; RangeEnd.Text = s.RangeEnd;
        AllowAgents.IsChecked = s.AllowAgents;
        Agents.ItemsSource = Agent.All();
        OnTaskbar.IsChecked = s.ShowOnTaskbar;
        Notify.IsChecked = s.ShowNotifications;
    }

    static bool SameNetwork(string a, string b, string mask) =>
        NetApply.IsIPv4(a) && NetApply.IsIPv4(b) && NetApply.IsMask(mask)
        && (IpScanner.ToUInt(a) & IpScanner.ToUInt(mask)) == (IpScanner.ToUInt(b) & IpScanner.ToUInt(mask));

    void Adapter_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (Adapter.SelectedItem is not string name) return;
        var live = NetApply.ReadCurrent(name);
        AdapterStatus.Text = live == null ? "" :
            !live.Up ? "Not connected" :
            live.Dhcp ? "Connected  ·  address assigned automatically (DHCP)" : "Connected  ·  manual address";
        // A different adapter is a different network: start from what it uses now
        if (name != _s.Adapter) ReadFromAdapter();
    }

    // The empty range boxes show what "the whole network" means for the address and mask typed above
    void Network_TextChanged(object sender, TextChangedEventArgs e)
    {
        try
        {
            var (first, last) = IpScanner.Range(new UserSettings { Ip = Ip.Text.Trim(), Mask = Mask.Text.Trim() });
            RangeStart.PlaceholderText = IpScanner.ToString(first);
            RangeEnd.PlaceholderText = IpScanner.ToString(last);
        }
        catch (InvalidOperationException)
        {
            RangeStart.PlaceholderText = RangeEnd.PlaceholderText = "";
        }
    }

    void ReadFromAdapter_Click(object sender, RoutedEventArgs e) => ReadFromAdapter();

    void ReadFromAdapter()
    {
        if (Adapter.SelectedItem is not string name) return;
        var cur = NetApply.ReadCurrent(name);
        if (cur == null) { ShowError("Adapter not found."); return; }
        Ip.Text = cur.Ip; Mask.Text = cur.Mask; Gateway.Text = cur.Gateway; Dns1.Text = cur.Dns1; Dns2.Text = cur.Dns2;
    }

    async void Save_Click(object sender, RoutedEventArgs e)
    {
        Error.Visibility = Visibility.Collapsed;
        if (Adapter.SelectedItem is not string adapter) { ShowError("Pick a network adapter.", Adapter); return; }
        if (!NetApply.IsIPv4(Ip.Text.Trim())) { Bad(Ip, "Enter an IP address."); return; }
        if (!NetApply.IsMask(Mask.Text.Trim())) { Bad(Mask, "Enter a subnet mask, such as 255.255.255.0."); return; }
        foreach (var t in new[] { Gateway, Dns1, Dns2, RangeStart, RangeEnd })
            if (t.Text.Trim() != "" && !NetApply.IsIPv4(t.Text.Trim())) { Bad(t); return; }

        var edited = new UserSettings
        {
            Adapter = adapter,
            Ip = Ip.Text.Trim(), Mask = Mask.Text.Trim(), Gateway = Gateway.Text.Trim(),
            Dns1 = Dns1.Text.Trim(), Dns2 = Dns2.Text.Trim(),
        };
        try { IpScanner.Range(edited); }                       // the address and mask on their own
        catch (InvalidOperationException ex) { ShowError(ex.Message, Mask); return; }

        edited.RangeStart = RangeStart.Text.Trim(); edited.RangeEnd = RangeEnd.Text.Trim();
        try { IpScanner.Range(edited); }                       // then the search range inside that network
        catch (InvalidOperationException ex) { ShowError(ex.Message, RangeStart); return; }

        _s.Adapter = edited.Adapter;
        _s.Ip = edited.Ip; _s.Mask = edited.Mask; _s.Gateway = edited.Gateway;
        _s.Dns1 = edited.Dns1; _s.Dns2 = edited.Dns2;
        _s.RangeStart = edited.RangeStart; _s.RangeEnd = edited.RangeEnd;
        _s.AllowAgents = AllowAgents.IsChecked == true;
        _s.ShowOnTaskbar = OnTaskbar.IsChecked == true;
        _s.ShowNotifications = Notify.IsChecked == true;
        _s.Save();

        // Like the Windows dialog, Save also applies - but only when the adapter isn't already set this way
        var live = NetApply.ReadCurrent(adapter);
        if (live != null && live.Ip == _s.Ip && live.Mask == _s.Mask && live.Gateway == _s.Gateway
            && live.Dns1 == _s.Dns1 && live.Dns2 == _s.Dns2)
        {
            Close();
            return;
        }

        Busy(true);
        try
        {
            await Task.Run(() => IpChanger.ApplySettings(_s));
            Close();
        }
        catch (Exception ex)
        {
            Busy(false);
            ShowError(ex.Message);
        }
    }

    void Cancel_Click(object sender, RoutedEventArgs e) => Close();

    // Connect and Disconnect act at once, in the agent's own files; Save and Cancel have no part in it
    void Agent_Click(object sender, RoutedEventArgs e)
    {
        var agent = (Agent)((FrameworkElement)sender).DataContext;
        Error.Visibility = AgentHint.Visibility = Visibility.Collapsed;
        try
        {
            bool connect = !agent.Connected;
            if (connect) agent.Connect(); else agent.Disconnect();
            AgentHint.Text = connect
                ? $"Connected. Restart {agent.Name} and it can use IpBump."
                : $"Disconnected. {agent.Name} lets go of IpBump when it restarts.";
            AgentHint.Visibility = Visibility.Visible;
        }
        catch (InvalidOperationException ex)
        {
            ShowError(ex.Message);
        }
    }

    void Busy(bool busy)
    {
        Form.IsEnabled = SaveButton.IsEnabled = !busy;
        SaveButton.Content = busy ? "Applying…" : "Save";
    }

    void ShowError(string message, Control field = null)
    {
        ErrorText.Text = message;
        Error.Visibility = Visibility.Visible;
        field?.Focus();   // also scrolls it into view
        (field as System.Windows.Controls.TextBox)?.SelectAll();
    }

    void Bad(Wpf.Ui.Controls.TextBox t, string whenEmpty = null) =>
        ShowError(t.Text.Trim() == "" && whenEmpty != null
            ? whenEmpty
            : $"\"{t.Text.Trim()}\" is not a valid {(t == Mask ? "subnet mask" : "IPv4 address")}.", t);
}
