import Foundation

/// Per-user settings, kept in ~/Library/Application Support/IpBump/settings.json (each Mac account has its own).
public struct UserSettings: Codable, Equatable, Sendable {
    public var service: String
    public var ip: String
    public var mask: String
    public var router: String
    public var dns1: String
    public var dns2: String
    /// Where to look for free addresses. Empty = the whole subnet.
    public var rangeStart: String
    public var rangeEnd: String
    /// Whether AI agents (through "IpBump mcp") may change the IP.
    public var allowAgents: Bool
    public var showNotifications: Bool
    /// The whole address in the menu bar, or only its last number.
    public var showFullAddress: Bool

    public init(service: String = "", ip: String = "", mask: String = "", router: String = "", dns1: String = "",
                dns2: String = "", rangeStart: String = "", rangeEnd: String = "", allowAgents: Bool = false,
                showNotifications: Bool = true, showFullAddress: Bool = true) {
        self.service = service; self.ip = ip; self.mask = mask; self.router = router; self.dns1 = dns1; self.dns2 = dns2
        self.rangeStart = rangeStart; self.rangeEnd = rangeEnd; self.allowAgents = allowAgents
        self.showNotifications = showNotifications; self.showFullAddress = showFullAddress
    }

    /// These settings with another address, ready for the helper.
    public func config(ip: String) -> IpConfig {
        IpConfig(service: service, ip: ip, mask: mask, router: router, dns1: dns1, dns2: dns2)
    }
}

extension UserSettings {
    // Declared here rather than in the type, so the memberwise-style init above stays as it is.
    // A file from another version may lack keys; those keep their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        let d = UserSettings()
        self.init(service: try value(.service, d.service), ip: try value(.ip, d.ip), mask: try value(.mask, d.mask),
                  router: try value(.router, d.router), dns1: try value(.dns1, d.dns1), dns2: try value(.dns2, d.dns2),
                  rangeStart: try value(.rangeStart, d.rangeStart), rangeEnd: try value(.rangeEnd, d.rangeEnd),
                  allowAgents: try value(.allowAgents, d.allowAgents),
                  showNotifications: try value(.showNotifications, d.showNotifications),
                  showFullAddress: try value(.showFullAddress, d.showFullAddress))
    }
}

public struct SettingsStore: Sendable {
    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    var file: URL { folder.appendingPathComponent("settings.json") }

    public func load() -> UserSettings {
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONDecoder().decode(UserSettings.self, from: data)
        else { return UserSettings() }   // not saved yet, or a corrupt file: defaults
        return settings
    }

    public func save(_ settings: UserSettings) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: file, options: .atomic)
    }
}
