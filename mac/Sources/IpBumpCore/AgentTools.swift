/// What the MCP tools do; "IpBump mcp" puts them on the wire.
public struct AgentTools: Sendable {
    public static let instructions =
        "IpBump changes this Mac's local (LAN) IPv4 address. It does not change the public IP that websites see."
    public static let statusTool = "get_ip_status"
    public static let changeTool = "change_ip"
    public static let statusDescription = "Shows the local IPv4 settings of the network service IpBump manages on this Mac: "
        + "address, subnet mask, router, DNS servers and whether the address is manual or from DHCP."
    public static let changeDescription = "Switches this Mac to a different local IPv4 address on the same network. "
        + "IpBump looks for an address no other device is using, applies it and returns the old and new address. "
        + "Takes about 5 seconds; open network connections are reset. Only the local address changes, not the public IP."

    let loadSettings: @Sendable () -> UserSettings
    let reader: NetworkReader
    let changer: IpChanging

    /// Settings are read on every call, so the switch in Settings works at once.
    public init(loadSettings: @escaping @Sendable () -> UserSettings, reader: NetworkReader, changer: IpChanging) {
        self.loadSettings = loadSettings; self.reader = reader; self.changer = changer
    }

    public func status() throws -> String {
        let s = loadSettings()
        guard !s.service.isEmpty else {
            throw IpBumpError("IpBump isn't set up yet. Ask the user to open IpBump's settings and pick a network service.")
        }
        guard let now = reader.current(service: s.service) else {
            throw IpBumpError("Network service \"\(s.service)\" was not found.")
        }
        return JSONValue.object(JSONObject([
            ("service", .string(now.service)),
            ("connected", .bool(now.up)),
            ("mode", .string(now.dhcp ? "automatic (DHCP)" : "manual")),
            ("ip", .string(now.ip)),
            ("subnetMask", .string(now.mask)),
            ("router", .string(now.router)),
            ("dns", .array([now.dns1, now.dns2].filter { !$0.isEmpty }.map(JSONValue.string))),
            ("agentsMayChangeIp", .bool(s.allowAgents)),
        ])).render(pretty: false)
    }

    /// Our own messages are safe and useful to pass on, so errors go to the agent as they are.
    public func change(clientName: String?) throws -> String {
        let s = loadSettings()
        guard s.allowAgents else {
            throw IpBumpError("AI agent access is switched off in IpBump. Ask the user to turn on "
                + "\"Let AI agents change the IP\" in IpBump's settings (menu bar, IpBump, Settings…).")
        }
        let r = try changer.toFreeAddress(s, source: Self.agentLabel(clientName), progress: nil)
        return JSONValue.object(JSONObject([
            ("service", .string(r.service)), ("previousIp", .string(r.oldIp)), ("ip", .string(r.newIp)),
        ])).render(pretty: false)
    }

    /// "claude-code" -> "Claude Code", for the notification in the menu bar app.
    public static func agentLabel(_ clientName: String?) -> String {
        let words = (clientName ?? "")
            .split(whereSeparator: { "-_ ".contains($0) })
            .filter { !["mcp", "client"].contains($0.lowercased()) }
            .map { $0.count <= 3 ? $0.uppercased() : $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? "an AI agent" : words.joined(separator: " ")
    }
}
