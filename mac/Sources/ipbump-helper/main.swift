import Foundation
import IpBumpCore
import IpBumpMac

// The root helper, started by launchd. It is the only part of IpBump that sends ARP probes or changes network
// settings; everything else asks it over its socket. launchd daemons are also exempt from local network privacy.
//   ipbump-helper                            serve the socket the rest of IpBump expects
//   ipbump-helper --socket <path>            serve another socket (development)
//   ipbump-helper --probe <service> <ip>...  print the addresses another device answers for

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func serve(_ path: String) -> Never {
    let server = HelperServer(socketPath: path, backend: SystemBackend())
    do { try server.start() } catch { fail("Could not listen on \(path): \(error)") }
    dispatchMain()
}

let usage = "usage: ipbump-helper [--socket <path> | --probe <service> <ip>...]"
let arguments = Array(CommandLine.arguments.dropFirst())
guard geteuid() == 0 else { fail("ipbump-helper must run as root.") }
signal(SIGPIPE, SIG_IGN)   // as well as SO_NOSIGPIPE: a client that hangs up must never stop the daemon

switch arguments.first {
case nil:
    serve(Paths.helperSocket)
case "--socket" where arguments.count == 2:
    serve(arguments[1])
case "--probe" where arguments.count >= 3:
    let backend = SystemBackend()
    let service = arguments[1], addresses = Array(arguments.dropFirst(2))
    do {
        try HelperValidation.validate(.probe(service: service, addresses: addresses), services: backend.serviceNames())
        for ip in try backend.probe(service: service, addresses: addresses).sorted() { print(ip) }
    } catch {
        fail((error as? IpBumpError)?.message ?? "\(error)")
    }
default:
    fail(usage)
}
