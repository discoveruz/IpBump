import Foundation
import Testing
@testable import IpBumpCore

struct ClaudeHookTests {
    let refused = Data(#"{"hook_event_name":"StopFailure","error":"unknown","last_assistant_message":"API Error: Connection refused — a firewall or proxy may be blocking it (ECONNREFUSED)"}"#.utf8)

    @Test func ignoresOtherFailures() {
        #expect(!ClaudeHook.isRefusedConnection(Data("not json".utf8)))
        #expect(!ClaudeHook.isRefusedConnection(Data(#"{"last_assistant_message":"API Error: Rate limit reached"}"#.utf8)))
    }

    @Test func seesRefusedConnections() {
        #expect(ClaudeHook.isRefusedConnection(refused))
        #expect(ClaudeHook.isRefusedConnection(Data(#"{"error_details":"connect ECONNREFUSED 1.2.3.4:443"}"#.utf8)))
    }

    @Test func staysOffWhileAgentsAreOff() {
        var called = false
        #expect(ClaudeHook.run(input: refused, settings: UserSettings(), change: { called = true }, log: { _ in }) == 0)
        #expect(!called)
    }

    @Test func changesWhenAllowed() {
        var s = UserSettings()
        s.allowAgents = true
        var called = false
        #expect(ClaudeHook.run(input: refused, settings: s, change: { called = true }, log: { _ in }) == 0)
        #expect(called)
    }

    @Test func leavesOtherFailuresAloneEvenWhenAllowed() {
        var s = UserSettings()
        s.allowAgents = true
        var called = false
        let limited = Data(#"{"last_assistant_message":"API Error: Rate limit reached"}"#.utf8)
        #expect(ClaudeHook.run(input: limited, settings: s, change: { called = true }, log: { _ in }) == 0)
        #expect(!called)
    }

    @Test func reportsFailures() {
        var s = UserSettings()
        s.allowAgents = true
        var logged = ""
        #expect(ClaudeHook.run(input: refused, settings: s, change: { throw IpBumpError("boom") }, log: { logged = $0 }) == 1)
        #expect(logged == "boom")
    }
}
