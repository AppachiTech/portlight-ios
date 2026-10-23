import Foundation

/// Where the library's JSON documents (hosts, keys, known hosts, settings)
/// are kept. Secrets never go here; they go to a `SecretStore`.
public protocol LibraryStorage: Sendable {
    func read(_ name: String) throws -> Data?
    func write(_ data: Data, name: String) throws
}

/// Files in a directory, written atomically. On iOS the files get complete
/// data protection, so they are unreadable while the phone is locked.
public struct DirectoryStorage: LibraryStorage {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `Application Support/Portlight`.
    public static func applicationSupport() throws -> DirectoryStorage {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return try DirectoryStorage(directory: base.appendingPathComponent("Portlight", isDirectory: true))
    }

    public func read(_ name: String) throws -> Data? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func write(_ data: Data, name: String) throws {
        #if os(iOS)
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        #endif
    }
}

public final class MemoryStorage: LibraryStorage, @unchecked Sendable {
    private var files: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func read(_ name: String) throws -> Data? { lock.withLock { files[name] } }
    public func write(_ data: Data, name: String) throws { lock.withLock { files[name] = data } }
}
