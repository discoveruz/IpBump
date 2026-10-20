import Foundation

/// Unix-domain socket plumbing for the helper and the processes that ask it: one line of text each way.
enum LineSocket {
    enum ReadFailure: Error {
        case timedOut, tooLong, closed
    }

    static func listen(path: String) throws -> Int32 {
        guard var address = address(path) else { throw POSIXError(.ENAMETOOLONG) }
        unlink(path)   // left behind by an earlier run
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError() }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        // Every login account may ask, as on Windows: they are all in the staff group. Service accounts such as
        // _www or nobody are not, and nobody can reach a Unix socket from the network
        let staff = getgrnam("staff")?.pointee.gr_gid ?? 20
        guard bound == 0, chown(path, uid_t.max, staff) == 0, chmod(path, 0o660) == 0, Darwin.listen(fd, 16) == 0 else {
            let error = posixError()
            close(fd)
            throw error
        }
        return fd
    }

    /// nil when nothing listens there.
    static func connect(path: String, timeout: Duration) -> Int32? {
        guard var address = address(path) else { return nil }
        let deadline = ContinuousClock.now + timeout
        while true {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return nil }
            noSigPipe(fd)
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            if connected == 0 { return fd }
            let reason = errno
            close(fd)
            // A full queue of waiting clients is worth another try; a missing or dead socket is not
            guard reason == EAGAIN, ContinuousClock.now < deadline else { return nil }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// The text up to the first newline, waiting at most `timeout` in all.
    static func readLine(_ fd: Int32, timeout: Duration, maxBytes: Int) throws -> String {
        let deadline = ContinuousClock.now + timeout
        var data: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            if let end = data.firstIndex(of: 0x0A) { return String(decoding: data[..<end], as: UTF8.self) }
            if data.count > maxBytes { throw ReadFailure.tooLong }
            let left = deadline - ContinuousClock.now
            guard left > .zero else { throw ReadFailure.timedOut }

            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&p, 1, milliseconds(left))
            if ready < 0 && errno == EINTR { continue }
            if ready < 0 { throw ReadFailure.closed }
            if ready == 0 { throw ReadFailure.timedOut }
            let n = read(fd, &chunk, chunk.count)
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { throw ReadFailure.closed }
            data.append(contentsOf: chunk[..<n])
        }
    }

    static func writeLine(_ fd: Int32, _ text: String) -> Bool { writeAll(fd, Array((text + "\n").utf8)) }

    static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var sent = 0
        while sent < bytes.count {
            let n = bytes[sent...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return false }
            sent += n
        }
        return true
    }

    /// A peer that hangs up early must not kill this process with SIGPIPE: the helper is a daemon.
    static func noSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// A peer that stops reading can't make a write hang for longer than this.
    static func sendTimeout(_ fd: Int32, _ timeout: Duration) {
        var limit = timeval(tv_sec: Int(timeout.components.seconds), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
    }

    /// sockaddr_un for a path; nil when the path doesn't fit (104 bytes on macOS).
    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    static func milliseconds(_ d: Duration) -> Int32 {
        let (seconds, attoseconds) = d.components
        return Int32(clamping: max(1, seconds * 1000 + attoseconds / 1_000_000_000_000_000))
    }

    static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
