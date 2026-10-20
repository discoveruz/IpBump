import Foundation

/// Who changed the IP last. Written after every change, so the menu bar app can report changes made by an AI agent.
public struct LastChange: Codable, Equatable, Sendable {
    public let at: Date
    public let from: String
    public let to: String
    public let source: String

    public init(at: Date, from: String, to: String, source: String) {
        self.at = at; self.from = from; self.to = to; self.source = source
    }
}

public struct LastChangeStore: Sendable {
    public static let fileName = "last-change.json"
    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    var file: URL { folder.appendingPathComponent(Self.fileName) }

    public func load() -> LastChange? {
        guard let data = try? Data(contentsOf: file) else { return nil }   // not written yet
        return try? JSONDecoder().decode(LastChange.self, from: data)
    }

    public func save(_ change: LastChange) {
        let aside = folder.appendingPathComponent(Self.fileName + ".tmp")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Written aside and moved into place, so the menu bar app never reads half a file
            try JSONEncoder().encode(change).write(to: aside)
            if rename(aside.path, file.path) != 0 { try? FileManager.default.removeItem(at: aside) }
        } catch {
            // Only a note for the menu bar; the IP change itself already succeeded
        }
    }
}
