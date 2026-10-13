using System.Net;
using System.Runtime.InteropServices;

namespace IpBump;

/// <summary>Finds an IPv4 address on the local network that no device is using.</summary>
public static class IpScanner
{
    // ARP rather than ping: firewalls drop pings, but a device can't hold an address without answering ARP.
    [DllImport("iphlpapi.dll", ExactSpelling = true)]
    static extern int SendARP(uint destIp, uint srcIp, byte[] macAddr, ref int macAddrLen);

    const int Batch = 8;        // addresses asked at the same time
    const int WaitMs = 1500;    // Windows repeats the question every second, so silence = two unanswered requests
    const int MaxProbes = 512;
    const int ERROR_NOT_FOUND = 1168;

    /// <summary>The next unused address after <paramref name="current"/> in the search range, or null if they all answered.</summary>
    public static string FindFree(UserSettings s, string current, IEnumerable<string> skip = null)
    {
        var (first, last) = Range(s);
        uint cur = NetApply.IsIPv4(current) ? ToUInt(current) : 0;
        var avoid = new[] { current, s.Gateway, s.Dns1, s.Dns2 }.Concat(skip ?? [])
            .Where(NetApply.IsIPv4).Select(ToUInt).ToHashSet();

        // Walk forward from the current address and wrap around at the end of the range.
        // With no address at all (e.g. DHCP gave none), begin with the one saved in the settings.
        uint count = last - first + 1, saved = ToUInt(s.Ip);
        uint start = cur == 0 && saved >= first && saved <= last ? saved
                   : cur >= first && cur < last ? cur + 1
                   : first;
        var candidates = Enumerable.Range(0, (int)Math.Min(count, MaxProbes))
            .Select(i => first + (start - first + (uint)i) % count)
            .Where(a => !avoid.Contains(a));

        foreach (var batch in candidates.Chunk(Batch))
        {
            var probes = batch.Select(a => Task.Factory.StartNew(() => Answers(a, cur), TaskCreationOptions.LongRunning)).ToArray();
            Task.WaitAll(probes, WaitMs);
            // A device that is there answers within milliseconds; whatever is still silent is free
            for (int i = 0; i < batch.Length; i++)
                if (!(probes[i].IsCompletedSuccessfully && probes[i].Result))
                    return ToString(batch[i]);
        }
        return null;
    }

    /// <summary>First and last address to try: the subnet's usable addresses, narrowed by the user's range.</summary>
    public static (uint First, uint Last) Range(UserSettings s)
    {
        if (!NetApply.IsIPv4(s.Ip) || !NetApply.IsMask(s.Mask))
            throw new InvalidOperationException("Enter the IP address and subnet mask in IpBump's settings first.");

        uint ip = ToUInt(s.Ip), mask = ToUInt(s.Mask);
        uint first = (ip & mask) + 1, last = (ip | ~mask) - 1;   // without the network and broadcast address
        if (first > last) throw new InvalidOperationException($"Subnet mask {s.Mask} leaves no addresses to choose from.");

        uint from = NetApply.IsIPv4(s.RangeStart) ? ToUInt(s.RangeStart) : first;
        uint to = NetApply.IsIPv4(s.RangeEnd) ? ToUInt(s.RangeEnd) : last;
        if (from < first || from > last || to < first || to > last)
            throw new InvalidOperationException($"The search range must be inside this network ({ToString(first)} to {ToString(last)}).");
        if (from > to) throw new InvalidOperationException("The search range's From address comes after its To address.");
        return (from, to);
    }

    /// <summary>True if some device replied for this address.</summary>
    static bool Answers(uint ip, uint from)
    {
        var mac = new byte[6];
        int len = mac.Length;
        int rc = SendARP(Wire(ip), Wire(from), mac, ref len);
        if (rc == ERROR_NOT_FOUND && from != 0)
        {
            // "from" is no longer one of this PC's addresses: let Windows choose the adapter
            len = mac.Length;
            rc = SendARP(Wire(ip), 0, mac, ref len);
        }
        return rc == 0;
    }

    /// <summary>Address as a number for range math: 192.168.44.189 -> 0xC0A82CBD.</summary>
    public static uint ToUInt(string ip)
    {
        var b = IPAddress.Parse(ip).GetAddressBytes();
        return (uint)(b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]);
    }

    public static string ToString(uint ip) => $"{ip >> 24}.{(ip >> 16) & 255}.{(ip >> 8) & 255}.{ip & 255}";

    // SendARP wants the bytes in network order
    static uint Wire(uint ip) => (uint)IPAddress.HostToNetworkOrder((int)ip);
}
