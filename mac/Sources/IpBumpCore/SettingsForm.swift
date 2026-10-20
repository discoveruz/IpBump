import Foundation

/// The Settings window's fields and the rules for what Save accepts, modelled on the TCP/IP settings in System Settings.
public struct SettingsForm: Equatable, Sendable {
    public var service: String
    public var ip: String
    public var mask: String
    public var router: String
    public var dns1: String
    public var dns2: String
    public var rangeStart: String
    public var rangeEnd: String
    public var allowAgents: Bool
    public var showFullAddress: Bool
    public var showNotifications: Bool

    public enum Field: Equatable, Sendable { case service, ip, mask, router, dns1, dns2, rangeStart, rangeEnd }

    /// What is wrong, and which field to put the cursor in.
    public struct Problem: Error, Equatable, Sendable {
        public let field: Field
        public let message: String

        public init(field: Field, message: String) { self.field = field; self.message = message }
    }

    public init(service: String = "", ip: String = "", mask: String = "", router: String = "", dns1: String = "",
                dns2: String = "", rangeStart: String = "", rangeEnd: String = "", allowAgents: Bool = false,
                showFullAddress: Bool = true, showNotifications: Bool = true) {
        self.service = service; self.ip = ip; self.mask = mask; self.router = router; self.dns1 = dns1; self.dns2 = dns2
        self.rangeStart = rangeStart; self.rangeEnd = rangeEnd; self.allowAgents = allowAgents
        self.showFullAddress = showFullAddress; self.showNotifications = showNotifications
    }

    public static func initial(saved: UserSettings, reader: NetworkReader) -> SettingsForm {
        var form = SettingsForm(service: saved.service, ip: saved.ip, mask: saved.mask, router: saved.router,
                                dns1: saved.dns1, dns2: saved.dns2, rangeStart: saved.rangeStart, rangeEnd: saved.rangeEnd,
                                allowAgents: saved.allowAgents, showFullAddress: saved.showFullAddress,
                                showNotifications: saved.showNotifications)
        if saved.service.isEmpty {
            // First run: the service the Mac is online with, and what it uses now
            form.service = reader.defaultService()
            _ = form.fill(from: reader)
        } else if let live = reader.current(service: saved.service), IPv4.sameNetwork(live.ip, saved.ip, mask: saved.mask) {
            // IpBump moves the address around, so show the one in use rather than the one saved
            form.ip = live.ip
        }
        return form
    }

    /// "Use the service's current values". False when there is no such service.
    public mutating func fill(from reader: NetworkReader) -> Bool {
        guard let now = reader.current(service: service) else { return false }
        ip = now.ip; mask = now.mask; router = now.router; dns1 = now.dns1; dns2 = now.dns2
        return true
    }

    /// The empty From and To boxes show what "the whole network" means for the address and mask above them.
    public var rangePlaceholders: (from: String, to: String) {
        guard let r = try? SearchRange.of(ip: Self.trim(ip), mask: Self.trim(mask)) else { return ("", "") }
        return (IPv4.string(r.lowerBound), IPv4.string(r.upperBound))
    }

    public func validated() throws -> UserSettings {
        guard !service.isEmpty else { throw Problem(field: .service, message: "Pick a network service.") }
        let ip = Self.trim(ip), mask = Self.trim(mask), router = Self.trim(router)
        let dns1 = Self.trim(dns1), dns2 = Self.trim(dns2), from = Self.trim(rangeStart), to = Self.trim(rangeEnd)

        try Self.address(ip, .ip, whenEmpty: "Enter an IP address.")
        if mask.isEmpty { throw Problem(field: .mask, message: "Enter a subnet mask, such as 255.255.255.0.") }
        if !IPv4.isMask(mask) { throw Problem(field: .mask, message: "\"\(mask)\" is not a valid subnet mask.") }
        try Self.address(router, .router, whenEmpty: "Enter the router address.")
        for (value, field) in [(dns1, Field.dns1), (dns2, .dns2), (from, .rangeStart), (to, .rangeEnd)] {
            try Self.address(value, field, whenEmpty: nil)
        }

        do { _ = try SearchRange.of(ip: ip, mask: mask) }   // the address and mask on their own
        catch let e as IpBumpError { throw Problem(field: .mask, message: e.message) }
        do { _ = try SearchRange.of(ip: ip, mask: mask, from: from, to: to) }   // then the search range inside that network
        catch let e as IpBumpError { throw Problem(field: .rangeStart, message: e.message) }

        return UserSettings(service: service, ip: ip, mask: mask, router: router, dns1: dns1, dns2: dns2,
                            rangeStart: from, rangeEnd: to, allowAgents: allowAgents,
                            showNotifications: showNotifications, showFullAddress: showFullAddress)
    }

    /// Like System Settings, Save also applies, but only when the service isn't already set this way.
    public static func needsApply(_ s: UserSettings, live: ServiceState?) -> Bool {
        guard let live else { return true }
        return !(live.ip == s.ip && live.mask == s.mask && live.router == s.router && live.dns1 == s.dns1 && live.dns2 == s.dns2)
    }

    public static func statusText(_ live: ServiceState?) -> String {
        guard let live else { return "" }
        if !live.up { return "Not connected" }
        return live.dhcp ? "Connected  ·  address assigned automatically (DHCP)" : "Connected  ·  manual address"
    }

    static func address(_ value: String, _ field: Field, whenEmpty: String?) throws {
        if value.isEmpty {
            if let whenEmpty { throw Problem(field: field, message: whenEmpty) }
            return
        }
        if !IPv4.isValid(value) { throw Problem(field: field, message: "\"\(value)\" is not a valid IPv4 address.") }
    }

    static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
}
