import Foundation

/// The networksetup commands that put settings on a network service; the helper runs them as root.
public enum NetworkSetup {
    public static let path = "/usr/sbin/networksetup"

    public static func commands(for c: IpConfig, currentlyDhcp: Bool) -> [[String]] {
        let dnsFromNetwork = ["-setdnsservers", c.service, "Empty"]
        if c.dhcp {
            // Only ask for DHCP when it isn't on already: asking again would renew the lease for nothing
            return (currentlyDhcp ? [] : [["-setdhcp", c.service]]) + [dnsFromNetwork]
        }
        let dns = [c.dns1, c.dns2].filter { !$0.isEmpty }
        return [["-setmanual", c.service, c.ip, c.mask, c.router],
                dns.isEmpty ? dnsFromNetwork : ["-setdnsservers", c.service] + dns]
    }

    /// nil when the command worked. networksetup can print an error and still exit with 0, so its text counts too.
    public static func failure(exitCode: Int32, output: String) -> String? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let reportsError = text.contains("Error") || text.contains("is not a recognized network service")
        if exitCode == 0 && !reportsError { return nil }
        return text.isEmpty ? "networksetup failed (\(exitCode))" : text
    }
}
