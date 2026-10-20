import Testing
@testable import IpBumpCore

struct IpChangerTests {
    let before = ServiceState(service: "Wi-Fi", interface: "en0", up: true, dhcp: true, ip: "192.168.1.10",
                              mask: "255.255.255.0", router: "192.168.1.1", dns1: "8.8.8.8")
    let s = UserSettings(service: "Wi-Fi", ip: "192.168.1.10", mask: "255.255.255.0", router: "192.168.1.1", dns1: "192.168.1.2")
    let net: FakeNetwork
    let lastChange = LastChangeStore(folder: temporaryFolder())
    // The 10-second wait runs at once: sleeping does nothing here
    var changer: IpChanger { IpChanger(reader: net, helper: net, lock: PassLock(), lastChange: lastChange, sleep: { _ in }) }

    init() { net = FakeNetwork(state: before) }

    @Test func notSetUp() {
        var e = s
        e.service = ""
        #expect(throws: IpBumpError("IpBump isn't set up yet. Open its settings and pick a network service.")) {
            try changer.toFreeAddress(e, source: "tray", progress: nil)
        }
    }

    @Test func serviceMissing() {
        net.state = nil
        #expect(throws: IpBumpError("Network service \"Wi-Fi\" was not found.")) {
            try changer.toFreeAddress(s, source: "tray", progress: nil)
        }
    }

    @Test func serviceDown() {
        net.state?.up = false
        #expect(throws: IpBumpError("\"Wi-Fi\" is not connected.")) { try changer.toFreeAddress(s, source: "tray", progress: nil) }
        #expect(net.applied.isEmpty)
    }

    /// Review fix: settings saved at home, laptop now on another network. A "free" address from the saved range
    /// would take the Mac off the network it is on, and nothing would answer to show it.
    @Test func refusesToChangeOnAnotherNetwork() {
        net.state?.ip = "10.0.0.5"
        #expect(throws: IpBumpError("\"Wi-Fi\" is on another network now (10.0.0.5). Open IpBump's settings, choose \"Use the service's current values\" and save.")) {
            try changer.toFreeAddress(s, source: "Claude Code", progress: nil)
        }
        #expect(net.applied.isEmpty && net.probes.isEmpty)
    }

    @Test func everyAddressInUse() {
        var r = s
        r.rangeStart = "192.168.1.100"
        r.rangeEnd = "192.168.1.101"
        net.taken = ["192.168.1.100", "192.168.1.101"]
        #expect(throws: IpBumpError("Every address in the search range is in use.")) {
            try changer.toFreeAddress(r, source: "tray", progress: nil)
        }
        #expect(net.applied.isEmpty)
    }

    @Test func movesToTheFirstFreeAddress() throws {
        let steps = Recorder<String>()
        #expect(try changer.toFreeAddress(s, source: "Claude Code", progress: { steps.append($0) })
            == ChangeResult(service: "Wi-Fi", oldIp: "192.168.1.10", newIp: "192.168.1.11"))
        #expect(net.applied == [s.config(ip: "192.168.1.11")])
        #expect(steps.all == ["Looking for a free address…", "Applying 192.168.1.11…"])
        let note = try #require(lastChange.load())
        #expect(note.from == "192.168.1.10" && note.to == "192.168.1.11" && note.source == "Claude Code")
    }

    @Test func skipsAnAddressAnotherDeviceClaims() throws {
        net.claimsWhenTaken = ["192.168.1.11"]
        #expect(try changer.toFreeAddress(s, source: "tray", progress: nil).newIp == "192.168.1.12")
        #expect(net.applied.map(\.ip) == ["192.168.1.11", "192.168.1.12"])
    }

    @Test func givesUpAfterThreeClaimsAndRestores() {
        net.claimsWhenTaken = ["192.168.1.11", "192.168.1.12", "192.168.1.13"]
        #expect(throws: IpBumpError("Other devices claimed 192.168.1.11, 192.168.1.12, 192.168.1.13. The previous address was put back.")) {
            try changer.toFreeAddress(s, source: "tray", progress: nil)
        }
        #expect(net.applied.last == before.config)
    }

    @Test func restoresWhenMacOSNeverUsesTheAddress() {
        net.startsUsing = false
        #expect(throws: IpBumpError("macOS did not start using the new address. The previous address was put back.")) {
            try changer.toFreeAddress(s, source: "tray", progress: nil)
        }
        #expect(net.applied == [s.config(ip: "192.168.1.11"), before.config])
    }

    @Test func failedFirstApplyNeedsNoRestore() {
        net.applyError = "boom"
        #expect(throws: IpBumpError("boom")) { try changer.toFreeAddress(s, source: "tray", progress: nil) }
        #expect(net.applied.isEmpty)
    }

    @Test func nothingToGoBackTo() {
        net.state = ServiceState(service: "Wi-Fi", up: true, dhcp: false)
        net.startsUsing = false
        #expect(throws: IpBumpError("macOS did not start using the new address. The previous address was put back.")) {
            try changer.toFreeAddress(s, source: "tray", progress: nil)
        }
        #expect(net.applied.count == 1)
    }

    @Test func waitsForTheLock() {
        let busy = IpChanger(reader: net, helper: net, lock: BusyLock(), lastChange: lastChange, sleep: { _ in })
        #expect(throws: IpBumpError.changeRunning) { try busy.toFreeAddress(s, source: "tray", progress: nil) }
        #expect(net.applied.isEmpty)
    }

    @Test func applySettingsAppliesExactlyTheSettings() throws {
        var m = s
        m.ip = "192.168.1.50"
        try changer.applySettings(m)
        #expect(net.applied == [m.config(ip: "192.168.1.50")])
        #expect(lastChange.load()?.source == "tray")
    }

    @Test func applySettingsRestoresOnConflict() {
        var m = s
        m.ip = "192.168.1.50"
        net.claimsWhenTaken = ["192.168.1.50"]
        #expect(throws: IpBumpError("Another device is already using 192.168.1.50. The previous address was put back.")) {
            try changer.applySettings(m)
        }
        #expect(net.applied.last == before.config)
    }

    @Test func useDhcp() throws {
        try changer.useDhcp(s)
        #expect(net.applied == [IpConfig(service: "Wi-Fi", dhcp: true)])
    }
}
