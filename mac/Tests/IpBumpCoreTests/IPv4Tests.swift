import Testing
@testable import IpBumpCore

struct IPv4Tests {
    @Test func validAddressesAreFourDecimalParts() {
        #expect(IPv4.isValid("192.168.1.1"))
        #expect(IPv4.isValid("0.0.0.0"))
        for bad in ["", "192.168.1", "192.168.1.256", "192.168.01.1", " 192.168.1.1", "1.2.3.4.5", "a.b.c.d", "1..2.3"] {
            #expect(!IPv4.isValid(bad), "\(bad)")
        }
    }

    @Test func masksAreOnesThenZeros() {
        #expect(IPv4.isMask("255.255.255.0"))
        #expect(IPv4.isMask("255.255.255.255"))
        #expect(!IPv4.isMask("255.0.255.0"))
        #expect(!IPv4.isMask("0.0.0.0"))
        #expect(!IPv4.isMask("abc"))
    }

    @Test func numbersRoundTrip() {
        #expect(IPv4.number("192.168.44.189") == 0xC0A8_2CBD)
        #expect(IPv4.string(0xC0A8_2CBD) == "192.168.44.189")
        #expect(IPv4.number("1.2.3") == nil)
    }

    @Test func sameNetwork() {
        #expect(IPv4.sameNetwork("192.168.1.10", "192.168.1.200", mask: "255.255.255.0"))
        #expect(!IPv4.sameNetwork("192.168.1.10", "192.168.2.10", mask: "255.255.255.0"))
        #expect(!IPv4.sameNetwork("", "192.168.1.10", mask: "255.255.255.0"))
    }
}
