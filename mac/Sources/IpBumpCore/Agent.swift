import Foundation

/// An AI agent on this Mac and its connection to IpBump (the Connect buttons in the Settings window).
/// Connecting writes into the agent's own configuration what "claude mcp add" or "gemini mcp add" would:
/// start "IpBump mcp" as an MCP server. Claude Code is also told to run "IpBump claude-hook"
/// whenever it gives up on a request.
public struct Agent: Sendable {
    public static let serverName = "ipbump"
    /// Claude Code's name for "the turn ended with an API error".
    public static let failureHook = "StopFailure"

    public let name: String
    /// Exists once the agent has been started by this user.
    public let folder: URL
    /// The file that lists its MCP servers.
    public let servers: URL
    /// The file that lists its hooks, for an agent that can react to a failed request.
    public let hooks: URL?
    /// The IpBump the agent should start: this copy.
    public let executable: String

    public init(name: String, folder: URL, servers: URL, hooks: URL?, executable: String) {
        self.name = name; self.folder = folder; self.servers = servers; self.hooks = hooks; self.executable = executable
    }

    public static func all(home: URL, executable: String) -> [Agent] {
        let claude = home.appendingPathComponent(".claude"), gemini = home.appendingPathComponent(".gemini")
        let desktop = home.appendingPathComponent("Library/Application Support/Claude")
        return [
            Agent(name: "Claude Code", folder: claude, servers: home.appendingPathComponent(".claude.json"),
                  hooks: claude.appendingPathComponent("settings.json"), executable: executable),
            Agent(name: "Gemini CLI", folder: gemini, servers: gemini.appendingPathComponent("settings.json"),
                  hooks: nil, executable: executable),
            Agent(name: "Claude Desktop", folder: desktop, servers: desktop.appendingPathComponent("claude_desktop_config.json"),
                  hooks: nil, executable: executable),
        ]
    }

    /// Whether the agent is set up to start this copy of IpBump, not one that was installed elsewhere.
    /// A file that can't be read counts as not connected; Connect says what is wrong with it.
    public var isConnected: Bool {
        guard let config = try? read(servers), isThisExe(config["mcpServers"]?[Self.serverName]) else { return false }
        guard let hooks else { return true }
        guard let hookConfig = try? read(hooks) else { return false }
        return Self.handlerLists(hookConfig).joined().contains(where: isThisExe)
    }

    public func connect() throws {
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw IpBumpError("\(name) was not found for your Mac account. Start it once, then connect again.")
        }
        try edit(servers) { config in
            var servers = try section(config, "mcpServers")
            servers[Self.serverName] = .object(JSONObject([
                ("command", .string(executable)), ("args", .array([.string("mcp")])),
            ]))
            config["mcpServers"] = .object(servers)
        }
        if let hooks {
            try edit(hooks) { config in
                removeHandlers(&config)   // an IpBump installed somewhere else may have left its own
                var hooks = try section(config, "hooks")
                var groups: [JSONValue] = []
                if case .array(let existing)? = hooks[Self.failureHook] { groups = existing }
                // "args" makes Claude Code start the program directly, so no shell has to cope with the path
                let handler = JSONValue.object(JSONObject([
                    ("type", .string("command")), ("command", .string(executable)), ("args", .array([.string("claude-hook")])),
                ]))
                groups.append(.object(JSONObject([("hooks", .array([handler]))])))
                hooks[Self.failureHook] = .array(groups)
                config["hooks"] = .object(hooks)
            }
        }
    }

    public func disconnect() throws {
        try edit(servers) { config in
            guard case .object(var servers)? = config["mcpServers"] else { return }
            servers[Self.serverName] = nil
            config["mcpServers"] = .object(servers)
        }
        if let hooks {
            try edit(hooks) { config in
                removeHandlers(&config)
                // Along with the wrappers that are empty without them
                guard case .object(var hooks)? = config["hooks"] else { return }
                if case .array(let groups)? = hooks[Self.failureHook], groups.isEmpty { hooks[Self.failureHook] = nil }
                config["hooks"] = hooks.count == 0 ? nil : .object(hooks)
            }
        }
    }

    /// The program a server entry or a hook handler starts.
    static func command(_ entry: JSONValue?) -> String {
        if case .string(let path)? = entry?["command"] { return path }
        return ""
    }

    // Mac disks ignore case unless formatted otherwise, so paths compare that way too
    func isThisExe(_ entry: JSONValue?) -> Bool {
        Self.command(entry).caseInsensitiveCompare(executable) == .orderedSame
    }

    func isIpBump(_ entry: JSONValue) -> Bool {
        let name = { (path: String) in (path as NSString).lastPathComponent }
        return name(Self.command(entry)).caseInsensitiveCompare(name(executable)) == .orderedSame
    }

    /// Claude Code keeps them as  "hooks": { "StopFailure": [ { "hooks": [ handler, ... ] }, ... ] }
    static func handlerLists(_ config: JSONObject) -> [[JSONValue]] {
        guard case .array(let groups)? = config["hooks"]?[failureHook] else { return [] }
        return groups.compactMap { group in
            if case .array(let list)? = group["hooks"] { return list }
            return nil
        }
    }

    /// Takes IpBump's handlers out, along with the groups that are empty without them.
    func removeHandlers(_ config: inout JSONObject) {
        guard case .object(var hooks)? = config["hooks"], case .array(let groups)? = hooks[Self.failureHook] else { return }
        var kept: [JSONValue] = []
        for group in groups {
            guard case .object(var g) = group, case .array(let list)? = g["hooks"] else {
                kept.append(group)
                continue
            }
            let others = list.filter { !isIpBump($0) }
            if others.isEmpty { continue }
            g["hooks"] = .array(others)
            kept.append(.object(g))
        }
        hooks[Self.failureHook] = .array(kept)
        config["hooks"] = .object(hooks)
    }

    func section(_ config: JSONObject, _ name: String) throws -> JSONObject {
        switch config[name] {
        case .object(let there)?: return there
        case nil: return JSONObject()
        default: throw IpBumpError("\"\(name)\" is not a JSON object.")
        }
    }

    func read(_ file: URL) throws -> JSONObject {
        let text = FileManager.default.fileExists(atPath: file.path) ? try String(contentsOf: file, encoding: .utf8) : ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return JSONObject() }
        guard case .object(let config) = try JSONValue.parse(text) else { throw IpBumpError("It does not hold a JSON object.") }
        return config
    }

    func edit(_ file: URL, _ change: (inout JSONObject) throws -> Void) throws {
        do {
            var config = try read(file)
            let before = JSONValue.object(config).render(pretty: false)
            try change(&config)
            let after = JSONValue.object(config)
            if after.render(pretty: false) == before { return }
            try Self.replace(file, with: Array(after.render(pretty: true).utf8))
        } catch {
            let reason = (error as? IpBumpError)?.message ?? (error as? JSONValue.ParseError)?.description ?? error.localizedDescription
            throw IpBumpError("Could not update \(file.path). \(reason)")
        }
    }

    /// Written aside and moved into place, so the agent never reads half a file. A config linked in from elsewhere
    /// (dotfiles) stays a link: the file it points to is the one replaced. The file keeps its permissions; a new one
    /// is readable by its owner only, since these files can hold tokens.
    static func replace(_ file: URL, with bytes: [UInt8]) throws {
        let real = file.resolvingSymlinksInPath()
        let attributes = try? FileManager.default.attributesOfItem(atPath: real.path)
        let mode = mode_t((attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0o600)
        let aside = real.path + ".ipbump.tmp"

        unlink(aside)   // left over from an attempt that was cut short
        let fd = open(aside, O_WRONLY | O_CREAT | O_EXCL, mode)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var failure: Int32 = fchmod(fd, mode) == 0 ? 0 : errno   // the umask must not change the bits
        var written = 0
        while failure == 0 && written < bytes.count {
            let n = bytes[written...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n < 0 { failure = errno } else { written += n }
        }
        close(fd)
        if failure == 0 && rename(aside, real.path) != 0 { failure = errno }
        if failure != 0 {
            unlink(aside)
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
    }
}
