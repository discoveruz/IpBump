/// IPv4 addresses as text (192.168.44.189) and as numbers for range math (0xC0A82CBD).
public enum IPv4 {
    /// Four dot-separated decimal numbers from 0 to 255, with no spaces and no leading zeros.
    public static func isValid(_ s: String) -> Bool { number(s) != nil }

    /// A subnet mask is ones followed by zeros, e.g. 255.255.255.0.
    public static func isMask(_ s: String) -> Bool {
        guard let n = number(s) else { return false }
        let zeros = ~n
        return zeros != .max && (zeros & (zeros + 1)) == 0
    }

    /// 192.168.44.189 -> 0xC0A82CBD, or nil when the text is not an IPv4 address.
    public static func number(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var n: UInt32 = 0
        for part in parts {
            // Some parsers read "010" as 8, others as 10; refusing leading zeros keeps everyone on the same address
            guard (1...3).contains(part.count), part.allSatisfy({ ("0"..."9").contains($0) }),
                  part == "0" || part.first != "0", let byte = UInt32(part), byte <= 255 else { return nil }
            n = n << 8 | byte
        }
        return n
    }

    public static func string(_ n: UInt32) -> String { "\(n >> 24).\(n >> 16 & 255).\(n >> 8 & 255).\(n & 255)" }

    public static func sameNetwork(_ a: String, _ b: String, mask: String) -> Bool {
        guard let x = number(a), let y = number(b), isMask(mask), let m = number(mask) else { return false }
        return x & m == y & m
    }
}
