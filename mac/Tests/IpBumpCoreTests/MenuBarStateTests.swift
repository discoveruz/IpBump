import Testing
@testable import IpBumpCore

struct MenuBarStateTests {
    let on = MenuBarState(setUp: true, ip: "192.168.1.189", service: "Wi-Fi")

    @Test func titles() {
        #expect(MenuBarState().title == "IpBump")
        #expect(on.title == "192.168.1.189")
        var c = on; c.showFullAddress = false
        #expect(c.title == "189")
        var b = on; b.busy = true
        #expect(b.title == "192.168.1.…")
        b.showFullAddress = false
        #expect(b.title == "…")
        var e = on; e.ip = ""; e.busy = true
        #expect(e.title == "…")
    }

    /// Review Focus 5: a service that lost its address, or went away, says so instead of showing an old address.
    @Test func noAddress() {
        var n = on; n.ip = ""
        #expect(n.title == "No IP")
        n.showFullAddress = false
        #expect(n.title == "–")
    }

    @Test func warnsAfterAFailure() {
        var p = on; p.problem = "Could not change IP: boom"
        #expect(p.title == "192.168.1.189" && p.showsWarning)
        p.busy = true
        #expect(!p.showsWarning)
        #expect(!on.showsWarning)
    }

    @Test func statusLine() {
        #expect(on.statusLine == "192.168.1.189  ·  Wi-Fi")
        var n = on; n.ip = ""
        #expect(n.statusLine == "No address")
        var p = on; p.problem = "Could not change IP: boom"
        #expect(p.statusLine == "Could not change IP: boom")
        #expect(MenuBarState().statusLine == "Not set up yet")
    }

    @Test func tooltip() {
        #expect(on.tooltip == "IpBump  192.168.1.189  ·  Wi-Fi\nClick: menu   Option-click: new IP")
        var b = on; b.busy = true; b.progress = "Applying 192.168.1.20…"
        #expect(b.tooltip == "Applying 192.168.1.20…")
    }
}
