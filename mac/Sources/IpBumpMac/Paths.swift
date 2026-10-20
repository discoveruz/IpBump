import Foundation
import IpBumpCore

/// Where IpBump keeps things. The environment can point elsewhere, for tests and for development.
public enum Paths {
    /// ~/Library/Application Support/IpBump, or $IPBUMP_HOME.
    public static var appSupport: URL {
        if let folder = ProcessInfo.processInfo.environment["IPBUMP_HOME"], !folder.isEmpty {
            return URL(fileURLWithPath: folder)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IpBump")
    }

    /// The root helper's socket, or $IPBUMP_HELPER_SOCKET (a helper started by hand during development).
    public static var helperSocket: String {
        if let path = ProcessInfo.processInfo.environment["IPBUMP_HELPER_SOCKET"], !path.isEmpty { return path }
        return HelperInfo.socketPath
    }

    /// This program, as an AI agent should start it.
    public static var executable: String {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().path
    }
}
