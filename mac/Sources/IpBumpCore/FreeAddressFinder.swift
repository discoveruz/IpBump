/// Finds an IPv4 address on the local network that no device is using.
/// The helper asks with ARP, eight addresses at a time: a device can't hold an address without answering ARP.
public struct FreeAddressFinder: Sendable {
    public static let batchSize = 8
    public static let maxProbes = 512

    let helper: PrivilegedHelper

    public init(helper: PrivilegedHelper) { self.helper = helper }

    /// The addresses to try, in order: forward from the one after `current`, wrapping around at the end of the range.
    /// With no address at all (DHCP gave none, say), the search begins at the one saved in the settings.
    /// The current address, the router and the DNS servers are left out.
    public static func candidates(_ s: UserSettings, current: String, skip: [String]) throws -> [String] {
        let range = try SearchRange.of(ip: s.ip, mask: s.mask, from: s.rangeStart, to: s.rangeEnd)
        let avoid = Set(([current, s.router, s.dns1, s.dns2] + skip).compactMap(IPv4.number))
        let first = UInt64(range.lowerBound), count = UInt64(range.upperBound) - first + 1

        let start: UInt64
        if let cur = IPv4.number(current) {
            start = cur >= range.lowerBound && cur < range.upperBound ? UInt64(cur) + 1 : first
        } else if let saved = IPv4.number(s.ip), range.contains(saved) {
            start = UInt64(saved)
        } else {
            start = first
        }

        return (0..<min(count, UInt64(maxProbes)))
            .map { UInt32(first + (start - first + $0) % count) }
            .filter { !avoid.contains($0) }
            .map(IPv4.string)
    }

    /// The first address nobody answered for, or nil if every one did.
    public func findFree(_ s: UserSettings, current: String, skip: [String]) throws -> String? {
        let all = try Self.candidates(s, current: current, skip: skip)
        for start in stride(from: 0, to: all.count, by: Self.batchSize) {
            let batch = Array(all[start..<min(start + Self.batchSize, all.count)])
            let answered = try helper.probe(service: s.service, addresses: batch)
            if let free = batch.first(where: { !answered.contains($0) }) { return free }
        }
        return nil
    }
}
