import Foundation

/// A new, empty folder for one test; the system clears its temporary folder on its own.
func temporaryFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IpBumpTests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// Collects what a @Sendable callback was given.
final class Recorder<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []

    func append(_ item: T) {
        lock.lock(); defer { lock.unlock() }
        items.append(item)
    }

    var all: [T] {
        lock.lock(); defer { lock.unlock() }
        return items
    }
}
