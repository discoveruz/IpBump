/// What the menu bar shows: the address (or its last number) beside the clock, and the menu's first line.
public struct MenuBarState: Equatable, Sendable {
    public var setUp: Bool
    public var ip: String
    public var service: String
    public var busy: Bool
    /// Why the last change failed. It stays on the menu bar and in the menu until something works.
    public var problem: String?
    /// The step a running change is at.
    public var progress: String?
    public var showFullAddress: Bool

    public init(setUp: Bool = false, ip: String = "", service: String = "", busy: Bool = false,
                problem: String? = nil, progress: String? = nil, showFullAddress: Bool = true) {
        self.setUp = setUp; self.ip = ip; self.service = service; self.busy = busy
        self.problem = problem; self.progress = progress; self.showFullAddress = showFullAddress
    }

    public var title: String {
        guard setUp else { return "IpBump" }
        let parts = ip.split(separator: ".")
        if busy {
            guard showFullAddress, parts.count == 4 else { return "…" }
            return parts.dropLast().joined(separator: ".") + ".…"
        }
        if ip.isEmpty { return showFullAddress ? "No IP" : "–" }
        return showFullAddress ? ip : String(parts.last ?? "")
    }

    /// Notifications can be switched off, so the menu bar carries the failure too.
    public var showsWarning: Bool { problem != nil && !busy }

    public var statusLine: String {
        if let problem { return problem }
        guard setUp else { return "Not set up yet" }
        return ip.isEmpty ? "No address" : "\(ip)  ·  \(service)"
    }

    public var tooltip: String {
        if busy, let progress { return progress }
        return "IpBump  \(statusLine)\nClick: menu   Option-click: new IP"
    }
}
