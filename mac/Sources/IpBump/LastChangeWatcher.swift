import Foundation

/// Watches IpBump's folder, where an MCP server or the hook leaves last-change.json after changing the IP.
final class LastChangeWatcher {
    private let source: DispatchSourceFileSystemObject?

    init(folder: URL, onChange: @escaping @Sendable () -> Void) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            source = nil
            return
        }
        // A file moved into place counts as a write to the folder
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    deinit { source?.cancel() }
}
