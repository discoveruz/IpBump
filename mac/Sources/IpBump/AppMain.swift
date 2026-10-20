import AppKit

/// The menu bar app.
@MainActor
enum AppMain {
    /// Starting IpBump again asks the copy already running to open Settings.
    static let showSettings = Notification.Name("io.github.discoveruz.ipbump.showSettings")

    static func run() -> Never {
        // One menu bar item per user. A build outside IpBump.app has no bundle id and skips this
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
            DistributedNotificationCenter.default().postNotificationName(showSettings, object: nil, userInfo: nil,
                                                                         deliverImmediately: true)
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // no Dock icon: IpBump lives in the menu bar
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }
}
