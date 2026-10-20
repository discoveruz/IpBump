import Testing
import IpBumpCore

struct HookRoleTests {
    let child = Child()
    let refused = #"{"hook_event_name":"StopFailure","error":"unknown","last_assistant_message":"API Error: Connection refused (ECONNREFUSED)"}"#

    @Test func ignoresAnythingButARefusedConnection() throws {
        #expect(try child.run(["claude-hook"], stdin: "not json").code == 0)
        #expect(try child.run(["claude-hook"], stdin: #"{"last_assistant_message":"API Error: Rate limit reached"}"#).code == 0)
    }

    @Test func staysOffWhileAgentsAreOff() throws {
        let r = try child.run(["claude-hook"], stdin: refused)
        #expect(r.code == 0 && r.stderr.isEmpty)
    }

    @Test func saysWhyItCouldNotChange() throws {
        try child.writeSettings(UserSettings(allowAgents: true))
        let r = try child.run(["claude-hook"], stdin: refused)
        #expect(r.code == 1)
        #expect(r.stderr.contains("IpBump isn't set up yet. Open its settings and pick a network service."))
    }

    @Test func printsItsVersion() throws {
        #expect(try child.run(["--version"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "dev")
    }
}
