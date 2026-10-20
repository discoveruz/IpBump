import Foundation
import Testing
@testable import IpBumpCore

struct SettingsTests {
    let folder = temporaryFolder()
    var file: URL { folder.appendingPathComponent("settings.json") }
    var store: SettingsStore { SettingsStore(folder: folder) }

    @Test func defaults() {
        let s = UserSettings()
        #expect(s.showNotifications && s.showFullAddress && !s.allowAgents && s.service == "")
    }

    @Test func roundTrip() throws {
        let nested = SettingsStore(folder: folder.appendingPathComponent("IpBump"))
        var s = UserSettings()
        s.service = "Wi-Fi"
        s.allowAgents = true
        try nested.save(s)
        #expect(nested.load() == s)
    }

    @Test func missingKeysKeepDefaults() throws {
        try #"{"service":"Wi-Fi"}"#.write(to: file, atomically: true, encoding: .utf8)
        let s = store.load()
        #expect(s.service == "Wi-Fi" && s.showNotifications && s.showFullAddress && !s.allowAgents)
    }

    @Test func corruptFileGivesDefaults() throws {
        try "{nope".write(to: file, atomically: true, encoding: .utf8)
        #expect(store.load() == UserSettings())
    }

    @Test func configUsesTheGivenAddress() {
        let s = UserSettings(service: "Wi-Fi", ip: "192.168.1.10", mask: "255.255.255.0", router: "192.168.1.1", dns1: "8.8.8.8")
        #expect(s.config(ip: "192.168.1.20")
            == IpConfig(service: "Wi-Fi", ip: "192.168.1.20", mask: "255.255.255.0", router: "192.168.1.1", dns1: "8.8.8.8"))
    }
}
