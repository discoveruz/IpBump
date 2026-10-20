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
        // The helper's own read deadline: a busy test machine needs a while to send a long request
        server = HelperServer(socketPath: path, backend: backend)
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

    /// Review fix: one failed accept() (a client that gave up first, a moment without file descriptors) must not
    /// stop the helper. launchd restarts a helper that exits, never one that keeps running without listening.
    @Test func keepsServingAfterAFailedAccept() throws {
        let otherPath = temporarySocketPath()
        let other = HelperServer(socketPath: otherPath, backend: backend, readTimeout: .milliseconds(200))
        let failures = Countdown(1)
        other.acceptClient = { fd in
            if failures.take() {
                errno = ECONNABORTED
                return -1
            }
            return accept(fd, nil, nil)
        }
        try other.start()
        defer {
            other.stop()
            unlink(otherPath)
        }
        try SocketHelper(socketPath: otherPath, responseTimeout: .seconds(2)).apply(IpConfig(service: "Wi-Fi", dhcp: true))
        #expect(backend.applied.count == 1)
    }

    /// Review fix: a helper stopped while it serves a client must not wait for another one. By then its socket's
    /// number can belong to another socket (another helper's, in tests that run side by side), whose clients it
    /// would take and hang up on.
    @Test func stopsAfterTheClientItIsServing() throws {
        let otherPath = temporarySocketPath()
        let slow = FakeBackend()
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        slow.hold = (started, release)
        let other = HelperServer(socketPath: otherPath, backend: slow)
        let accepts = Counter()
        other.acceptClient = { fd in
            accepts.add()
            return accept(fd, nil, nil)
        }
        try other.start()
        defer { unlink(otherPath) }

        let answered = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            try? SocketHelper(socketPath: otherPath).apply(IpConfig(service: "Wi-Fi", dhcp: true))
            answered.signal()
        }
        try #require(started.wait(timeout: .now() + 5) == .success)   // the helper is busy with that client
        other.stop()
        release.signal()
        try #require(answered.wait(timeout: .now() + 5) == .success)
        Thread.sleep(forTimeInterval: 0.2)   // a helper that goes on is back in accept() long before this
        #expect(slow.applied.count == 1)
        #expect(accepts.count == 1)
    }

    @Test func dropsSilentClients() throws {
        let otherPath = temporarySocketPath()
        let other = HelperServer(socketPath: otherPath, backend: backend, readTimeout: .milliseconds(200))
        try other.start()
        defer {
            other.stop()
            unlink(otherPath)
        }
        let silent = try #require(LineSocket.connect(path: otherPath, timeout: .seconds(1)))
        defer { close(silent) }
        try SocketHelper(socketPath: otherPath).apply(IpConfig(service: "Wi-Fi", dhcp: true))
        #expect(backend.applied.count == 1)
    }

    /// Review fix: every login account may ask (they are all in the staff group); service accounts such as _www
    /// or nobody, which are not, may not.
    @Test func onlyLoginAccountsMayConnect() throws {
        var info = stat()
        #expect(stat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o660)
        #expect(info.st_gid == getgrnam("staff").pointee.gr_gid)
    }
}
