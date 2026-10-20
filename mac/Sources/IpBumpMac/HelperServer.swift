import Foundation
import IpBumpCore
import os

/// What the helper does with a request once it has been checked: BPF and networksetup in the real helper.
public protocol HelperBackend: Sendable {
    func serviceNames() -> [String]
    func apply(_ config: IpConfig) throws
    func probe(service: String, addresses: [String]) throws -> Set<String>
}

/// The helper's end of the socket. One request at a time; whoever comes next waits in the queue.
public final class HelperServer: @unchecked Sendable {
    let socketPath: String
    let backend: HelperBackend
    let readTimeout: Duration
    private var listener: Int32 = -1
    private let state = NSLock()
    private var stopped = false
    private let log = Logger(subsystem: "io.github.discoveruz.ipbump", category: "helper")
    /// accept(2); tests make it fail.
    var acceptClient: @Sendable (Int32) -> Int32 = { accept($0, nil, nil) }

    public init(socketPath: String, backend: HelperBackend, readTimeout: Duration = .seconds(5)) {
        self.socketPath = socketPath
        self.backend = backend
        self.readTimeout = readTimeout
    }

    public func start() throws {
        let fd = try LineSocket.listen(path: socketPath)
        listener = fd
        Thread.detachNewThread { [self] in
            while true {
                let client = acceptClient(fd)
                if isStopped {
                    if client >= 0 { close(client) }
                    return
                }
                guard client >= 0 else {
                    // A client that gave up before it was accepted, or a moment without file descriptors: keep
                    // listening. launchd restarts a helper that exits, never one that runs on without listening
                    if errno != EINTR { Thread.sleep(forTimeInterval: 0.1) }
                    continue
                }
                LineSocket.noSigPipe(client)
                LineSocket.sendTimeout(client, readTimeout)
                serve(client)
                close(client)
            }
        }
    }

    public func stop() {
        guard listener >= 0 else { return }
        state.lock()
        stopped = true
        state.unlock()
        shutdown(listener, SHUT_RDWR)   // wakes the waiting accept()
        close(listener)
        listener = -1
    }

    var isStopped: Bool {
        state.lock(); defer { state.unlock() }
        return stopped
    }

    func serve(_ client: Int32) {
        var uid: uid_t = 0, gid: gid_t = 0
        getpeereid(client, &uid, &gid)

        let response: HelperResponse
        do {
            let line = try LineSocket.readLine(client, timeout: readTimeout, maxBytes: HelperInfo.maxLineBytes)
            response = handle(line)
        } catch LineSocket.ReadFailure.tooLong {
            response = HelperResponse(ok: false, error: "Request too long.")
        } catch {
            // A silent or stuck client can't hold up everyone else; there is nobody to answer
            log.warning("uid \(uid, privacy: .public): no request (\(String(describing: error), privacy: .public))")
            return
        }
        if !response.ok { log.warning("uid \(uid, privacy: .public): \(response.error, privacy: .public)") }
        if let json = try? JSONEncoder().encode(response) {
            _ = LineSocket.writeLine(client, String(decoding: json, as: UTF8.self))
        }
    }

    func handle(_ line: String) -> HelperResponse {
        guard let request = try? JSONDecoder().decode(HelperRequest.self, from: Data(line.utf8)) else {
            return HelperResponse(ok: false, error: "Bad request.")
        }
        do {
            try HelperValidation.validate(request, services: backend.serviceNames())
            switch request {
            case .apply(let config):
                try backend.apply(config)
                return HelperResponse(ok: true)
            case .probe(let service, let addresses):
                return HelperResponse(ok: true, answered: try backend.probe(service: service, addresses: addresses).sorted())
            }
        } catch {
            return HelperResponse(ok: false, error: (error as? IpBumpError)?.message ?? error.localizedDescription)
        }
    }
}
