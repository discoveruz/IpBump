import Testing
import IpBumpCore
@testable import IpBumpMac

struct SystemNetworkTests {
    /// The values scutil showed for this Mac's Ethernet service.
    @Test func mapsADhcpService() {
        let state = SystemNetwork.state(
            service: "USB 10/100 LAN 2", interface: "en9", setupIPv4: ["ConfigMethod": "DHCP"],
            stateIPv4: ["Addresses": ["192.168.44.18"], "SubnetMasks": ["255.255.255.0"], "Router": "192.168.44.1"],
            dns: ["ServerAddresses": ["10.104.50.2", "10.104.50.3"]], linkActive: true)
        #expect(state == ServiceState(service: "USB 10/100 LAN 2", interface: "en9", up: true, dhcp: true, ip: "192.168.44.18",
                                      mask: "255.255.255.0", router: "192.168.44.1", dns1: "10.104.50.2", dns2: "10.104.50.3"))
    }

    @Test func skipsSelfAssignedAddresses() {
        let state = SystemNetwork.state(
            service: "Wi-Fi", interface: "en0", setupIPv4: ["ConfigMethod": "Manual"],
            stateIPv4: ["Addresses": ["169.254.10.2", "192.168.1.5"], "SubnetMasks": ["255.255.0.0", "255.255.255.0"]],
            dns: nil, linkActive: true)
        #expect(state.ip == "192.168.1.5" && state.mask == "255.255.255.0" && !state.dhcp)
    }

    @Test func noIPv4MeansDown() {
        let state = SystemNetwork.state(service: "Wi-Fi", interface: "en0", setupIPv4: nil, stateIPv4: nil, dns: nil, linkActive: false)
        #expect(!state.up && state.ip == "")
    }

    @Test func keepsOnlyIPv4DnsServers() {
        let state = SystemNetwork.state(service: "Wi-Fi", interface: "en0", setupIPv4: nil, stateIPv4: nil,
                                        dns: ["ServerAddresses": ["fe80::1", "1.1.1.1"]], linkActive: nil)
        #expect(state.dns1 == "1.1.1.1" && state.dns2 == "" && !state.up)
    }

    @Test func managesOnlyEthernetLikeServices() {
        #expect(SystemNetwork.isSupported(interfaceType: "Ethernet") && SystemNetwork.isSupported(interfaceType: "IEEE80211"))
        #expect(!SystemNetwork.isSupported(interfaceType: "PPP") && !SystemNetwork.isSupported(interfaceType: "VPN"))
        #expect(!SystemNetwork.isSupported(interfaceType: "IPSec"))
    }

    /// Read-only: the services of the Mac running the tests.
    @Test func readsThisMac() throws {
        let network = SystemNetwork()
        let primary = network.defaultService()
        try #require(primary != "")
        #expect(network.serviceNames().contains(primary))
        #expect(network.current(service: primary)?.interface.isEmpty == false)
        #expect(network.interfaceName(service: primary) == network.current(service: primary)?.interface)
        #expect(network.current(service: "No Such Service") == nil)
    }
}
