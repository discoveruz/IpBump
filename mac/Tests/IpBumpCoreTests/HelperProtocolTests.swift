import Foundation
import Testing
@testable import IpBumpCore

struct HelperProtocolTests {
    @Test func oneJsonObjectPerRequest() throws {
        let line = Data(#"{"op":"probe","service":"Wi-Fi","addresses":["192.168.1.11"]}"#.utf8)
        #expect(try JSONDecoder().decode(HelperRequest.self, from: line) == .probe(service: "Wi-Fi", addresses: ["192.168.1.11"]))
        let a = HelperRequest.apply(IpConfig(service: "Wi-Fi", dhcp: true))
        #expect(try JSONDecoder().decode(HelperRequest.self, from: JSONEncoder().encode(a)) == a)
    }

    @Test func rejectsUnknownServices() {
        #expect(throws: IpBumpError("Unknown network service \"Wi-Fii\".")) {
            try HelperValidation.validate(.apply(IpConfig(service: "Wi-Fii", dhcp: true)), services: ["Wi-Fi"])
        }
    }

    @Test func rejectsServicesThatLookLikeOptions() {
        #expect(throws: IpBumpError("IpBump can't manage a network service whose name starts with \"-\". Rename it in System Settings.")) {
            try HelperValidation.validate(.apply(IpConfig(service: "-setdhcp", dhcp: true)), services: ["-setdhcp"])
        }
    }

    @Test func dhcpNeedsOnlyTheService() throws {
        try HelperValidation.validate(.apply(IpConfig(service: "Wi-Fi", dhcp: true)), services: ["Wi-Fi"])
    }

    @Test func checksEveryAddress() {
        let ok = IpConfig(service: "Wi-Fi", ip: "192.168.1.20", mask: "255.255.255.0", router: "192.168.1.1")
        func bad(_ c: IpConfig, _ message: String) {
            #expect(throws: IpBumpError(message)) { try HelperValidation.validate(.apply(c), services: ["Wi-Fi"]) }
        }
        var c = ok; c.ip = "1.2.3"; bad(c, "Invalid IP address \"1.2.3\".")
        c = ok; c.mask = "255.0.255.0"; bad(c, "Invalid subnet mask \"255.0.255.0\".")
        c = ok; c.router = ""; bad(c, "Invalid router address \"\".")
        c = ok; c.dns1 = "x"; bad(c, "Invalid address \"x\".")
        #expect(throws: Never.self) { try HelperValidation.validate(.apply(ok), services: ["Wi-Fi"]) }
    }

    @Test func limitsProbes() {
        func bad(_ addresses: [String], _ message: String) {
            #expect(throws: IpBumpError(message)) {
                try HelperValidation.validate(.probe(service: "Wi-Fi", addresses: addresses), services: ["Wi-Fi"])
            }
        }
        bad([], "No addresses to probe.")
        bad(Array(repeating: "192.168.1.2", count: 65), "Too many addresses in one request (64 at most).")
        bad(["nope"], "Invalid address \"nope\".")
    }
}
