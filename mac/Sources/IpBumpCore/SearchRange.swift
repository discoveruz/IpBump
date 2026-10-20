/// Where to look for a free address: the subnet's usable addresses, narrowed by the user's From and To.
public enum SearchRange {
    /// A From or To that is not an IPv4 address means "no limit on that side".
    public static func of(ip: String, mask: String, from: String = "", to: String = "") throws -> ClosedRange<UInt32> {
        guard let address = IPv4.number(ip), IPv4.isMask(mask), let bits = IPv4.number(mask) else {
            throw IpBumpError("Enter the IP address and subnet mask in IpBump's settings first.")
        }
        // Without the network and broadcast address; 64-bit so a /31 or /32 can't wrap around
        let first = Int64(address & bits) + 1, last = Int64(address | ~bits) - 1
        guard first <= last else { throw IpBumpError("Subnet mask \(mask) leaves no addresses to choose from.") }
        let network = UInt32(first)...UInt32(last)

        let lower = IPv4.number(from) ?? network.lowerBound, upper = IPv4.number(to) ?? network.upperBound
        guard network.contains(lower), network.contains(upper) else {
            throw IpBumpError("The search range must be inside this network "
                + "(\(IPv4.string(network.lowerBound)) to \(IPv4.string(network.upperBound))).")
        }
        guard lower <= upper else { throw IpBumpError("The search range's From address comes after its To address.") }
        return lower...upper
    }
}
