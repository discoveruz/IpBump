/// Reads what the Mac's network services are using right now. Needs no special rights.
public protocol NetworkReader: Sendable {
    /// The services IpBump can manage, in the order System Settings lists them.
    func serviceNames() -> [String]
    /// The service the Mac is online with; pre-fills the first run.
    func defaultService() -> String
    /// nil: there is no such service.
    func current(service: String) -> ServiceState?
}

/// The root helper: the only part of IpBump that sends ARP probes or changes network settings.
public protocol PrivilegedHelper: Sendable {
    func apply(_ config: IpConfig) throws
    /// The addresses another device answered for.
    func probe(service: String, addresses: [String]) throws -> Set<String>
}

/// One change at a time, whoever asked for it.
public protocol ChangeLock: Sendable {
    func withLock<T>(_ body: () throws -> T) throws -> T
}
