import Foundation
import SystemConfiguration

/// Calls back on the main queue whenever a service's address, DNS servers or link change, whoever changed them,
/// so the menu bar can follow along.
public final class NetworkChangeWatcher: @unchecked Sendable {
    private var store: SCDynamicStore?
    private let onChange: @Sendable () -> Void

    public init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            Unmanaged<NetworkChangeWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        store = SCDynamicStoreCreate(nil, "IpBump" as CFString, callback, &context)
        guard let store else { return }
        let keys = ["State:/Network/Global/IPv4"] as CFArray
        let patterns = ["State:/Network/Service/.*/(IPv4|DNS)", "State:/Network/Interface/.*/Link",
                        "Setup:/Network/Service/.*"] as CFArray
        SCDynamicStoreSetNotificationKeys(store, keys, patterns)
        SCDynamicStoreSetDispatchQueue(store, .main)
    }

    public func stop() {
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
        store = nil
    }

    deinit { stop() }
}
