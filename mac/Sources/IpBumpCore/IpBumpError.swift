import Foundation

/// A problem worth showing to whoever asked for a change: the menu, the Settings window or an AI agent.
/// The message is written for them and passed on as it is.
public struct IpBumpError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var description: String { message }
    public var errorDescription: String? { message }

    /// The menu and an agent may ask at the same moment; one change at a time.
    public static let changeRunning = IpBumpError("Another IP change is still running. Try again in a moment.")
}
