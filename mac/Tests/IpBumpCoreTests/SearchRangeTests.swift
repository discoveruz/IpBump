import Testing
@testable import IpBumpCore

struct SearchRangeTests {
    @Test func wholeSubnetWithoutNetworkAndBroadcast() throws {
        let r = try SearchRange.of(ip: "192.168.1.10", mask: "255.255.255.0")
        #expect(IPv4.string(r.lowerBound) == "192.168.1.1")
        #expect(IPv4.string(r.upperBound) == "192.168.1.254")
    }

    @Test func userRangeNarrowsIt() throws {
        let r = try SearchRange.of(ip: "192.168.1.10", mask: "255.255.255.0", from: "192.168.1.100", to: "192.168.1.200")
        #expect(IPv4.string(r.lowerBound) == "192.168.1.100")
        #expect(IPv4.string(r.upperBound) == "192.168.1.200")
    }

    @Test func explainsBadInput() {
        #expect(throws: IpBumpError("Enter the IP address and subnet mask in IpBump's settings first.")) {
            try SearchRange.of(ip: "", mask: "255.255.255.0")
        }
        #expect(throws: IpBumpError("Subnet mask 255.255.255.254 leaves no addresses to choose from.")) {
            try SearchRange.of(ip: "192.168.1.10", mask: "255.255.255.254")
        }
        #expect(throws: IpBumpError("The search range must be inside this network (192.168.1.1 to 192.168.1.254).")) {
            try SearchRange.of(ip: "192.168.1.10", mask: "255.255.255.0", from: "10.0.0.1")
        }
        #expect(throws: IpBumpError("The search range's From address comes after its To address.")) {
            try SearchRange.of(ip: "192.168.1.10", mask: "255.255.255.0", from: "192.168.1.50", to: "192.168.1.40")
        }
    }
}
