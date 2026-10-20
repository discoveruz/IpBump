import Foundation
import Testing
import IpBumpCore
@testable import IpBumpMac

struct FileChangeLockTests {
    let file = temporaryFolder().appendingPathComponent("change.lock")

    @Test func secondHolderTimesOut() throws {
        let holding = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let file = file
        Thread.detachNewThread {
            try? FileChangeLock(path: file).withLock {
                holding.signal()
                release.wait()
            }
        }
        holding.wait()
        defer { release.signal() }
        #expect(throws: IpBumpError.changeRunning) { try FileChangeLock(path: file, timeout: .milliseconds(300)).withLock {} }
    }

    @Test func releasedAfterTheBody() throws {
        #expect(try FileChangeLock(path: file).withLock { 42 } == 42)
        try FileChangeLock(path: file, timeout: .milliseconds(300)).withLock {}
    }

    @Test func bodyErrorsPassThroughAndRelease() throws {
        #expect(throws: IpBumpError("x")) { try FileChangeLock(path: file).withLock { throw IpBumpError("x") } }
        try FileChangeLock(path: file, timeout: .milliseconds(300)).withLock {}
    }
}
