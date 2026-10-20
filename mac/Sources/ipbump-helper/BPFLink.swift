import CBPF
import Foundation
import IpBumpCore

/// ARP frames in and out of one interface. Only root may open BPF devices.
final class BPFLink: LinkLayer {
    let fd: Int32
    let bufferLength: Int

    init(interface: String) throws {
        // Reads come back at least every 100 ms, so a deadline is never overshot by much
        let fd = ipb_bpf_open(interface, 100)
        guard fd >= 0 else { throw IpBumpError("Could not listen on \(interface): \(String(cString: strerror(-fd))).") }
        let length = ipb_bpf_buffer_length(fd)
        guard length > 0 else {
            close(fd)
            throw IpBumpError("Could not listen on \(interface): \(String(cString: strerror(-length))).")
        }
        self.fd = fd
        bufferLength = Int(length)
    }

    deinit { close(fd) }

    func send(_ frame: [UInt8]) throws {
        let sent = frame.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard sent == frame.count else { throw IpBumpError("Could not send an ARP request: \(String(cString: strerror(errno))).") }
    }

    func receive(for duration: Duration) throws -> [[UInt8]] {
        let deadline = ContinuousClock.now + duration
        var frames: [[UInt8]] = []
        var buffer = [UInt8](repeating: 0, count: bufferLength)
        while ContinuousClock.now < deadline {
            let n = read(fd, &buffer, bufferLength)
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw IpBumpError("Could not read ARP answers: \(String(cString: strerror(errno))).") }
            if n > 0 { frames += ARP.frames(inBPFBuffer: Array(buffer[..<n])) }
        }
        return frames
    }
}
