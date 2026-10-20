import Foundation
import IpBumpCore
import IpBumpMac
import MCP

/// "IpBump mcp": an MCP server on stdin and stdout. The agent starts it itself once it has been connected in
/// Settings (see Agent). stdout carries nothing but MCP messages.
enum MCPRole {
    static let tools = [
        Tool(name: AgentTools.statusTool, description: AgentTools.statusDescription,
             inputSchema: ["type": "object", "properties": [:]],
             annotations: .init(readOnlyHint: true)),
        Tool(name: AgentTools.changeTool, description: AgentTools.changeDescription,
             inputSchema: ["type": "object", "properties": [:]],
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)),
    ]

    /// The name the agent gave when it connected, for the notification in the menu bar app.
    actor Client {
        var name: String?
        func set(_ name: String) { self.name = name }
    }

    static func run() async -> Int32 {
        let agentTools = AgentTools(loadSettings: { Wiring.settings().load() }, reader: SystemNetwork(),
                                    changer: Wiring.changer())
        let client = Client()
        let server = Server(name: Agent.serverName, version: Version.current, instructions: AgentTools.instructions,
                            capabilities: .init(tools: .init(listChanged: false)))

        await server.withMethodHandler(ListTools.self) { _ in ListTools.Result(tools: tools) }
        await server.withMethodHandler(CallTool.self) { params in
            guard [AgentTools.statusTool, AgentTools.changeTool].contains(params.name) else {
                throw MCPError.invalidParams("Unknown tool: \(params.name)")
            }
            let clientName = await client.name
            // A change blocks for seconds, so it runs away from the server's own executor
            let outcome = await Task.detached {
                Result {
                    params.name == AgentTools.statusTool ? try agentTools.status() : try agentTools.change(clientName: clientName)
                }
            }.value
            switch outcome {
            case .success(let json):
                return CallTool.Result(content: [.text(text: json, annotations: nil, _meta: nil)])
            case .failure(let error):
                let message = (error as? IpBumpError)?.message ?? error.localizedDescription
                return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
            }
        }

        do {
            try await server.start(transport: StdioTransport()) { info, _ in await client.set(info.name) }
            await server.waitUntilCompleted()   // returns when the agent closes stdin
            return 0
        } catch {
            FileHandle.standardError.write(Data("IpBump mcp: \(error)\n".utf8))
            return 1
        }
    }
}
