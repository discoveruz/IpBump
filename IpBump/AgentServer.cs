using System.Text.Json;
using ModelContextProtocol;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;

namespace IpBump;

/// <summary>
/// Lets AI agents (Claude, Gemini, ...) use IpBump. "IpBump.exe mcp" is an MCP server on stdin/stdout;
/// the agent starts it itself once it has been connected in the settings window (see <see cref="Agent"/>).
/// </summary>
public static class AgentServer
{
    public const string Name = "ipbump";

    public static int Run()
    {
        var options = new McpServerOptions
        {
            ServerInfo = new Implementation { Name = Name, Version = Program.Version },
            ServerInstructions =
                "IpBump changes this Windows PC's local (LAN) IPv4 address. It does not change the public IP that websites see.",
            ToolCollection =
            [
                McpServerTool.Create(GetIpStatus, new()
                {
                    Name = "get_ip_status",
                    Description = "Shows the local IPv4 settings of the network adapter IpBump manages on this PC: "
                                + "address, subnet mask, gateway, DNS servers and whether the address is manual or from DHCP.",
                    ReadOnly = true,
                }),
                McpServerTool.Create(ChangeIp, new()
                {
                    Name = "change_ip",
                    Description = "Switches this PC to a different local IPv4 address on the same network. IpBump looks for an "
                                + "address no other device is using, applies it and returns the old and new address. Takes about "
                                + "5 seconds; open network connections are reset. Only the local address changes, not the public IP.",
                    ReadOnly = false,
                    Destructive = false,
                    Idempotent = false,
                    OpenWorld = false,
                }),
            ],
        };

        var server = McpServer.Create(new StdioServerTransport(Name), options);
        server.RunAsync().GetAwaiter().GetResult();   // returns when the agent closes stdin
        server.DisposeAsync().AsTask().GetAwaiter().GetResult();
        return 0;
    }

    static string GetIpStatus()
    {
        var s = UserSettings.Load();
        if (string.IsNullOrEmpty(s.Adapter))
            throw new McpException("IpBump isn't set up yet. Ask the user to open IpBump's settings and pick a network adapter.");
        var now = NetApply.ReadCurrent(s.Adapter)
            ?? throw new McpException($"Network adapter \"{s.Adapter}\" was not found.");

        return JsonSerializer.Serialize(new
        {
            adapter = now.Adapter,
            connected = now.Up,
            mode = now.Dhcp ? "automatic (DHCP)" : "manual",
            ip = now.Ip,
            subnetMask = now.Mask,
            gateway = now.Gateway,
            dns = new[] { now.Dns1, now.Dns2 }.Where(d => d != ""),
            agentsMayChangeIp = s.AllowAgents,
        });
    }

    static string ChangeIp(McpServer server)
    {
        var s = UserSettings.Load();   // read every time, so the switch in Settings works immediately
        if (!s.AllowAgents)
            throw new McpException("AI agent access is switched off in IpBump. Ask the user to turn on "
                                 + "\"Let AI agents change the IP\" in IpBump's settings (tray icon, right-click, Settings).");
        try
        {
            var r = IpChanger.ToFreeAddress(s, AgentLabel(server.ClientInfo?.Name));
            return JsonSerializer.Serialize(new { adapter = r.Adapter, previousIp = r.OldIp, ip = r.NewIp });
        }
        catch (Exception ex) when (ex is not McpException)
        {
            throw new McpException(ex.Message);   // our own messages are safe and useful to pass on
        }
    }

    /// <summary>"claude-code" -> "Claude Code", for the tray notification.</summary>
    static string AgentLabel(string clientName)
    {
        if (string.IsNullOrWhiteSpace(clientName)) return "an AI agent";
        var words = clientName.Split(new[] { '-', '_', ' ' }, StringSplitOptions.RemoveEmptyEntries)
            .Where(w => !w.Equals("mcp", StringComparison.OrdinalIgnoreCase) && !w.Equals("client", StringComparison.OrdinalIgnoreCase))
            .Select(w => w.Length <= 3 ? w.ToUpperInvariant() : char.ToUpperInvariant(w[0]) + w[1..]);
        string label = string.Join(" ", words);
        return label == "" ? "an AI agent" : label;
    }

    /// <summary>
    /// "IpBump.exe claude-hook": Claude Code runs this when it gives up on a request (its StopFailure hook) and
    /// describes the failure on stdin. A refused connection gets a new address. Everything else is left alone:
    /// rate limits, sign-in problems and errors the API itself reported have nothing to do with this PC's address.
    /// </summary>
    public static int RunClaudeHook()
    {
        string error;
        try
        {
            using var failure = JsonDocument.Parse(Console.OpenStandardInput());
            error = failure.RootElement.GetProperty("last_assistant_message").GetString() ?? "";
        }
        catch (Exception ex) when (ex is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            return 0;   // not a failure report
        }

        // Claude Code words it "API Error: Connection refused — a firewall or proxy may be blocking it (ECONNREFUSED)"
        if (!error.Contains("ECONNREFUSED", StringComparison.OrdinalIgnoreCase)
            && !error.Contains("connection refused", StringComparison.OrdinalIgnoreCase)) return 0;

        var s = UserSettings.Load();
        if (!s.AllowAgents) return 0;
        try
        {
            IpChanger.ToFreeAddress(s, "Claude Code");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.Message);   // Claude Code ignores it, but keeps it in its debug log
            return 1;
        }
    }
}
