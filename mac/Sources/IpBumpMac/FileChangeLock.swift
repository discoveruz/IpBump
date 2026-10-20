import Foundation
import IpBumpCore

/// One change at a time across processes: the menu bar app, every MCP server and the hook take this lock.
/// flock() goes away with the process that held it, so a crash in the middle of a change never leaves it stuck.
public struct FileChangeLock: ChangeLock {
    let path: URL
    let timeout: Duration

    public init(path: URL, timeout: Duration = .seconds(30)) {
        self.path = path
        self.timeout = timeout
    }

    public func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(path.path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { throw IpBumpError("Could not open \(path.path).") }
        defer { close(fd) }   // closing the file also lets go of the lock

        let deadline = ContinuousClock.now + timeout
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, ContinuousClock.now < deadline else { throw IpBumpError.changeRunning }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return try body()
    }
}
