import Testing
@testable import IpBumpCore

struct FreeAddressFinderTests {
    let s = UserSettings(service: "Wi-Fi", ip: "192.168.1.10", mask: "255.255.255.0", router: "192.168.1.1", dns1: "192.168.1.2")
    let net = FakeNetwork()
    var finder: FreeAddressFinder { FreeAddressFinder(helper: net) }

    @Test func startsAfterTheCurrentAddress() throws {
        #expect(try FreeAddressFinder.candidates(s, current: "192.168.1.10", skip: []).prefix(3)
            == ["192.168.1.11", "192.168.1.12", "192.168.1.13"])
    }

    @Test func wrapsAroundAndSkipsRouterAndDns() throws {
        let c = try FreeAddressFinder.candidates(s, current: "192.168.1.254", skip: [])
        #expect(c.prefix(3) == ["192.168.1.3", "192.168.1.4", "192.168.1.5"])
        #expect(!c.contains("192.168.1.254") && !c.contains("192.168.1.1") && !c.contains("192.168.1.2"))
    }

    @Test func withoutAnAddressStartsAtTheSavedOne() throws {
        #expect(try FreeAddressFinder.candidates(s, current: "", skip: []).prefix(3)
            == ["192.168.1.10", "192.168.1.11", "192.168.1.12"])
    }

    @Test func honoursTheUserRangeAndSkipList() throws {
        var r = s
        r.rangeStart = "192.168.1.100"
        r.rangeEnd = "192.168.1.103"
        #expect(try FreeAddressFinder.candidates(r, current: "192.168.1.101", skip: ["192.168.1.103"])
            == ["192.168.1.102", "192.168.1.100"])
    }

    @Test func probesAtMost512() throws {
        var b = s
        b.mask = "255.255.0.0"
        #expect(try FreeAddressFinder.candidates(b, current: "192.168.1.10", skip: []).count == 512)
    }

    @Test func returnsTheFirstSilentAddressInBatchesOfEight() throws {
        net.taken = ["192.168.1.11", "192.168.1.12"]
        #expect(try finder.findFree(s, current: "192.168.1.10", skip: []) == "192.168.1.13")
        #expect(net.probes.first == (11...18).map { "192.168.1.\($0)" })
    }

    @Test func nilWhenEveryAddressAnswers() throws {
        var r = s
        r.rangeStart = "192.168.1.100"
        r.rangeEnd = "192.168.1.101"
        net.taken = ["192.168.1.100", "192.168.1.101"]
        #expect(try finder.findFree(r, current: "192.168.1.10", skip: []) == nil)
    }

    @Test func helperErrorsPassThrough() {
        net.probeError = "boom"
        #expect(throws: IpBumpError("boom")) { try finder.findFree(s, current: "192.168.1.10", skip: []) }
    }
}
