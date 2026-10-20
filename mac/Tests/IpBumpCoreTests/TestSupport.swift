import Foundation

/// A new, empty folder for one test; the system clears its temporary folder on its own.
func temporaryFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IpBumpTests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}
