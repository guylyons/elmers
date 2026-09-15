import Foundation

public struct Archive: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    private struct Envelope: Codable { var version: Int; var history: History }
    public enum ArchiveError: LocalizedError {
        case unsupportedVersion(Int)
        public var errorDescription: String? { "This history archive was created by a newer version of Elmers." }
    }
    public func load() throws -> History {
        guard FileManager.default.fileExists(atPath: url.path) else { return History() }
        let envelope = try PropertyListDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard envelope.version == 1 else { throw ArchiveError.unsupportedVersion(envelope.version) }
        return envelope.history
    }
    public func save(_ history: History) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let data = try encoder.encode(Envelope(version: 1, history: history))
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
