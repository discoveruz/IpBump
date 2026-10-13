using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace IpBump;

/// <summary>What gets sent from the tray app to the service.</summary>
public class IpConfig
{
    public string Adapter { get; set; } = "";
    public string Ip { get; set; } = "";
    public string Mask { get; set; } = "";
    public string Gateway { get; set; } = "";
    public string Dns1 { get; set; } = "";
    public string Dns2 { get; set; } = "";
    /// <summary>True = hand the adapter back to DHCP; the address fields are ignored.</summary>
    public bool Dhcp { get; set; }
}

/// <summary>What an adapter is using right now.</summary>
public class AdapterState : IpConfig
{
    public bool Up { get; set; }
}

public record ApplyResponse(bool Ok, string Error);

/// <summary>Result of Windows' own duplicate-address check on a freshly applied address.</summary>
public enum AddressCheck { Usable, Duplicate, TimedOut }

/// <summary>Validates and applies IPv4 settings with netsh. Runs inside the service (as SYSTEM).</summary>
public static class NetApply
{
    public static bool IsIPv4(string s) =>
        !string.IsNullOrWhiteSpace(s)
        && s.Split('.').Length == 4
        && IPAddress.TryParse(s, out var a)
        && a.AddressFamily == AddressFamily.InterNetwork;

    /// <summary>A subnet mask is ones followed by zeros, e.g. 255.255.255.0.</summary>
    public static bool IsMask(string s)
    {
        if (!IsIPv4(s)) return false;
        uint zeros = ~IpScanner.ToUInt(s);
        return zeros != uint.MaxValue && (zeros & (zeros + 1)) == 0;
    }

    public static List<string> AdapterNames() =>
        Adapters().Select(n => n.Name).OrderBy(n => n).ToList();

    /// <summary>The adapter the PC is online with (connected, has a gateway). Used to pre-fill the first run.</summary>
    public static string DefaultAdapter() =>
        Adapters()
            .Where(n => n.OperationalStatus == OperationalStatus.Up)
            .OrderByDescending(n => n.GetIPProperties().GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork))
            .Select(n => n.Name)
            .FirstOrDefault() ?? AdapterNames().FirstOrDefault() ?? "";

    // Windows also lists driver layers ("Ethernet-QoS Packet Scheduler-0000") as interfaces; those have no IPv4 settings.
    static IEnumerable<NetworkInterface> Adapters() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.NetworkInterfaceType != NetworkInterfaceType.Loopback
                     && n.NetworkInterfaceType != NetworkInterfaceType.Tunnel
                     && n.Supports(NetworkInterfaceComponent.IPv4));

    public static void Validate(IpConfig c)
    {
        if (c == null) throw new ArgumentException("Empty request.");
        // Adapter must be a real adapter name: this also prevents passing arbitrary text to netsh.
        if (!AdapterNames().Contains(c.Adapter)) throw new ArgumentException($"Unknown adapter \"{c.Adapter}\".");
        if (c.Dhcp) return;
        if (!IsIPv4(c.Ip)) throw new ArgumentException($"Invalid IP address \"{c.Ip}\".");
        if (!IsIPv4(c.Mask)) throw new ArgumentException($"Invalid subnet mask \"{c.Mask}\".");
        foreach (var opt in new[] { c.Gateway, c.Dns1, c.Dns2 })
            if (!string.IsNullOrWhiteSpace(opt) && !IsIPv4(opt))
                throw new ArgumentException($"Invalid address \"{opt}\".");
    }

    public static void Apply(IpConfig c)
    {
        Validate(c);

        if (c.Dhcp)
        {
            // netsh reports an error when DHCP is already on, so only ask for a real change
            if (ReadCurrent(c.Adapter)?.Dhcp != true)
                Netsh(new() { "interface", "ipv4", "set", "address", c.Adapter, "dhcp" });
            try { Netsh(new() { "interface", "ipv4", "set", "dnsservers", c.Adapter, "dhcp" }); }
            catch (InvalidOperationException) { /* DNS was already automatic */ }
            return;
        }

        var addr = new List<string> { "interface", "ipv4", "set", "address", c.Adapter, "static", c.Ip, c.Mask };
        if (IsIPv4(c.Gateway)) addr.Add(c.Gateway);
        Netsh(addr);

        if (IsIPv4(c.Dns1))
        {
            Netsh(new() { "interface", "ipv4", "set", "dnsservers", c.Adapter, "static", c.Dns1, "primary", "validate=no" });
            if (IsIPv4(c.Dns2))
                Netsh(new() { "interface", "ipv4", "add", "dnsservers", c.Adapter, c.Dns2, "index=2", "validate=no" });
        }
        else
        {
            Netsh(new() { "interface", "ipv4", "set", "dnsservers", c.Adapter, "dhcp" });
        }
    }

    /// <summary>Reads what the adapter is using right now. Null if there is no such adapter.</summary>
    public static AdapterState ReadCurrent(string adapter)
    {
        var nic = Adapters().FirstOrDefault(n => n.Name == adapter);
        if (nic == null) return null;
        var p = nic.GetIPProperties();
        // 169.254.x.x is what Windows gives itself when it has no real address
        var uni = p.UnicastAddresses.FirstOrDefault(u => u.Address.AddressFamily == AddressFamily.InterNetwork
                                                      && !u.Address.ToString().StartsWith("169.254."));
        var dns = p.DnsAddresses.Where(d => d.AddressFamily == AddressFamily.InterNetwork).ToList();
        return new AdapterState
        {
            Adapter = adapter,
            Up = nic.OperationalStatus == OperationalStatus.Up,
            Dhcp = p.GetIPv4Properties()?.IsDhcpEnabled == true,
            Ip = uni?.Address.ToString() ?? "",
            Mask = uni?.IPv4Mask.ToString() ?? "",
            Gateway = p.GatewayAddresses.FirstOrDefault(g => g.Address.AddressFamily == AddressFamily.InterNetwork)?.Address.ToString() ?? "",
            Dns1 = dns.Count > 0 ? dns[0].ToString() : "",
            Dns2 = dns.Count > 1 ? dns[1].ToString() : "",
        };
    }

    /// <summary>
    /// After an address is set, Windows asks the network whether anyone else has it and only then
    /// starts using it. Waits for that verdict.
    /// </summary>
    public static AddressCheck WaitUntilUsable(string adapter, string ip, int timeoutMs = 10000)
    {
        var want = IPAddress.Parse(ip);
        var clock = Stopwatch.StartNew();
        while (clock.ElapsedMilliseconds < timeoutMs)
        {
            var state = Adapters().FirstOrDefault(n => n.Name == adapter)?
                .GetIPProperties().UnicastAddresses.FirstOrDefault(u => u.Address.Equals(want))?
                .DuplicateAddressDetectionState;
            if (state == DuplicateAddressDetectionState.Preferred) return AddressCheck.Usable;
            if (state == DuplicateAddressDetectionState.Duplicate) return AddressCheck.Duplicate;
            Thread.Sleep(200);
        }
        return AddressCheck.TimedOut;
    }

    static void Netsh(List<string> args)
    {
        var psi = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "netsh.exe"))
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        using var p = Process.Start(psi)!;
        string output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
        p.WaitForExit();
        if (p.ExitCode != 0)
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(output) ? $"netsh failed ({p.ExitCode})" : output.Trim());
    }
}
