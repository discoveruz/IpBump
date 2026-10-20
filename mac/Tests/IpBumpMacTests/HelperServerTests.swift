import Foundation
import Testing
import IpBumpCore
@testable import IpBumpMac

final class HelperServerTests {
    let path = temporarySocketPath()
    let backend = FakeBackend()
    let server: HelperServer
    var client: SocketHelper { SocketHelper(socketPath: path) }

    init() throws {
        server = HelperServer(socketPath: path, backend: backend, readTimeout: .milliseconds(200))
        try server.start()
    }

    deinit {
        server.stop()
        unlink(path)
    }

    /// Sends bytes as they are and reads back the helper's answer.
    func rawRequest(_ text: String) throws -> HelperResponse {
        let fd = try #require(LineSocket.connect(path: path, timeout: .seconds(1)))
        defer { close(fd) }
        _ = LineSocket.writeAll(fd, Array(text.utf8))   // the helper may stop reading early; its answer still comes
        let line = try LineSocket.readLine(fd, timeout: .seconds(2), maxBytes: HelperInfo.maxLineBytes)
        return try JSONDecoder().decode(HelperResponse.self, from: Data(line.utf8))
    }

    @Test func appliesValidRequests() throws {
        let c = IpConfig(service: "Wi-Fi", ip: "192.168.1.20", mask: "255.255.255.0", router: "192.168.1.1")
        try client.apply(c)
        #expect(backend.applied == [c])
    }

    /// Review Focus 4: nothing unchecked reaches the backend, which runs as root.
    @Test func refusesInvalidRequestsBeforeTheBackend() {
        #expect(throws: IpBumpError("Unknown network service \"Wi-Fii\".")) { try client.apply(IpConfig(service: "Wi-Fii", dhcp: true)) }
        #expect(backend.applied.isEmpty)
    }

    @Test func returnsProbeAnswers() throws {
        backend.answered = ["192.168.1.11"]
        #expect(try client.probe(service: "Wi-Fi", addresses: ["192.168.1.11", "192.168.1.12"]) == ["192.168.1.11"])
    }

    @Test func passesBackendErrors() {
        backend.applyError = "boom"
        #expect(throws: IpBumpError("boom")) { try client.apply(IpConfig(service: "Wi-Fi", dhcp: true)) }
    }

    @Test func explainsAMissingHelper() {
        #expect(throws: IpBumpError("The IpBump helper isn't running. Reinstall IpBump.")) {
            try SocketHelper(socketPath: temporarySocketPath()).apply(IpConfig(service: "Wi-Fi", dhcp: true))
        }
    }

    /// Review Focus 4: an endless line or garbage gets an answer, and the helper keeps serving.
    @Test func refusesEndlessLinesAndKeepsServing() throws {
        #expect(try rawRequest(String(repeating: "x", count: 70_000)) == HelperResponse(ok: false, error: "Request too long."))
        #expect(try rawRequest("{nope}\n") == HelperResponse(ok: false, error: "Bad request."))
        try client.apply(IpConfig(service: "Wi-Fi", dhcp: true))
        #expect(backend.applied.count == 1)
    }

    @Test func dropsSilentClients() throws {
        let silent = try #require(LineSocket.connect(path: path, timeout: .seconds(1)))
        defer { close(silent) }
        try client.apply(IpConfig(service: "Wi-Fi", dhcp: true))
        #expect(backend.applied.count == 1)
    }

    @Test func everyLocalUserMayConnect() throws {
        var info = stat()
        #expect(stat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o666)
    }
}
