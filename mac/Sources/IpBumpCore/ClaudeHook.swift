import Foundation

/// "IpBump claude-hook": Claude Code runs this when it gives up on a request (its StopFailure hook) and describes
/// the failure on stdin. A refused connection gets a new address. Everything else is left alone: rate limits,
/// sign-in problems and errors the API itself reported have nothing to do with this Mac's address.
public enum ClaudeHook {
    /// Claude Code words it "API Error: Connection refused — a firewall or proxy may be blocking it (ECONNREFUSED)".
    public static func isRefusedConnection(_ input: Data) -> Bool {
        guard case .object(let report)? = try? JSONValue.parse(String(decoding: input, as: UTF8.self)) else {
            return false   // not a failure report
        }
        return ["last_assistant_message", "error_details"].contains { key in
            guard case .string(let text)? = report[key] else { return false }
            return text.range(of: "ECONNREFUSED", options: .caseInsensitive) != nil
                || text.range(of: "connection refused", options: .caseInsensitive) != nil
        }
    }

    /// The exit code. A failed change is logged for Claude Code's debug log; Claude Code itself ignores it.
    public static func run(input: Data, settings: UserSettings, change: () throws -> Void, log: (String) -> Void) -> Int32 {
        guard isRefusedConnection(input), settings.allowAgents else { return 0 }
        do {
            try change()
            return 0
        } catch {
            log((error as? IpBumpError)?.message ?? error.localizedDescription)
            return 1
        }
    }
}
