import Foundation
import Testing
import IpBumpCore
import IpBumpMac

struct MCPRoleTests {
    let child = Child()

    @Test func introducesItself() throws {
        let r = try MCPSession(child).initialize()
        #expect(r["serverInfo"]?["name"] == .string("ipbump"))
        #expect(r["instructions"] == .string(AgentTools.instructions))
    }

    @Test func listsTwoTools() throws {
        let tools = try MCPSession(child).call("tools/list")["tools"]
        #expect(tools?[0]?["name"] == .string("get_ip_status") && tools?[1]?["name"] == .string("change_ip") && tools?[2] == nil)
        #expect(tools?[0]?["annotations"]?["readOnlyHint"] == .bool(true))
        #expect(tools?[1]?["annotations"]?["destructiveHint"] == .bool(false))
    }

    @Test func changeIsRefusedWhileAgentsAreOff() throws {
        let r = try MCPSession(child).tool("change_ip")
        #expect(r["isError"] == .bool(true))
        #expect(text(r) == "AI agent access is switched off in IpBump. Ask the user to turn on \"Let AI agents change the IP\" in IpBump's settings (menu bar, IpBump, Settings…).")
    }

    @Test func statusNeedsSetup() throws {
        #expect(text(try MCPSession(child).tool("get_ip_status"))
            == "IpBump isn't set up yet. Ask the user to open IpBump's settings and pick a network service.")
    }

    @Test func statusReadsThisMac() throws {
        let service = SystemNetwork().defaultService()
        try #require(service != "")
        try child.writeSettings(UserSettings(service: service))
        #expect(text(try MCPSession(child).tool("get_ip_status")).contains("\"service\":\"\(service)\""))
    }

    @Test func stdoutCarriesOnlyMessages() throws {
        let session = try MCPSession(child)
        _ = try session.call("tools/list")
        #expect(!session.stdoutLines.isEmpty)
        for line in session.stdoutLines { #expect(line.contains(#""jsonrpc":"2.0""#), "\(line)") }
    }
}
