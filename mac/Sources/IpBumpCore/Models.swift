/// IPv4 settings for one network service: what the helper is asked to apply.
public struct IpConfig: Codable, Equatable, Sendable {
    public var service: String
    public var ip: String
    public var mask: String
    public var router: String
    public var dns1: String
    public var dns2: String
    /// True = hand the service back to DHCP; the address fields are ignored.
    public var dhcp: Bool

    public init(service: String = "", ip: String = "", mask: String = "", router: String = "",
                dns1: String = "", dns2: String = "", dhcp: Bool = false) {
        self.service = service; self.ip = ip; self.mask = mask; self.router = router
        self.dns1 = dns1; self.dns2 = dns2; self.dhcp = dhcp
    }
}

/// What a network service is using right now.
public struct ServiceState: Equatable, Sendable {
    public var service: String
    /// The BSD name of the service's interface, such as en0.
    public var interface: String
    public var up: Bool
    public var dhcp: Bool
    public var ip: String
    public var mask: String
    public var router: String
    public var dns1: String
    public var dns2: String
    /// The DNS servers were set by hand rather than handed out by DHCP.
    public var dnsManual: Bool

    public init(service: String = "", interface: String = "", up: Bool = false, dhcp: Bool = false, ip: String = "",
                mask: String = "", router: String = "", dns1: String = "", dns2: String = "", dnsManual: Bool = false) {
        self.service = service; self.interface = interface; self.up = up; self.dhcp = dhcp
        self.ip = ip; self.mask = mask; self.router = router; self.dns1 = dns1; self.dns2 = dns2; self.dnsManual = dnsManual
    }

    /// The settings that put the service back the way it is now. A DHCP service's DNS servers come from the
    /// network unless someone set them by hand, and only those are carried over.
    public var config: IpConfig {
        let keepDns = !dhcp || dnsManual
        return IpConfig(service: service, ip: ip, mask: mask, router: router,
                        dns1: keepDns ? dns1 : "", dns2: keepDns ? dns2 : "", dhcp: dhcp)
    }
}

public struct ChangeResult: Equatable, Sendable {
    public let service: String
    public let oldIp: String
    public let newIp: String

    public init(service: String, oldIp: String, newIp: String) {
        self.service = service; self.oldIp = oldIp; self.newIp = newIp
    }
}

/// How a freshly applied address turned out.
public enum AddressCheck: Equatable, Sendable {
    case usable
    /// Another device answers for it too.
    case duplicate
    /// macOS never started using it.
    case timedOut
}
