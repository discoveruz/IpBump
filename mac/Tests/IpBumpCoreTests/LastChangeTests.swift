import Foundation
import Testing
@testable import IpBumpCore

struct LastChangeTests {
    let folder = temporaryFolder()
    var file: URL { folder.appendingPathComponent("last-change.json") }
    var store: LastChangeStore { LastChangeStore(folder: folder) }

    @Test func roundTrip() {
        let c = LastChange(at: Date(timeIntervalSince1970: 1_800_000_000.25), from: "192.168.1.10", to: "192.168.1.20", source: "Claude Code")
        store.save(c)
        #expect(store.load() == c)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("last-change.json.tmp").path))
    }

    @Test func missingOrCorruptIsNil() throws {
        #expect(store.load() == nil)
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(store.load() == nil)
    }
}
