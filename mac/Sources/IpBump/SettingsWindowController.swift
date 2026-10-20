import AppKit
import IpBumpCore
import IpBumpMac
import SwiftUI

/// The one Settings window. Opening it again only brings it to the front.
@MainActor
final class SettingsWindowController: NSObject, SettingsPresenter, NSWindowDelegate {
    let model: AppModel
    var window: NSWindow?
    var firstRun = false

    init(model: AppModel) { self.model = model }

    func showSettings() {
        NSApp.activate()
        if let window {
            bringForward(window)
            return
        }
        firstRun = model.settings.service.isEmpty
        let form = SettingsViewModel(store: Wiring.settings(), reader: SystemNetwork(), changer: Wiring.changer())
        // Small laptop screens get a shorter window; the form scrolls
        let height = min(760, (NSScreen.main?.visibleFrame.height ?? 800) - 40)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "IpBump"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(model: form, height: height))
        window.delegate = self
        form.close = { [weak window] in window?.close() }
        window.center()
        self.window = window
        bringForward(window)
    }

    /// macOS only lets an app take the front when the person just used it. IpBump also opens Settings by itself
    /// (on the first start, at login or from the installer), so the window comes forward regardless.
    func bringForward(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        model.settingsClosed(firstRun: firstRun)
    }
}

/// What the Settings window shows and does. The rules themselves are in SettingsForm.
@MainActor
final class SettingsViewModel: ObservableObject {
    struct AgentRow: Identifiable {
        let agent: Agent
        var connected: Bool
        var id: String { agent.name }
    }

    @Published var form: SettingsForm
    @Published var error: String?
    @Published var problemField: SettingsForm.Field?
    @Published var busy = false
    @Published var agentHint: String?
    @Published var agents: [AgentRow]
    let services: [String]
    var close: () -> Void = {}

    let store: SettingsStore
    let reader: NetworkReader
    let changer: IpChanging
    let savedService: String

    init(store: SettingsStore, reader: NetworkReader, changer: IpChanging) {
        self.store = store
        self.reader = reader
        self.changer = changer
        let saved = store.load()
        savedService = saved.service
        form = SettingsForm.initial(saved: saved, reader: reader)
        services = reader.serviceNames()
        agents = Agent.all(home: FileManager.default.homeDirectoryForCurrentUser, executable: Paths.executable)
            .map { AgentRow(agent: $0, connected: $0.isConnected) }
    }

    var status: String { SettingsForm.statusText(reader.current(service: form.service)) }

    /// A different service is a different network: start from what it uses now.
    func serviceChanged() {
        if form.service != savedService { _ = form.fill(from: reader) }
    }

    func useCurrentValues() {
        error = form.fill(from: reader) ? nil : "Network service not found."
    }

    func save() async {
        error = nil
        let settings: UserSettings
        do {
            settings = try form.validated()
            try store.save(settings)
        } catch let problem as SettingsForm.Problem {
            error = problem.message
            problemField = problem.field
            return
        } catch {
            self.error = error.localizedDescription
            return
        }
        guard SettingsForm.needsApply(settings, live: reader.current(service: settings.service)) else { return close() }

        busy = true
        let changer = changer
        let applied = await Task.detached { Result { try changer.applySettings(settings) } }.value
        busy = false
        switch applied {
        case .success: close()
        case .failure(let failure): error = (failure as? IpBumpError)?.message ?? failure.localizedDescription
        }
    }

    /// Connect and Disconnect act at once, in the agent's own files; Save and Cancel have no part in it.
    func toggle(_ row: AgentRow) {
        error = nil
        agentHint = nil
        do {
            if row.connected {
                try row.agent.disconnect()
                agentHint = "Disconnected. \(row.agent.name) lets go of IpBump when it restarts."
            } else {
                try row.agent.connect()
                agentHint = "Connected. Restart \(row.agent.name) and it can use IpBump."
            }
        } catch {
            self.error = (error as? IpBumpError)?.message ?? error.localizedDescription
        }
        agents = agents.map { AgentRow(agent: $0.agent, connected: $0.agent.isConnected) }
    }
}
