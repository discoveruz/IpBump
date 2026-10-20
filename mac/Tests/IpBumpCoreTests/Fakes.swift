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
