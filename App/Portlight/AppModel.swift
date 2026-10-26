import Foundation
import Observation
import PortlightSSH

/// App-wide state: the saved library, open sessions and the lock.
@MainActor
@Observable
final class AppModel {
    let library: Library
    let sessions: SessionManager
    let lock: AppLock
    /// Whether the full-screen terminal is showing.
    var showingTerminal = false
    /// Set when app data couldn't be opened from disk.
    private(set) var startupProblem: String?
    /// Each open session's terminal view, kept for the life of its tab.
    @ObservationIgnored private var terminals: [UUID: TerminalController] = [:]

    init() {
        let storage: LibraryStorage
        var problem: String?
        do {
            storage = try DirectoryStorage.applicationSupport()
        } catch {
            storage = MemoryStorage()
            problem = "Portlight couldn't open its data folder, so changes won't be saved: \(error.localizedDescription)"
        }
        // Read the grace period before the lock exists; everything else
        // waits until after unlocking.
        let probe = Library(storage: storage, secrets: InMemorySecretStore())
        let lock = AppLock(gracePeriod: probe.settings.lockGracePeriod)
        let box = lock.contextBox
        let secrets = KeychainSecretStore(authenticationContext: { box.context })
        // Only with the real data folder: in-memory fallback storage would
        // look like a fresh install and wipe secrets that are still in use.
        if problem == nil {
            Library.clearSecretsLeftFromAnEarlierInstall(storage: storage, secrets: secrets)
        }
        let library = Library(storage: storage, secrets: secrets)
        self.lock = lock
        self.library = library
        self.startupProblem = problem
        self.sessions = SessionManager(library: library) { record in
            guard let handle = try secrets.data(for: SecretAccount.privateKey(record.id)) else {
                throw LibraryError.missingSecret
            }
            return try SecureEnclaveKeys.credential(handle: handle, context: box.context)
        }
    }

    /// Opens a terminal tab for the host and shows the terminal.
    func connect(_ host: SSHHost) {
        sessions.open(host)
        showingTerminal = true
    }

    /// The terminal view for a session, created on first use.
    func terminal(for session: TerminalSession) -> TerminalController {
        if let existing = terminals[session.id] { return existing }
        let controller = TerminalController(session: session, settings: library.settings)
        terminals[session.id] = controller
        return controller
    }

    /// Closes a tab: disconnects and drops its terminal view.
    func close(_ session: TerminalSession) {
        terminals.removeValue(forKey: session.id)?.close()
        sessions.close(session)
        if sessions.sessions.isEmpty { showingTerminal = false }
    }

    /// Creates a Secure Enclave key and adds it to the key list.
    @discardableResult
    func generateSecureEnclaveKey(named name: String) throws -> KeyRecord {
        let (handle, publicKey) = try SecureEnclaveKeys.create(context: lock.contextBox.context)
        let record = try KeyRecord(name: name, publicKey: publicKey, storage: .secureEnclave)
        try library.secrets.set(handle, for: SecretAccount.privateKey(record.id))
        library.addExternalKey(record)
        return record
    }
}
