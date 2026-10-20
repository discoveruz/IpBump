import Foundation
import IpBumpCore
import IpBumpMac

/// "IpBump claude-hook": Claude Code's StopFailure hook (see ClaudeHook). Claude Code ignores what it prints,
/// but keeps stderr in its debug log.
enum HookRole {
    static func run() -> Int32 {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let settings = Wiring.settings().load()
        return ClaudeHook.run(
            input: input, settings: settings,
            change: { _ = try Wiring.changer().toFreeAddress(settings, source: "Claude Code", progress: nil) },
            log: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
    }
}
