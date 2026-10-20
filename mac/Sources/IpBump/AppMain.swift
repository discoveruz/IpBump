import AppKit

/// The menu bar app.
@MainActor
enum AppMain {
    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)   // no Dock icon: IpBump lives in the menu bar
        app.run()
        exit(0)
    }
}
