import Foundation
import IpBumpCore

/// Asks the root helper over its socket. The menu bar app, the MCP server and the hook have no right to change
/// network settings or to send probes themselves.
public struct SocketHelper: PrivilegedHelper {
    let socketPath: String
    let connectTimeout: Duration
    let responseTimeout: Duration

    public init(socketPath: String = Paths.helperSocket, connectTimeout: Duration = .seconds(3),
                responseTimeout: Duration = .seconds(30)) {
        self.socketPath = socketPath
        self.connectTimeout = connectTimeout
        self.responseTimeout = responseTimeout
    }

    public func apply(_ config: IpConfig) throws {
        _ = try send(.apply(config))
    }

    public func probe(service: String, addresses: [String]) throws -> Set<String> {
        Set(try send(.probe(service: service, addresses: addresses)).answered)
    }

    func send(_ request: HelperRequest) throws -> HelperResponse {
        guard let fd = LineSocket.connect(path: socketPath, timeout: connectTimeout) else {
            throw IpBumpError("The IpBump helper isn't running. Reinstall IpBump.")
        }
        defer { close(fd) }
        let line = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        guard LineSocket.writeLine(fd, line) else { throw IpBumpError("No answer from the IpBump helper.") }

        let answer: String
        do {
            answer = try LineSocket.readLine(fd, timeout: responseTimeout, maxBytes: HelperInfo.maxLineBytes)
        } catch LineSocket.ReadFailure.timedOut {
            throw IpBumpError("The IpBump helper did not answer.")
        } catch {
            throw IpBumpError("No answer from the IpBump helper.")
        }
        guard let response = try? JSONDecoder().decode(HelperResponse.self, from: Data(answer.utf8)) else {
            throw IpBumpError("No answer from the IpBump helper.")
        }
        guard response.ok else { throw IpBumpError(response.error) }
        return response
    }
}
