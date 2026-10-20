import Foundation
@testable import IpBumpCore

/// The network and the helper in one: applying settings changes what the reader reports, as on a real Mac.
final class FakeNetwork: NetworkReader, PrivilegedHelper, @unchecked Sendable {
    private let lock = NSLock()
    var state: ServiceState?
    var services: [String] = []
    /// Answer every probe.
    var taken: Set<String> = []
    /// Silent until the Mac itself uses the address, then they answer: devices that wake up and claim it late.
    var claimsWhenTaken: Set<String> = []
    /// false: macOS never starts using an applied address.
    var startsUsing = true
    var applyError: String?
    var probeError: String?
    private(set) var applied: [IpConfig] = []
    private(set) var probes: [[String]] = []

    init(state: ServiceState? = nil, services: [String] = []) {
        self.state = state
        self.services = services
    }

    func serviceNames() -> [String] { services }

    func defaultService() -> String { services.first ?? "" }

    func current(service: String) -> ServiceState? {
        lock.lock(); defer { lock.unlock() }
        return state?.service == service ? state : nil
    }

    func apply(_ config: IpConfig) throws {
        lock.lock(); defer { lock.unlock() }
        if let applyError { throw IpBumpError(applyError) }
        applied.append(config)
        guard startsUsing, var s = state else { return }
        s.dhcp = config.dhcp
        s.ip = config.ip; s.mask = config.mask; s.router = config.router; s.dns1 = config.dns1; s.dns2 = config.dns2
        state = s
    }

    func probe(service: String, addresses: [String]) throws -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        if let probeError { throw IpBumpError(probeError) }
        probes.append(addresses)
        let mine = state?.ip
        return Set(addresses.filter { taken.contains($0) || (claimsWhenTaken.contains($0) && $0 == mine) })
    }
}

struct PassLock: ChangeLock {
    func withLock<T>(_ body: () throws -> T) throws -> T { try body() }
}

struct BusyLock: ChangeLock {
    func withLock<T>(_ body: () throws -> T) throws -> T { throw IpBumpError.changeRunning }
}

/// A link that plays back scripted frames: each receive call returns the next round.
final class FakeLink: LinkLayer, @unchecked Sendable {
    private var rounds: [[[UInt8]]]
    private(set) var sent: [[UInt8]] = []

    init(rounds: [[[UInt8]]]) { self.rounds = rounds }

    func send(_ frame: [UInt8]) throws { sent.append(frame) }

    func receive(for duration: Duration) throws -> [[UInt8]] {
        rounds.isEmpty ? [] : rounds.removeFirst()
    }

    /// The target address of each request sent, read straight from bytes 38–41 of the frame.
    var sentTargets: [UInt32] {
        sent.map { f in UInt32(f[38]) << 24 | UInt32(f[39]) << 16 | UInt32(f[40]) << 8 | UInt32(f[41]) }
    }
}

/// Stands in for IpChanger where only the outcome of a change matters.
final class FakeChanger: IpChanging, @unchecked Sendable {
    private let lock = NSLock()
    var result = ChangeResult(service: "Wi-Fi", oldIp: "192.168.1.10", newIp: "192.168.1.11")
    var error: IpBumpError?
    /// When set, a change waits for a signal before it finishes.
    var gate: DispatchSemaphore?
    private var recorded: [String] = []

    /// The source of every toFreeAddress call, recorded as the call starts.
    var sources: [String] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func toFreeAddress(_ s: UserSettings, source: String, progress: (@Sendable (String) -> Void)?) throws -> ChangeResult {
        lock.lock(); recorded.append(source); lock.unlock()
        gate?.wait()
        if let error { throw error }
        return result
    }

    func applySettings(_ s: UserSettings) throws {
        if let error { throw error }
    }

    func useDhcp(_ s: UserSettings) throws {
        gate?.wait()
        if let error { throw error }
    }
}

struct Post: Equatable {
    let title: String
    let body: String
    let isError: Bool

    init(_ title: String, _ body: String, _ isError: Bool) { self.title = title; self.body = body; self.isError = isError }
}

final class FakeNotifier: Notifier, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Post] = []

    var posts: [Post] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func post(title: String, body: String, isError: Bool) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(Post(title, body, isError))
    }
}
