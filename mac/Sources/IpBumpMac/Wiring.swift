import Foundation
import IpBumpCore

/// The real objects, as the menu bar app, the MCP server and the hook all use them.
public enum Wiring {
    public static func settings() -> SettingsStore { SettingsStore(folder: Paths.appSupport) }

    public static func lastChange() -> LastChangeStore { LastChangeStore(folder: Paths.appSupport) }

    public static func changer() -> IpChanger {
        IpChanger(reader: SystemNetwork(), helper: SocketHelper(),
                  lock: FileChangeLock(path: Paths.appSupport.appendingPathComponent("change.lock")),
                  lastChange: lastChange())
    }
}
