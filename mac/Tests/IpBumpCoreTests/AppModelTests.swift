import Foundation
import Testing
@testable import IpBumpCore

@MainActor
struct AppModelTests {
    let s = UserSettings(service: "Wi-Fi", ip: "192.168.1.10", mask: "255.255.255.0", router: "192.168.1.1")
    let net = FakeNetwork(state: ServiceState(service: "Wi-Fi", interface: "en0", up: true, dhcp: true, ip: "192.168.1.10"),
                          services: ["Wi-Fi"])
    let changer = FakeChanger()
    let notifier = FakeNotifier()
    let folder = temporaryFolder()
    var lastChange: LastChangeStore { LastChangeStore(folder: folder) }

    func store(_ settings: UserSettings) -> SettingsStore {
        let store = SettingsStore(folder: folder)
        try! store.save(settings)
        return store
    }

    func model(_ settings: UserSettings) -> AppModel {
        AppModel(settings: store(settings), reader: net, changer: changer, lastChange: lastChange, notifier: notifier)
    }

    @Test func showsTheServicesAddress() {
        let m = model(s)
        #expect(m.menu.title == "192.168.1.10" && m.menu.statusLine == "192.168.1.10  ·  Wi-Fi")
    }

    @Test func asksForSetupFirst() async {
        let m = model(UserSettings())
        var asked = false
        m.onNeedsSetup = { asked = true }
        await m.changeIp()
        #expect(asked && changer.sources.isEmpty)
    }

    @Test func reportsSuccess() async {
        changer.result = ChangeResult(service: "Wi-Fi", oldIp: "192.168.1.10", newIp: "192.168.1.20")
        await model(s).changeIp()
        #expect(notifier.posts == [Post("IP changed", "Wi-Fi: 192.168.1.10 → 192.168.1.20", false)])
        #expect(changer.sources == ["tray"])
    }

    @Test func quietWhenNotificationsAreOff() async {
        var q = s
        q.showNotifications = false
        await model(q).changeIp()
        #expect(notifier.posts.isEmpty)
    }

    @Test func failureStaysInTheMenu() async {
        var q = s
        q.showNotifications = false
        changer.error = IpBumpError("boom")
        let m = model(q)
        await m.changeIp()
        #expect(m.menu.problem == "Could not change IP: boom" && m.menu.showsWarning)
        #expect(notifier.posts == [Post("Could not change IP", "boom", true)])
    }

    @Test func successClearsAnEarlierFailure() async {
        changer.error = IpBumpError("boom")
        let m = model(s)
        await m.changeIp()
        changer.error = nil
        await m.changeIp()
        #expect(m.menu.problem == nil)
    }

    @Test func ignoresClicksWhileBusy() async {
        changer.gate = DispatchSemaphore(value: 0)
        let m = model(s)
        async let first: Void = m.changeIp()
        await until { changer.sources.count == 1 }   // FakeChanger records the source before it waits on the gate
        await m.changeIp()
        changer.gate!.signal()
        await first
        #expect(changer.sources.count == 1)
    }

    @Test func dhcp() async {
        await model(s).useDhcp()
        #expect(notifier.posts == [Post("Automatic address", "Wi-Fi now gets its address from the network (DHCP).", false)])
    }

    @Test func dhcpFailure() async {
        changer.error = IpBumpError("boom")
        let m = model(s)
        await m.useDhcp()
        #expect(m.menu.problem == "Could not switch to automatic: boom")
    }

    @Test func reportsChangesByAgents() {
        let m = model(s)
        lastChange.save(LastChange(at: Date().addingTimeInterval(1), from: "192.168.1.10", to: "192.168.1.20", source: "Claude Code"))
        m.reportAgentChange()
        m.reportAgentChange()
        #expect(notifier.posts == [Post("IP changed by Claude Code", "192.168.1.10 → 192.168.1.20", false)])
    }

    @Test func ignoresItsOwnChanges() {
        let m = model(s)
        lastChange.save(LastChange(at: Date().addingTimeInterval(1), from: "a", to: "b", source: "tray"))
        m.reportAgentChange()
        #expect(notifier.posts.isEmpty)
    }

    /// Review Focus 5: the saved service is gone (renamed in System Settings, adapter unplugged).
    @Test func explainsAMissingService() async {
        net.state = nil
        let real = IpChanger(reader: net, helper: net, lock: PassLock(), lastChange: lastChange, sleep: { _ in })
        let m = AppModel(settings: store(s), reader: net, changer: real, lastChange: lastChange, notifier: notifier)
        await m.changeIp()
        #expect(m.menu.problem == "Could not change IP: Network service \"Wi-Fi\" was not found.")
        #expect(m.menu.title == "No IP")
    }

    @Test func announcesReadinessAfterFirstSetup() {
        let m = model(s)
        m.settingsClosed(firstRun: true)
        #expect(notifier.posts == [Post("IpBump is ready", "Click the address in the menu bar for a new IP, or Option-click it to change right away.", false)])
    }

    @Test func picksUpSavedSettings() throws {
        let m = model(s)
        var compact = s
        compact.showFullAddress = false
        try SettingsStore(folder: folder).save(compact)
        m.settingsClosed(firstRun: false)
        #expect(m.menu.title == "10" && notifier.posts.isEmpty)
    }
}
