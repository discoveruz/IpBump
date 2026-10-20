import AppKit
import IpBumpCore
import IpBumpMac

/// Shows the Settings window (SettingsWindowController).
@MainActor
protocol SettingsPresenter: AnyObject {
    func showSettings()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel!
    var statusItem: StatusItemController!
    var settings: SettingsPresenter?
    var networkWatcher: NetworkChangeWatcher?
    var changeWatcher: LastChangeWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(settings: Wiring.settings(), reader: SystemNetwork(), changer: Wiring.changer(),
                             lastChange: Wiring.lastChange(), notifier: UserNotifier())
        self.model = model
        settings = SettingsWindowController(model: model)
        statusItem = StatusItemController(model: model, openSettings: { [weak self] in self?.openSettings() })
        model.onUpdate = { [weak self] in self?.statusItem.render() }
        model.onNeedsSetup = { [weak self] in self?.openSettings() }

        // The menu bar shows the real address, whoever changed it
        networkWatcher = NetworkChangeWatcher { Task { @MainActor in model.refresh() } }
        // Changes made by an AI agent happen in another process, which leaves a note in IpBump's folder
        changeWatcher = LastChangeWatcher(folder: Paths.appSupport) { Task { @MainActor in model.reportAgentChange() } }
        DistributedNotificationCenter.default().addObserver(forName: AppMain.showSettings, object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.openSettings() }
        }

        statusItem.render()
        if model.settings.service.isEmpty { openSettings() }   // the first start for this user
    }

    /// Opening IpBump from Finder or Spotlight while it runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    func openSettings() { settings?.showSettings() }
}
