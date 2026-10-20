/// Facts the root helper and the processes that talk to it share.
public enum HelperInfo {
    public static let label = "io.github.discoveruz.ipbump.helper"
    /// One request per connection: a line of JSON in, a line of JSON out.
    public static let socketPath = "/var/run/io.github.discoveruz.ipbump.v1.sock"
    public static let maxLineBytes = 65_536
    public static let maxProbeAddresses = 64
}

public enum HelperRequest: Codable, Equatable, Sendable {
    case apply(IpConfig)
    /// Which of these addresses does another device answer for?
    case probe(service: String, addresses: [String])

    enum CodingKeys: String, CodingKey { case op, config, service, addresses }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .op) {
        case "apply":
            self = .apply(try c.decode(IpConfig.self, forKey: .config))
        case "probe":
            self = .probe(service: try c.decode(String.self, forKey: .service),
                          addresses: try c.decode([String].self, forKey: .addresses))
        case let op:
            throw DecodingError.dataCorruptedError(forKey: .op, in: c, debugDescription: "Unknown op \"\(op)\".")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .apply(let config):
            try c.encode("apply", forKey: .op)
            try c.encode(config, forKey: .config)
        case .probe(let service, let addresses):
            try c.encode("probe", forKey: .op)
            try c.encode(service, forKey: .service)
            try c.encode(addresses, forKey: .addresses)
        }
    }
}

public struct HelperResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var error: String
    /// For a probe: the addresses another device answered for.
    public var answered: [String]

    public init(ok: Bool, error: String = "", answered: [String] = []) {
        self.ok = ok; self.error = error; self.answered = answered
    }
}

/// The helper runs as root and anyone signed in to this Mac may talk to it,
/// so every request is checked before anything privileged happens.
public enum HelperValidation {
    public static func validate(_ request: HelperRequest, services: [String]) throws {
        switch request {
        case .apply(let c):
            try check(service: c.service, services)
            // DNS servers go to networksetup for DHCP too, when they were set by hand
            for dns in [c.dns1, c.dns2] where !dns.isEmpty && !IPv4.isValid(dns) {
                throw IpBumpError("Invalid address \"\(dns)\".")
            }
            if c.dhcp { return }
            guard IPv4.isValid(c.ip) else { throw IpBumpError("Invalid IP address \"\(c.ip)\".") }
            guard IPv4.isMask(c.mask) else { throw IpBumpError("Invalid subnet mask \"\(c.mask)\".") }
            guard IPv4.isValid(c.router) else { throw IpBumpError("Invalid router address \"\(c.router)\".") }
        case .probe(let service, let addresses):
            try check(service: service, services)
            guard !addresses.isEmpty else { throw IpBumpError("No addresses to probe.") }
            guard addresses.count <= HelperInfo.maxProbeAddresses else {
                throw IpBumpError("Too many addresses in one request (\(HelperInfo.maxProbeAddresses) at most).")
            }
            for address in addresses where !IPv4.isValid(address) { throw IpBumpError("Invalid address \"\(address)\".") }
        }
    }

    static func check(service: String, _ services: [String]) throws {
        // It must be a real service: this also keeps arbitrary text away from networksetup
        guard services.contains(service) else { throw IpBumpError("Unknown network service \"\(service)\".") }
        // networksetup would read such a name as one of its options
        guard !service.hasPrefix("-") else {
            throw IpBumpError("IpBump can't manage a network service whose name starts with \"-\". Rename it in System Settings.")
        }
    }
}
