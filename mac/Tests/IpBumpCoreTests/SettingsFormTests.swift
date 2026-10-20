import Testing
@testable import IpBumpCore

struct SettingsFormTests {
    let s = UserSettings(service: "Wi-Fi", ip: "192.168.1.10", mask: "255.255.255.0", router: "192.168.1.1", dns1: "8.8.8.8")
    let net = FakeNetwork(state: ServiceState(service: "Wi-Fi", interface: "en0", up: true, dhcp: true, ip: "192.168.1.10",
                                              mask: "255.255.255.0", router: "192.168.1.1", dns1: "8.8.8.8"),
                          services: ["Wi-Fi"])
    var form: SettingsForm { SettingsForm.initial(saved: s, reader: net) }

    @Test func firstRunStartsFromTheDefaultService() {
        let f = SettingsForm.initial(saved: UserSettings(), reader: net)
        #expect(f.service == "Wi-Fi" && f.ip == "192.168.1.10" && f.mask == "255.255.255.0")
        #expect(f.router == "192.168.1.1" && f.dns1 == "8.8.8.8")
    }

    @Test func showsTheLiveAddressInTheSameNetwork() {
        net.state?.ip = "192.168.1.77"
        #expect(SettingsForm.initial(saved: s, reader: net).ip == "192.168.1.77")
        net.state?.ip = "10.0.0.5"
        #expect(SettingsForm.initial(saved: s, reader: net).ip == "192.168.1.10")
    }

    @Test func fillsFromTheService() {
        var f = SettingsForm(service: "Wi-Fi")
        let filled = f.fill(from: net)
        #expect(filled && f.ip == "192.168.1.10" && f.router == "192.168.1.1")
        f.service = "Ethernet"
        let missing = f.fill(from: net)
        #expect(!missing)
    }

    @Test func placeholdersShowTheWholeNetwork() {
        #expect(form.rangePlaceholders.from == "192.168.1.1" && form.rangePlaceholders.to == "192.168.1.254")
        var f = form
        f.mask = "x"
        #expect(f.rangePlaceholders.from == "" && f.rangePlaceholders.to == "")
    }

    @Test func explainsEachField() {
        func bad(_ edit: (inout SettingsForm) -> Void, _ field: SettingsForm.Field, _ message: String) {
            var f = form
            edit(&f)
            #expect(throws: SettingsForm.Problem(field: field, message: message)) { try f.validated() }
        }
        bad({ $0.service = "" }, .service, "Pick a network service.")
        bad({ $0.ip = "" }, .ip, "Enter an IP address.")
        bad({ $0.ip = "1.2.3" }, .ip, "\"1.2.3\" is not a valid IPv4 address.")
        bad({ $0.mask = "" }, .mask, "Enter a subnet mask, such as 255.255.255.0.")
        bad({ $0.mask = "255.0.255.0" }, .mask, "\"255.0.255.0\" is not a valid subnet mask.")
        bad({ $0.router = "" }, .router, "Enter the router address.")
        bad({ $0.dns2 = "x" }, .dns2, "\"x\" is not a valid IPv4 address.")
        bad({ $0.mask = "255.255.255.254" }, .mask, "Subnet mask 255.255.255.254 leaves no addresses to choose from.")
        bad({ $0.rangeStart = "10.0.0.1" }, .rangeStart, "The search range must be inside this network (192.168.1.1 to 192.168.1.254).")
    }

    @Test func savesWhatWasEntered() throws {
        var f = form
        f.ip = " 192.168.1.10 "
        f.rangeEnd = "192.168.1.200"
        f.allowAgents = true
        let saved = try f.validated()
        #expect(saved.ip == "192.168.1.10" && saved.rangeEnd == "192.168.1.200" && saved.allowAgents && saved.service == "Wi-Fi")
    }

    @Test func appliesOnlyWhatChanged() {
        #expect(!SettingsForm.needsApply(s, live: net.state))
        var m = s
        m.ip = "192.168.1.11"
        #expect(SettingsForm.needsApply(m, live: net.state))
        #expect(SettingsForm.needsApply(s, live: nil))
    }

    @Test func statusText() {
        #expect(SettingsForm.statusText(nil) == "")
        var st = net.state!
        st.up = false
        #expect(SettingsForm.statusText(st) == "Not connected")
        st.up = true
        #expect(SettingsForm.statusText(st) == "Connected  ·  address assigned automatically (DHCP)")
        st.dhcp = false
        #expect(SettingsForm.statusText(st) == "Connected  ·  manual address")
    }
}
