import AppKit

/// macOS has no list of installed apps to remove IpBump from, so Settings offers it.
@MainActor
enum Uninstaller {
    /// Only an installed IpBump.app carries the script; a debug build has nothing to uninstall.
    static var script: String? { Bundle.main.path(forResource: "uninstall", ofType: "sh") }
    static var available: Bool { script != nil }

    static func run() {
        guard let script else { return }
        let alert = NSAlert()
        alert.messageText = "Uninstall IpBump?"
        alert.informativeText = "This removes IpBump and its helper. Your network settings, your AI agents' "
            + "configuration and your IpBump settings stay as they are."
        alert.addButton(withTitle: "Uninstall").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // macOS asks for an administrator's password. The script removes this app too, which then quits
        let path = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script quoted form of \"\(path)\" with administrator privileges")?
            .executeAndReturnError(&error)
        if let error, error[NSAppleScript.errorNumber] as? Int != -128 {   // -128: the password prompt was cancelled
            let failed = NSAlert()
            failed.messageText = "IpBump could not be uninstalled"
            failed.informativeText = error[NSAppleScript.errorMessage] as? String ?? ""
            failed.runModal()
        }
    }
}
