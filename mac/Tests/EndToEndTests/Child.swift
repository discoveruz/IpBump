import Foundation
import IpBumpCore

/// The IpBump binary `swift build` made, run with a settings folder and a helper socket of its own.
struct Child {
    let home: URL = {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IpBumpTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    /// Nothing listens here: these tests never reach a helper.
    let socket = "/tmp/ipbump-e2e-\(UUID().uuidString.prefix(8)).sock"

    /// mac/Tests/EndToEndTests/Child.swift -> mac/.build/debug/IpBump
    static let binary = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/IpBump")

    var environment: [String: String] {
        ProcessInfo.processInfo.environment.merging(["IPBUMP_HOME": home.path, "IPBUMP_HELPER_SOCKET": socket]) { $1 }
    }

    func writeSettings(_ settings: UserSettings) throws { try SettingsStore(folder: home).save(settings) }

    func run(_ arguments: [String], stdin: String = "") throws -> (code: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = Self.binary
        process.arguments = arguments
        process.environment = environment
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}

struct Timeout: Error {}

/// "IpBump mcp" with a JSON-RPC conversation on its stdin and stdout, one message per line.
final class MCPSession: @unchecked Sendable {
    let process = Process()
    let input = Pipe(), output = Pipe()
    private let lock = NSLock()
    private var pending = Data()
    private var lines: [String] = []
    private var nextID = 2
    private var initialized: JSONValue?

    init(_ child: Child) throws {
        process.executableURL = Child.binary
        process.arguments = ["mcp"]
        process.environment = child.environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in self?.received(handle.availableData) }
        try process.run()
    }

    deinit {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        process.terminate()
    }

    var stdoutLines: [String] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }

    private func received(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        while let end = pending.firstIndex(of: 0x0A) {
            lines.append(String(decoding: pending[..<end], as: UTF8.self))
            pending.removeSubrange(...end)
        }
    }

    func send(_ json: String) { input.fileHandleForWriting.write(Data((json + "\n").utf8)) }

    /// The "result" of the reply with this id.
    func reply(id: Int) throws -> JSONValue {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            for line in stdoutLines {
                guard let message = try? JSONValue.parse(line), message["id"] == .number("\(id)") else { continue }
                return message["result"] ?? message
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw Timeout()
    }

    func initialize() throws -> JSONValue {
        if let initialized { return initialized }
        send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"claude-code","version":"1.0"}}}"#)
        let result = try reply(id: 1)
        send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        initialized = result
        return result
    }

    func call(_ method: String, _ params: String = "{}") throws -> JSONValue {
        _ = try initialize()
        let id = nextID
        nextID += 1
        send(#"{"jsonrpc":"2.0","id":\#(id),"method":"\#(method)","params":\#(params)}"#)
        return try reply(id: id)
    }

    func tool(_ name: String) throws -> JSONValue { try call("tools/call", #"{"name":"\#(name)","arguments":{}}"#) }
}

/// The text of a tool call's first content item.
func text(_ result: JSONValue) -> String {
    if case .string(let s)? = result["content"]?[0]?["text"] { return s }
    return ""
}
