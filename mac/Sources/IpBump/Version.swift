import Foundation

enum Version {
    /// The app bundle's version; "dev" for a build that isn't inside IpBump.app.
    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
}
