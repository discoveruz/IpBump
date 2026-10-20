import Foundation
import IpBumpCore
@testable import IpBumpMac

/// A new, empty folder for one test; the system clears its temporary folder on its own.
func temporaryFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IpBumpTests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// A socket path short enough for sockaddr_un (104 bytes), which the temporary folder's path is not.
func temporarySocketPath() -> String { "/tmp/ipbump-test-\(UUID().uuidString.prefix(8)).sock" }

/// Stands in for the real backend behind the helper's socket.
final class FakeBackend: HelperBackend, @unchecked Sendable {
    private let lock = NSLock()
    var services = ["Wi-Fi"]
    var answered: Set<String> = []
    var applyError: String?
    private var recorded: [IpConfig] = []

    var applied: [IpConfig] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func serviceNames() -> [String] { services }

    func apply(_ config: IpConfig) throws {
        if let applyError { throw IpBumpError(applyError) }
        lock.lock(); defer { lock.unlock() }
        recorded.append(config)
    }

    func probe(service: String, addresses: [String]) throws -> Set<String> { answered.intersection(addresses) }
}

/// True for the first `count` calls, then false.
final class Countdown: @unchecked Sendable {
    private let lock = NSLock()
    private var left: Int

    init(_ count: Int) { left = count }

    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard left > 0 else { return false }
        left -= 1
        return true
    }
}
