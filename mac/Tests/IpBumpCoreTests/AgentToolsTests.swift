import Testing
@testable import IpBumpCore

struct AgentToolsTests {
    let s = UserSettings(service: "Wi-Fi", ip: "192.168.1.10", mask: "255.255.255.0", router: "192.168.1.1")
    let net = FakeNetwork(state: ServiceState(service: "Wi-Fi", interface: "en0", up: true, dhcp: true, ip: "192.168.1.10"))
    let changer = FakeChanger()

    func tools(_ settings: UserSettings) -> AgentTools {
        AgentTools(loadSettings: { settings }, reader: net, changer: changer)
    }

    @Test func statusNeedsSetup() {
        #expect(throws: IpBumpError("IpBump isn't set up yet. Ask the user to open IpBump's settings and pick a network service.")) {
            try tools(UserSettings()).status()
        }
    }

    /// Review Focus 5: a service that was renamed or removed after setup.
    @Test func statusNamesAMissingService() {
        net.state = nil
        #expect(throws: IpBumpError("Network service \"Wi-Fi\" was not found.")) { try tools(s).status() }
    }

    @Test func statusJson() throws {
        net.state = ServiceState(service: "Wi-Fi", interface: "en0", up: true, dhcp: false, ip: "192.168.1.10",
                                 mask: "255.255.255.0", router: "192.168.1.1", dns1: "8.8.8.8")
        #expect(try tools(s).status()
            == #"{"service":"Wi-Fi","connected":true,"mode":"manual","ip":"192.168.1.10","subnetMask":"255.255.255.0","router":"192.168.1.1","dns":["8.8.8.8"],"agentsMayChangeIp":false}"#)
    }

    @Test func statusSaysDhcp() throws {
        #expect(try tools(s).status().contains(#""mode":"automatic (DHCP)""#))
    }

    @Test func changeIsOffByDefault() {
        #expect(throws: IpBumpError("AI agent access is switched off in IpBump. Ask the user to turn on \"Let AI agents change the IP\" in IpBump's settings (menu bar, IpBump, Settings…).")) {
            try tools(s).change(clientName: "claude-code")
        }
        #expect(changer.sources.isEmpty)
    }

    @Test func changeJsonAndLabel() throws {
        var a = s
        a.allowAgents = true
        changer.result = ChangeResult(service: "Wi-Fi", oldIp: "192.168.1.10", newIp: "192.168.1.20")
        #expect(try tools(a).change(clientName: "claude-code") == #"{"service":"Wi-Fi","previousIp":"192.168.1.10","ip":"192.168.1.20"}"#)
        #expect(changer.sources == ["Claude Code"])
    }

    @Test func changeErrorsPassThrough() {
        var a = s
        a.allowAgents = true
        changer.error = IpBumpError("Every address in the search range is in use.")
        #expect(throws: IpBumpError("Every address in the search range is in use.")) { try tools(a).change(clientName: nil) }
    }

    @Test func labels() {
        #expect(AgentTools.agentLabel(nil) == "an AI agent")
        #expect(AgentTools.agentLabel("mcp") == "an AI agent")
        #expect(AgentTools.agentLabel("claude-code") == "Claude Code")
        #expect(AgentTools.agentLabel("gemini-cli-mcp-client") == "Gemini CLI")
        #expect(AgentTools.agentLabel("claude-ai") == "Claude AI")
    }
}
