import Foundation

public protocol IpChanging: Sendable {
    func toFreeAddress(_ s: UserSettings, source: String, progress: (@Sendable (String) -> Void)?) throws -> ChangeResult
    func applySettings(_ s: UserSettings) throws
    func useDhcp(_ s: UserSettings) throws
}

/// The IP changes themselves, shared by the menu bar app, the Settings window, the MCP server and the hook.
public struct IpChanger: IpChanging {
    /// The source of changes made from the menu bar app; the app doesn't report its own changes.
    public static let traySource = "tray"

    public static let threadSleep: @Sendable (Duration) -> Void = { duration in
        let (seconds, attoseconds) = duration.components
        Thread.sleep(forTimeInterval: Double(seconds) + Double(attoseconds) / 1e18)
    }

    let reader: NetworkReader
    let helper: PrivilegedHelper
    let lock: ChangeLock
    let lastChange: LastChangeStore
    let verifyPolls: Int
    let pollInterval: Duration
    let sleep: @Sendable (Duration) -> Void

    public init(reader: NetworkReader, helper: PrivilegedHelper, lock: ChangeLock, lastChange: LastChangeStore,
                verifyPolls: Int = 50, pollInterval: Duration = .milliseconds(200),
                sleep: @escaping @Sendable (Duration) -> Void = IpChanger.threadSleep) {
        self.reader = reader; self.helper = helper; self.lock = lock; self.lastChange = lastChange
        self.verifyPolls = verifyPolls; self.pollInterval = pollInterval; self.sleep = sleep
    }

    /// Finds an address nobody is using and switches to it.
    public func toFreeAddress(_ s: UserSettings, source: String,
                              progress: (@Sendable (String) -> Void)? = nil) throws -> ChangeResult {
        try lock.withLock {
            let before = try current(s)
            guard before.up else { throw IpBumpError("\"\(s.service)\" is not connected.") }

            let finder = FreeAddressFinder(helper: helper)
            var taken: [String] = []
            var replaced = false   // once the old address is gone, any failure must put it back
            do {
                for _ in 0..<3 {
                    progress?("Looking for a free address…")
                    guard let ip = try finder.findFree(s, current: before.ip, skip: taken) else {
                        throw IpBumpError("Every address in the search range is in use.")
                    }

                    progress?("Applying \(ip)…")
                    try helper.apply(s.config(ip: ip))
                    replaced = true
                    let check = waitUntilUsable(service: s.service, ip: ip)
                    if check == .usable {
                        lastChange.save(LastChange(at: Date(), from: before.ip, to: ip, source: source))
                        return ChangeResult(service: s.service, oldIp: before.ip, newIp: ip)
                    }
                    if check == .timedOut { break }
                    taken.append(ip)   // a device that stayed silent during the search claimed it; try the next one
                }
                throw IpBumpError(taken.isEmpty
                    ? "macOS did not start using the new address. The previous address was put back."
                    : "Other devices claimed \(taken.joined(separator: ", ")). The previous address was put back.")
            } catch {
                if replaced { restore(before) }
                throw error
            }
        }
    }

    /// Applies exactly what is in the settings (the Save button).
    public func applySettings(_ s: UserSettings) throws {
        try lock.withLock {
            let before = try current(s)
            try helper.apply(s.config(ip: s.ip))
            if before.up && waitUntilUsable(service: s.service, ip: s.ip) == .duplicate {
                restore(before)
                throw IpBumpError("Another device is already using \(s.ip). The previous address was put back.")
            }
            lastChange.save(LastChange(at: Date(), from: before.ip, to: s.ip, source: Self.traySource))
        }
    }

    /// Hands the service back to the network's DHCP server.
    public func useDhcp(_ s: UserSettings) throws {
        try lock.withLock {
            _ = try current(s)
            try helper.apply(IpConfig(service: s.service, dhcp: true))
        }
    }

    /// macOS takes a moment to start using a new address. Waits for that, then asks once more whether another
    /// device answers for it: one that was asleep during the search, say.
    public func waitUntilUsable(service: String, ip: String) -> AddressCheck {
        for poll in 0..<verifyPolls {
            if reader.current(service: service)?.ip == ip {
                // A failed double-check doesn't undo an address that is already working
                let answered = (try? helper.probe(service: service, addresses: [ip])) ?? []
                return answered.contains(ip) ? .duplicate : .usable
            }
            if poll < verifyPolls - 1 { sleep(pollInterval) }
        }
        return .timedOut
    }

    func current(_ s: UserSettings) throws -> ServiceState {
        guard !s.service.isEmpty else {
            throw IpBumpError("IpBump isn't set up yet. Open its settings and pick a network service.")
        }
        guard let state = reader.current(service: s.service) else {
            throw IpBumpError("Network service \"\(s.service)\" was not found.")
        }
        return state
    }

    func restore(_ before: ServiceState) {
        guard before.dhcp || IPv4.isValid(before.ip) else { return }   // there was nothing usable to go back to
        try? helper.apply(before.config)   // the caller reports the original problem
    }
}
