import Testing
@testable import IpBumpCore

struct NetworkSetupTests {
    let c = IpConfig(service: "Wi-Fi", ip: "192.168.1.20", mask: "255.255.255.0", router: "192.168.1.1", dns1: "8.8.8.8", dns2: "1.1.1.1")

    @Test func manualWithTwoDnsServers() {
        #expect(NetworkSetup.commands(for: c, currentlyDhcp: true) == [
            ["-setmanual", "Wi-Fi", "192.168.1.20", "255.255.255.0", "192.168.1.1"],
            ["-setdnsservers", "Wi-Fi", "8.8.8.8", "1.1.1.1"],
        ])
    }

    @Test func manualWithoutDnsClearsIt() {
        var n = c
        n.dns1 = ""
        n.dns2 = ""
        #expect(NetworkSetup.commands(for: n, currentlyDhcp: false).last == ["-setdnsservers", "Wi-Fi", "Empty"])
    }

    @Test func dhcpOnlyWhenNotAlready() {
        #expect(NetworkSetup.commands(for: IpConfig(service: "Wi-Fi", dhcp: true), currentlyDhcp: false)
            == [["-setdhcp", "Wi-Fi"], ["-setdnsservers", "Wi-Fi", "Empty"]])
        #expect(NetworkSetup.commands(for: IpConfig(service: "Wi-Fi", dhcp: true), currentlyDhcp: true)
            == [["-setdnsservers", "Wi-Fi", "Empty"]])
    }

    /// Review fix: putting back a DHCP service whose DNS servers were set by hand keeps those servers.
    @Test func dhcpKeepsDnsSetByHand() {
        #expect(NetworkSetup.commands(for: IpConfig(service: "Wi-Fi", dns1: "8.8.8.8", dns2: "1.1.1.1", dhcp: true), currentlyDhcp: false)
            == [["-setdhcp", "Wi-Fi"], ["-setdnsservers", "Wi-Fi", "8.8.8.8", "1.1.1.1"]])
    }

    @Test func recognisesFailures() {
        #expect(NetworkSetup.failure(exitCode: 0, output: "") == nil)
        #expect(NetworkSetup.failure(exitCode: 0, output: "** Error: The parameters were not valid.\n") == "** Error: The parameters were not valid.")
        #expect(NetworkSetup.failure(exitCode: 0, output: "Wi-Fii is not a recognized network service.\n") == "Wi-Fii is not a recognized network service.")
        #expect(NetworkSetup.failure(exitCode: 4, output: "") == "networksetup failed (4)")
        // What networksetup on macOS 26 prints for a service it doesn't know, with exit code 4
        #expect(NetworkSetup.failure(exitCode: 4, output: "No Such Service is not a recognized network service.\n** Error: The parameters were not valid.\n")
            == "No Such Service is not a recognized network service.\n** Error: The parameters were not valid.")
    }
}
