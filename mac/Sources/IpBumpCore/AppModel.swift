import Foundation

/// Notifications, which people can switch off; the menu bar carries failures as well.
public protocol Notifier: Sendable {
    func post(title: String, body: String, isError: Bool)
}

/// What the menu bar app does, without the AppKit parts: changes run off the main thread, the menu bar follows
/// the service's real address, and changes made by AI agents are reported.
@MainActor
public final class AppModel {
    let store: SettingsStore
    let reader: NetworkReader
    let changer: IpChanging
    let lastChange: LastChangeStore
    let notifier: Notifier

    public private(set) var settings: UserSettings
    public private(set) var menu = MenuBarState()
    /// Called after every change to `menu`.
    public var onUpdate: () -> Void = {}
    /// Called when a change is asked for before a service was picked.
    public var onNeedsSetup: () -> Void = {}
    var reported = Date()

    public init(settings: SettingsStore, reader: NetworkReader, changer: IpChanging, lastChange: LastChangeStore,
                notifier: Notifier) {
        store = settings
        self.reader = reader; self.changer = changer; self.lastChange = lastChange; self.notifier = notifier
        self.settings = settings.load()
        refresh()
    }

    /// The menu bar shows the service's real address, whoever changed it.
    public func refresh() {
        menu.setUp = !settings.service.isEmpty
        menu.service = settings.service
        menu.showFullAddress = settings.showFullAddress
        menu.ip = menu.setUp ? reader.current(service: settings.service)?.ip ?? "" : ""
        onUpdate()
    }

    public func reloadSettings() {
        settings = store.load()
        refresh()
    }

    public func changeIp() async {
        guard !settings.service.isEmpty else { return onNeedsSetup() }
        let s = settings, changer = changer
        await run(failed: "Could not change IP") {
            let r = try changer.toFreeAddress(s, source: IpChanger.traySource, progress: { step in
                Task { @MainActor in self.show(progress: step) }
            })
            return ("IP changed", "\(r.service): \(r.oldIp) → \(r.newIp)")
        }
    }

    public func useDhcp() async {
        let s = settings, changer = changer
        await run(failed: "Could not switch to automatic") {
            try changer.useDhcp(s)
            return ("Automatic address", "\(s.service) now gets its address from the network (DHCP).")
        }
    }

    /// Changes made by AI agents happen in other processes, which leave a note in last-change.json.
    public func reportAgentChange() {
        guard let last = lastChange.load(), last.source != IpChanger.traySource, last.at > reported else { return }
        reported = last.at
        menu.problem = nil
        refresh()
        if settings.showNotifications {
            notifier.post(title: "IP changed by \(last.source)", body: "\(last.from) → \(last.to)", isError: false)
        }
    }

    /// The Settings window closed: pick up what it saved.
    public func settingsClosed(firstRun: Bool) {
        menu.problem = nil
        reloadSettings()
        // A crowded menu bar can hide new items behind the notch, so say what to look for
        if firstRun && !settings.service.isEmpty {
            notifier.post(title: "IpBump is ready",
                          body: "Click the address in the menu bar for a new IP, or Option-click it to change right away.",
                          isError: false)
        }
    }

    /// Runs a change off the main thread and reports how it went.
    func run(failed: String, _ change: @escaping @Sendable () throws -> (title: String, body: String)) async {
        if menu.busy { return }
        menu.busy = true
        menu.progress = nil
        onUpdate()

        let outcome = await Task.detached { Result { try change() } }.value
        switch outcome {
        case .success(let done):
            menu.problem = nil
            if settings.showNotifications { notifier.post(title: done.title, body: done.body, isError: false) }
        case .failure(let error):
            let message = (error as? IpBumpError)?.message ?? error.localizedDescription
            menu.problem = "\(failed): \(message)"
            notifier.post(title: failed, body: message, isError: true)
        }
        menu.busy = false
        menu.progress = nil
        refresh()
    }

    func show(progress step: String) {
        guard menu.busy else { return }   // a step that arrives after the change finished
        menu.progress = step
        onUpdate()
    }
}
