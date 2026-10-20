import AppKit
import IpBumpCore

/// The address in the menu bar. Click: the menu. Option-click: a new address right away.
@MainActor
final class StatusItemController: NSObject {
    let model: AppModel
    let openSettings: () -> Void
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    /// The menu's first line: the address, or why the last change failed. It wraps rather than widen the menu.
    let statusLine = NSTextField(wrappingLabelWithString: "")
    let statusView = NSView()

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.imagePosition = .imageLeading
            // Digits of equal width, so the item doesn't jiggle as the address changes
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }

        statusLine.font = NSFont.menuFont(ofSize: 0)
        statusLine.textColor = .secondaryLabelColor
        statusLine.maximumNumberOfLines = 0
        statusView.addSubview(statusLine)
        let first = NSMenuItem()
        first.view = statusView
        menu.addItem(first)
        menu.addItem(.separator())
        menu.addItem(entry("Change IP now", #selector(changeIp)))
        menu.addItem(entry("Switch back to automatic (DHCP)", #selector(useDhcp)))
        menu.addItem(.separator())
        menu.addItem(entry("Settings…", #selector(settings), key: ","))
        menu.addItem(entry("Quit IpBump", #selector(quit), key: "q"))
    }

    func render() {
        let state = model.menu
        guard let button = item.button else { return }
        button.title = state.title
        button.image = state.showsWarning
            ? NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "The last change failed")
            : nil
        button.toolTip = state.tooltip

        statusLine.stringValue = state.statusLine
        let width: CGFloat = 280
        let height = ceil(statusLine.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height)
        statusLine.frame = NSRect(x: 14, y: 3, width: width, height: height)
        statusView.frame = NSRect(x: 0, y: 0, width: width + 28, height: height + 6)
    }

    @objc func clicked() {
        if let event = NSApp.currentEvent, event.type == .leftMouseDown, event.modifierFlags.contains(.option) {
            Task { await model.changeIp() }
            return
        }
        render()
        // Attached only while it shows, so the button's own action keeps getting the clicks
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc func changeIp() { Task { await model.changeIp() } }

    @objc func useDhcp() { Task { await model.useDhcp() } }

    @objc func settings() { openSettings() }

    @objc func quit() { NSApp.terminate(nil) }   // the helper keeps running

    func entry(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }
}
