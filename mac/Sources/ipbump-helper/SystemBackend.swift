import CBPF
import Foundation
import IpBumpCore
import IpBumpMac

/// What the helper does with a request it has checked: ARP over BPF, settings through networksetup.
struct SystemBackend: HelperBackend {
    let network = SystemNetwork()

    func serviceNames() -> [String] { network.serviceNames() }

    func apply(_ config: IpConfig) throws {
        let currentlyDhcp = network.current(service: config.service)?.dhcp ?? false
        for arguments in NetworkSetup.commands(for: config, currentlyDhcp: currentlyDhcp) {
            let (code, output) = try run(NetworkSetup.path, arguments)
            if let failure = NetworkSetup.failure(exitCode: code, output: output) { throw IpBumpError(failure) }
        }
    }

    func probe(service: String, addresses: [String]) throws -> Set<String> {
        guard let state = network.current(service: service), !state.interface.isEmpty else {
            throw IpBumpError("Network service \"\(service)\" was not found.")
        }
        var mac = [UInt8](repeating: 0, count: 6)
        guard ipb_interface_mac(state.interface, &mac) == 0 else {
            throw IpBumpError("\(state.interface) has no Ethernet address to send ARP requests from.")
        }
        let link = try BPFLink(interface: state.interface)
        let answered = try ARPProbe.run(link: link, ownMAC: mac,
                                        senderIP: ARPProbe.senderIP(current: state.ip, targets: addresses),
                                        targets: addresses.compactMap(IPv4.number))
        return Set(answered.map(IPv4.string))
    }

    /// Arguments go to the program as they are; no shell sees them.
    func run(_ program: String, _ arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let text = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: text, as: UTF8.self))
    }
}
