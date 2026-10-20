import Foundation
import IpBumpCore
import SystemConfiguration

/// Reads the Mac's network services from SystemConfiguration, the store System Settings itself uses.
/// Reading needs no special rights.
public struct SystemNetwork: NetworkReader {
    struct Service {
        let id: String
        let name: String
        let bsd: String
    }

    public init() {}

    public func serviceNames() -> [String] { services().map(\.name) }

    /// The service the Mac is online with, else the first one System Settings lists.
    public func defaultService() -> String {
        let all = services()
        let primary = value(store(), "State:/Network/Global/IPv4")?["PrimaryService"] as? String
        return all.first { $0.id == primary }?.name ?? all.first?.name ?? ""
    }

    public func current(service name: String) -> ServiceState? {
        guard let service = services().first(where: { $0.name == name }) else { return nil }
        let store = store()
        return Self.state(service: service.name, interface: service.bsd,
                          setupIPv4: value(store, "Setup:/Network/Service/\(service.id)/IPv4"),
                          stateIPv4: value(store, "State:/Network/Service/\(service.id)/IPv4"),
                          dns: value(store, "State:/Network/Service/\(service.id)/DNS"),
                          setupDNS: value(store, "Setup:/Network/Service/\(service.id)/DNS"),
                          linkActive: value(store, "State:/Network/Interface/\(service.bsd)/Link")?["Active"] as? Bool)
    }

    /// The BSD name of the service's interface, such as en0.
    public func interfaceName(service name: String) -> String? { services().first { $0.name == name }?.bsd }

    /// Ethernet-like services, where ARP works. VPNs and modems are left out.
    public static func isSupported(interfaceType: String) -> Bool {
        // The values of kSCNetworkInterfaceType…; the SDK has no public constant for bridges
        ["Ethernet", "IEEE80211", "Bridge", "Bond", "VLAN"].contains(interfaceType)
    }

    /// What the dynamic store says about one service.
    public static func state(service: String, interface: String, setupIPv4: [String: Any]?, stateIPv4: [String: Any]?,
                             dns: [String: Any]?, setupDNS: [String: Any]? = nil, linkActive: Bool?) -> ServiceState {
        let addresses = stateIPv4?["Addresses"] as? [String] ?? []
        let masks = stateIPv4?["SubnetMasks"] as? [String] ?? []
        // 169.254.x.x is what macOS gives itself when it has no real address
        let index = addresses.firstIndex { IPv4.isValid($0) && !$0.hasPrefix("169.254.") }
        // DNS servers typed into the service's setup replace DHCP's; State holds only DHCP's, and nothing for a manual service
        let typed = setupDNS?["ServerAddresses"] as? [String] ?? []
        let servers = (typed.isEmpty ? dns?["ServerAddresses"] as? [String] ?? [] : typed).filter(IPv4.isValid)
        return ServiceState(
            service: service, interface: interface,
            up: linkActive ?? (stateIPv4 != nil),   // a bridge, say, has no link state of its own
            dhcp: setupIPv4?["ConfigMethod"] as? String == "DHCP",
            ip: index.map { addresses[$0] } ?? "",
            mask: index.flatMap { masks.indices.contains($0) ? masks[$0] : nil } ?? "",
            router: stateIPv4?["Router"] as? String ?? "",
            dns1: servers.first ?? "", dns2: servers.dropFirst().first ?? "",
            dnsManual: !typed.isEmpty)
    }

    /// The enabled services in the current location, in the order System Settings shows them.
    func services() -> [Service] {
        guard let prefs = SCPreferencesCreate(nil, "IpBump" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(prefs),
              let all = SCNetworkSetCopyServices(set) as? [SCNetworkService] else { return [] }
        let order = SCNetworkSetGetServiceOrder(set) as? [String] ?? []
        return all.compactMap { service -> Service? in
            guard SCNetworkServiceGetEnabled(service),
                  let id = SCNetworkServiceGetServiceID(service) as String?,
                  let name = SCNetworkServiceGetName(service) as String?,
                  let interface = SCNetworkServiceGetInterface(service),
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String?, Self.isSupported(interfaceType: type),
                  let bsd = SCNetworkInterfaceGetBSDName(interface) as String?
            else { return nil }
            return Service(id: id, name: name, bsd: bsd)
        }
        .sorted { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
    }

    func store() -> SCDynamicStore? { SCDynamicStoreCreate(nil, "IpBump" as CFString, nil, nil) }

    func value(_ store: SCDynamicStore?, _ key: String) -> [String: Any]? {
        SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
    }
}
