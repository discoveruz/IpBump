import Foundation
import Testing
@testable import IpBumpCore

struct AgentTests {
    let home = temporaryFolder()
    let exe = "/Applications/IpBump.app/Contents/MacOS/IpBump"
    var claude: Agent { Agent.all(home: home, executable: exe)[0] }

    func path(_ relative: String) -> String { home.appendingPathComponent(relative).path }
    func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(atPath: path(relative), withIntermediateDirectories: true)
    }
    func write(_ relative: String, _ text: String, mode: Int = 0o644) throws {
        try text.write(toFile: path(relative), atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path(relative))
    }
    func text(_ relative: String) throws -> String { try String(contentsOfFile: path(relative), encoding: .utf8) }
    func compact(_ relative: String) throws -> String { try JSONValue.parse(text(relative)).render(pretty: false) }
    func mode(_ relative: String) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: path(relative))[.posixPermissions] as! NSNumber).intValue
    }
    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: path(relative)) }
    func symlink(_ relative: String, to target: String) throws {
        try FileManager.default.createSymbolicLink(atPath: path(relative), withDestinationPath: path(target))
    }
    func isSymlink(_ relative: String) -> Bool { (try? FileManager.default.destinationOfSymbolicLink(atPath: path(relative))) != nil }

    @Test func knowsWhereEachAgentKeepsItsConfig() {
        let a = Agent.all(home: home, executable: exe)
        #expect(a.map(\.name) == ["Claude Code", "Gemini CLI", "Claude Desktop"])
        #expect(a[0].servers.path == path(".claude.json"))
        #expect(a[0].hooks?.path == path(".claude/settings.json"))
        #expect(a[1].servers.path == path(".gemini/settings.json") && a[1].hooks == nil)
        #expect(a[2].servers.path == path("Library/Application Support/Claude/claude_desktop_config.json"))
    }

    @Test func connectNeedsTheAgentToHaveRunOnce() {
        #expect(throws: IpBumpError("Claude Code was not found for your Mac account. Start it once, then connect again.")) {
            try claude.connect()
        }
    }

    @Test func connectsClaudeCode() throws {
        try mkdir(".claude")
        try claude.connect()
        #expect(try compact(".claude.json") == #"{"mcpServers":{"ipbump":{"command":"\#(exe)","args":["mcp"]}}}"#)
        #expect(try compact(".claude/settings.json")
            == #"{"hooks":{"StopFailure":[{"hooks":[{"type":"command","command":"\#(exe)","args":["claude-hook"]}]}]}}"#)
        #expect(claude.isConnected)
    }

    @Test func keepsEverythingElse() throws {
        try mkdir(".claude")
        try write(".claude.json", #"{"numStartups":42,"mcpServers":{"other":{"command":"x"}},"zeta":"ʻ"}"#)
        try claude.connect()
        #expect(try compact(".claude.json")
            == #"{"numStartups":42,"mcpServers":{"other":{"command":"x"},"ipbump":{"command":"\#(exe)","args":["mcp"]}},"zeta":"ʻ"}"#)
    }

    @Test func replacesAnOldIpBumpHookAndKeepsOthers() throws {
        try mkdir(".claude")
        try write(".claude/settings.json",
                  #"{"hooks":{"StopFailure":[{"hooks":[{"type":"command","command":"/old/IpBump","args":["claude-hook"]},{"type":"command","command":"notify"}]}]}}"#)
        try claude.connect()
        try claude.connect()
        #expect(try compact(".claude/settings.json")
            == #"{"hooks":{"StopFailure":[{"hooks":[{"type":"command","command":"notify"}]},{"hooks":[{"type":"command","command":"\#(exe)","args":["claude-hook"]}]}]}}"#)
    }

    @Test func disconnectCleansUp() throws {
        try mkdir(".claude")
        try claude.connect()
        try claude.disconnect()
        #expect(try compact(".claude.json") == #"{"mcpServers":{}}"#)
        #expect(try compact(".claude/settings.json") == "{}")
        #expect(!claude.isConnected)
    }

    @Test func otherAgentsHaveNoHook() throws {
        try mkdir(".gemini")
        let gemini = Agent.all(home: home, executable: exe)[1]
        try gemini.connect()
        #expect(try compact(".gemini/settings.json") == #"{"mcpServers":{"ipbump":{"command":"\#(exe)","args":["mcp"]}}}"#)
        #expect(gemini.isConnected)
    }

    @Test func aCopyElsewhereIsNotConnected() throws {
        try mkdir(".gemini")
        try write(".gemini/settings.json", #"{"mcpServers":{"ipbump":{"command":"/Users/x/IpBump","args":["mcp"]}}}"#)
        #expect(!Agent.all(home: home, executable: exe)[1].isConnected)
    }

    @Test func explainsBrokenFiles() throws {
        try mkdir(".claude")
        try write(".claude.json", #"{"mcpServers":"x"}"#)
        #expect(throws: IpBumpError("Could not update \(path(".claude.json")). \"mcpServers\" is not a JSON object.")) {
            try claude.connect()
        }
        #expect(!claude.isConnected)

        try write(".claude.json", "{oops")
        let error = try #require(throws: IpBumpError.self) { try claude.connect() }
        #expect(error.message.hasPrefix("Could not update \(path(".claude.json")). It is not valid JSON"))
    }

    @Test func leavesUnchangedFilesAlone() throws {
        try mkdir(".claude")
        try claude.disconnect()
        #expect(!exists(".claude.json") && !exists(".claude/settings.json"))
    }

    /// Review Focus 1: ~/.claude.json is private to its owner and must stay that way.
    @Test func keepsFilePermissions() throws {
        try mkdir(".claude")
        try write(".claude.json", "{}", mode: 0o600)
        try claude.connect()
        #expect(try mode(".claude.json") == 0o600)
    }

    /// Review Focus 2: dotfiles setups link the config in from elsewhere.
    @Test func followsSymlinkedConfig() throws {
        try mkdir(".claude")
        try mkdir("dotfiles")
        try write("dotfiles/settings.json", "{}")
        try symlink(".claude/settings.json", to: "dotfiles/settings.json")
        try claude.connect()
        #expect(isSymlink(".claude/settings.json"))
        #expect(try compact("dotfiles/settings.json").contains("claude-hook"))
    }

    /// Review fix: a dotfiles link (relative, as GNU stow writes them) whose file doesn't exist yet stays a link,
    /// and the file it names is created readable by its owner only.
    @Test func followsADanglingLink() throws {
        try mkdir(".claude")
        try mkdir("dotfiles")
        try FileManager.default.createSymbolicLink(atPath: path(".claude/settings.json"), withDestinationPath: "../dotfiles/settings.json")
        try claude.connect()
        #expect(isSymlink(".claude/settings.json"))
        #expect(try compact("dotfiles/settings.json").contains("claude-hook"))
        #expect(try mode("dotfiles/settings.json") == 0o600)
    }

    @Test func newFilesArePrivate() throws {
        try mkdir(".claude")
        try claude.connect()
        #expect(try mode(".claude.json") == 0o600 && mode(".claude/settings.json") == 0o600)
    }

    @Test func disconnectKeepsFilePermissions() throws {
        try mkdir(".claude")
        try write(".claude.json", "{}", mode: 0o640)
        try claude.connect()
        try claude.disconnect()
        #expect(try mode(".claude.json") == 0o640)
    }

    @Test func writesTwoSpaceJson() throws {
        try mkdir(".claude")
        try claude.connect()
        #expect(try text(".claude.json").hasPrefix("{\n  \"mcpServers\": {"))
    }
}
