/// One ARP packet (IPv4 over Ethernet), as the helper reads it from BPF.
public struct ARPPacket: Equatable, Sendable {
    public let op: UInt16
    public let senderMAC: [UInt8]
    public let senderIP: UInt32
    public let targetIP: UInt32

    public init(op: UInt16, senderMAC: [UInt8], senderIP: UInt32, targetIP: UInt32) {
        self.op = op; self.senderMAC = senderMAC; self.senderIP = senderIP; self.targetIP = targetIP
    }
}

/// ARP rather than ping: firewalls drop pings, but a device can't hold an address without answering ARP.
public enum ARP {
    /// "Who has targetIP?", sent to every device on the link.
    public static func request(senderMAC: [UInt8], senderIP: UInt32, targetIP: UInt32) -> [UInt8] {
        var frame = [UInt8](repeating: 0xff, count: 6)            // Ethernet: to everyone
        frame += senderMAC
        frame += [0x08, 0x06]                                     // ARP
        frame += [0x00, 0x01, 0x08, 0x00, 6, 4, 0x00, 0x01]       // Ethernet and IPv4 addresses; a request
        frame += senderMAC
        frame += bytes(senderIP)
        frame += [UInt8](repeating: 0, count: 6)                  // the MAC being asked for
        frame += bytes(targetIP)
        return frame
    }

    /// nil for anything but IPv4-over-Ethernet ARP. Frames from the wire are often padded past 42 bytes.
    public static func parse(_ f: [UInt8]) -> ARPPacket? {
        guard f.count >= 42, f[12] == 0x08, f[13] == 0x06,
              f[14] == 0x00, f[15] == 0x01, f[16] == 0x08, f[17] == 0x00, f[18] == 6, f[19] == 4 else { return nil }
        return ARPPacket(op: UInt16(f[20]) << 8 | UInt16(f[21]), senderMAC: Array(f[22..<28]),
                         senderIP: number(f, at: 28), targetIP: number(f, at: 38))
    }

    /// One BPF read holds several packets, each behind a struct bpf_hdr and padded to 4 bytes.
    public static func frames(inBPFBuffer buffer: [UInt8]) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        var at = 0
        while at + 18 <= buffer.count {
            let caplen = Int(littleEndian(buffer, at: at + 8, bytes: 4))
            let hdrlen = Int(littleEndian(buffer, at: at + 16, bytes: 2))
            guard hdrlen >= 18, at + hdrlen + caplen <= buffer.count else { break }
            frames.append(Array(buffer[(at + hdrlen)..<(at + hdrlen + caplen)]))
            at += (hdrlen + caplen + 3) & ~3
        }
        return frames
    }

    static func bytes(_ ip: UInt32) -> [UInt8] { [UInt8(ip >> 24), UInt8(ip >> 16 & 255), UInt8(ip >> 8 & 255), UInt8(ip & 255)] }

    static func number(_ f: [UInt8], at i: Int) -> UInt32 {
        UInt32(f[i]) << 24 | UInt32(f[i + 1]) << 16 | UInt32(f[i + 2]) << 8 | UInt32(f[i + 3])
    }

    // struct bpf_hdr is in the Mac's own byte order, which is little-endian on Apple silicon and Intel alike
    static func littleEndian(_ b: [UInt8], at i: Int, bytes count: Int) -> UInt32 {
        (0..<count).reduce(0) { $0 | UInt32(b[i + $1]) << (8 * UInt32($1)) }
    }
}

/// Where ARP frames go out and come back in: BPF in the helper, scripted frames in tests.
public protocol LinkLayer {
    func send(_ frame: [UInt8]) throws
    /// The frames that arrive within `duration`.
    func receive(for duration: Duration) throws -> [[UInt8]]
}

public enum ARPProbe {
    /// The question goes out twice; an address that stays silent both times (1.5 s in all) counts as free.
    public static let resendAfter: Duration = .milliseconds(750)

    /// The Mac's own address as the sender. While that address is itself being checked, or when there is none,
    /// 0.0.0.0 instead: an RFC 5227 probe, which leaves other devices' ARP caches alone.
    public static func senderIP(current: String, targets: [String]) -> UInt32 {
        guard let mine = IPv4.number(current), !targets.compactMap(IPv4.number).contains(mine) else { return 0 }
        return mine
    }

    /// The targets another device answered for. Any ARP packet from another device that names a target as its own
    /// address counts, reply or not; packets from this Mac don't.
    public static func run(link: LinkLayer, ownMAC: [UInt8], senderIP: UInt32, targets: [UInt32]) throws -> Set<UInt32> {
        let wanted = Set(targets)
        var answered = Set<UInt32>()

        func ask(_ ips: [UInt32]) throws {
            for ip in ips { try link.send(ARP.request(senderMAC: ownMAC, senderIP: senderIP, targetIP: ip)) }
        }
        func listen() throws {
            for frame in try link.receive(for: resendAfter) {
                guard let p = ARP.parse(frame), p.senderMAC != ownMAC, wanted.contains(p.senderIP) else { continue }
                answered.insert(p.senderIP)
            }
        }

        try ask(targets)
        try listen()
        let silent = targets.filter { !answered.contains($0) }
        if !silent.isEmpty {
            try ask(silent)
            try listen()
        }
        return answered
    }
}
