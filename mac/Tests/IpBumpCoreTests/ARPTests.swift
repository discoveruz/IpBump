import Testing
@testable import IpBumpCore

struct ARPTests {
    let me: [UInt8] = [2, 0, 0, 0, 0, 1]
    let other: [UInt8] = [2, 0, 0, 0, 0, 2]

    func bytes(_ ip: String) -> [UInt8] { ip.split(separator: ".").map { UInt8($0)! } }

    /// An ARP packet as it arrives from the wire, padded to Ethernet's 60-byte minimum.
    func arp(op: UInt8, from mac: [UInt8], ip: String, to target: String) -> [UInt8] {
        var f: [UInt8] = me + mac + [0x08, 0x06]
        f += [0x00, 0x01, 0x08, 0x00, 6, 4, 0x00, op]
        f += mac + bytes(ip)
        f += me + bytes(target)
        return f + [UInt8](repeating: 0, count: 60 - f.count)
    }

    func reply(from mac: [UInt8], ip: String, to target: String = "192.168.1.10") -> [UInt8] { arp(op: 2, from: mac, ip: ip, to: target) }

    func request(from mac: [UInt8], ip: String) -> [UInt8] { arp(op: 1, from: mac, ip: ip, to: "192.168.1.99") }

    var ipv4Frame: [UInt8] {
        var f = reply(from: other, ip: "192.168.1.20")
        f[12] = 0x08; f[13] = 0x00
        return f
    }

    /// A struct bpf_hdr as macOS lays it out: 8 bytes of time, caplen and datalen (little-endian), hdrlen 18.
    func bpfRecord(_ frame: [UInt8]) -> [UInt8] {
        let n = UInt32(frame.count)
        let len: [UInt8] = [UInt8(n & 255), UInt8(n >> 8 & 255), 0, 0]
        return [UInt8](repeating: 0, count: 8) + len + len + [18, 0] + frame
    }

    func ip(_ last: Int) -> UInt32 { IPv4.number("192.168.1.\(last)")! }

    @Test func buildsABroadcastRequest() {
        var expected = [UInt8](repeating: 0xff, count: 6) + me + [0x08, 0x06, 0, 1, 0x08, 0, 6, 4, 0, 1]
        expected += me + [192, 168, 1, 10] + [UInt8](repeating: 0, count: 6) + [192, 168, 1, 20]
        #expect(ARP.request(senderMAC: me, senderIP: ip(10), targetIP: ip(20)) == expected)
    }

    @Test func parsesAnyArpFrame() {
        #expect(ARP.parse(reply(from: other, ip: "192.168.1.20", to: "192.168.1.10"))
            == ARPPacket(op: 2, senderMAC: other, senderIP: ip(20), targetIP: ip(10)))
        #expect(ARP.parse(ipv4Frame) == nil)
        #expect(ARP.parse(Array(reply(from: other, ip: "192.168.1.20").prefix(41))) == nil)
    }

    @Test func splitsABPFBuffer() {
        let a = reply(from: other, ip: "192.168.1.20"), b = reply(from: other, ip: "192.168.1.21")
        // 18 + 60 = 78 bytes, so two bytes of padding before the next record; the cut-off tail is dropped
        #expect(ARP.frames(inBPFBuffer: bpfRecord(a) + [0, 0] + bpfRecord(b) + [1, 2, 3]) == [a, b])
    }

    @Test func senderIsTheMacsAddressUnlessItIsBeingProbed() {
        #expect(ARPProbe.senderIP(current: "192.168.1.10", targets: ["192.168.1.20"]) == ip(10))
        #expect(ARPProbe.senderIP(current: "192.168.1.10", targets: ["192.168.1.10"]) == 0)
        #expect(ARPProbe.senderIP(current: "", targets: ["192.168.1.20"]) == 0)
    }

    @Test func resendsOnceAndCollectsForeignAnswers() throws {
        let link = FakeLink(rounds: [
            [reply(from: other, ip: "192.168.1.21"), reply(from: me, ip: "192.168.1.22"), ipv4Frame],
            [request(from: other, ip: "192.168.1.20")],
        ])
        let answered = try ARPProbe.run(link: link, ownMAC: me, senderIP: ip(10), targets: [ip(20), ip(21), ip(22)])
        #expect(answered == [ip(20), ip(21)])
        #expect(link.sentTargets == [ip(20), ip(21), ip(22), ip(20), ip(22)])
    }

    @Test func noSecondRoundWhenEveryoneAnswered() throws {
        let link = FakeLink(rounds: [[reply(from: other, ip: "192.168.1.20")]])
        #expect(try ARPProbe.run(link: link, ownMAC: me, senderIP: ip(10), targets: [ip(20)]) == [ip(20)])
        #expect(link.sentTargets == [ip(20)])
    }
}
