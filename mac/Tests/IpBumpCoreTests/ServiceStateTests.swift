import Testing
@testable import IpBumpCore

/// What putting a service back the way it was means.
struct ServiceStateTests {
    @Test func dhcpGoesBackToTheNetworksDns() {
        let state = ServiceState(service: "Wi-Fi", up: true, dhcp: true, ip: "192.168.1.10", dns1: "192.168.1.1")
        #expect(state.config.dhcp && state.config.dns1 == "")
    }

    /// Review fix: DNS servers set by hand on a DHCP service stay.
    @Test func dhcpKeepsDnsSetByHand() {
        let state = ServiceState(service: "Wi-Fi", up: true, dhcp: true, ip: "192.168.1.10", dns1: "8.8.8.8", dns2: "1.1.1.1",
                                 dnsManual: true)
        #expect(state.config.dns1 == "8.8.8.8" && state.config.dns2 == "1.1.1.1")
    }

    @Test func manualKeepsEverything() {
        let state = ServiceState(service: "Wi-Fi", up: true, dhcp: false, ip: "192.168.1.10", mask: "255.255.255.0",
                                 router: "192.168.1.1", dns1: "8.8.8.8")
        #expect(state.config == IpConfig(service: "Wi-Fi", ip: "192.168.1.10", mask: "255.255.255.0", router: "192.168.1.1", dns1: "8.8.8.8"))
    }
}
