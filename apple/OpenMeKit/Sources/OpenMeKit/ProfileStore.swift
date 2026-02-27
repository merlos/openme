import Combine
import Foundation

/// Observable store that loads, persists, and exposes client profiles.
///
/// `ProfileStore` reads `config.yaml` on init and whenever ``reload()`` is
/// called. All mutations are written back atomically to the same file with
/// `0600` permissions (the file contains Ed25519 private keys).
///
/// ## Platform storage paths
///
/// | Platform | Default path |
/// |----------|--------------|
/// | **iOS** | `<AppGroup>/Library/Application Support/openme/config.yaml` |
/// | **macOS** | `~/Library/Application Support/openme/config.yaml` |
/// | **watchOS** | `<AppSandbox>/Library/Application Support/openme/config.yaml` |
///
/// On iOS the App Group container (`group.org.merlos.openme`) is used so the
/// main app and its widget extension share the same file without any
/// additional coordination.
///
/// ## Observation
/// ```swift
/// @StateObject private var store = ProfileStore()
///
/// // React to profile changes in SwiftUI
/// ForEach(store.profiles) { entry in
///     Text(entry.name)
/// }
/// ```
public final class ProfileStore: ObservableObject {

    /// Lightweight summaries of all loaded profiles, sorted alphabetically.
    ///
    /// Updated after every successful ``reload()``, ``merge(_:)``,
    /// ``update(_:)``, ``delete(name:)``, and ``replaceAll(_:)``.
    @Published public var profiles: [ProfileEntry] = []
    /// Human-readable description of the last error, or `nil` if the last
    /// operation succeeded. Observe this to surface parse or save errors in UI.
    @Published public var lastError: String?

    private var allProfiles: [String: Profile] = [:]
    private let configURL: URL

    /// Creates a store and immediately loads profiles from `configURL`.
    ///
    /// If `configURL` is `nil` the platform-appropriate default path is used
    /// (see class documentation). Passing a custom URL is useful for testing.
    ///
    /// - Parameter configURL: Override for the config file location. Pass `nil`
    ///   to use the default path for the current platform.
    public init(configURL: URL? = nil) {
        self.configURL = configURL ?? ProfileStore.defaultConfigURL()
        reload()
    }

    // MARK: - Public API

    /// Returns the full ``Profile`` (including private key) for the given name.
    ///
    /// - Parameter name: The profile name as it appears in `config.yaml`.
    /// - Returns: The matching ``Profile``, or `nil` if no profile with that name
    ///   exists in the current in-memory state.
    public func profile(named name: String) -> Profile? {
        allProfiles[name]
    }

    /// Discards the in-memory state and re-reads the config file from disk.
    ///
    /// Call this after the config file may have been modified by an external
    /// process (e.g. `openme add` on the command line). On parse error
    /// ``lastError`` is set and ``profiles`` is left unchanged.
    public func reload() {
        guard let data = try? Data(contentsOf: configURL),
              let yaml = String(data: data, encoding: .utf8) else {
            profiles = []
            return
        }
        do {
            allProfiles = try ClientConfigParser.parse(yaml: yaml)
            syncEntries()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Merges `newProfiles` into the current config and saves to disk.
    ///
    /// Existing profiles with the same name are overwritten; others are preserved.
    /// This is the import operation used when scanning a QR code or receiving
    /// profiles via WatchConnectivity.
    ///
    /// - Parameter newProfiles: Dictionary of profile name → ``Profile`` to add or update.
    /// - Throws: A `Foundation` error if the file cannot be written.
    public func merge(_ newProfiles: [String: Profile]) throws {
        allProfiles.merge(newProfiles) { _, new in new }
        try save()
        syncEntries()
    }

    /// Removes the named profile and saves the updated config to disk.
    ///
    /// - Parameter name: Name of the profile to remove.
    /// - Throws: A `Foundation` error if the updated file cannot be written.
    ///   The in-memory state is updated before the throw so ``profiles`` will
    ///   reflect the deletion even if the write fails.
    public func delete(name: String) throws {
        allProfiles.removeValue(forKey: name)
        try save()
        syncEntries()
    }

    /// Replaces or inserts `profile` and saves the updated config to disk.
    ///
    /// The profile is matched by ``Profile/name``. Use this to edit an existing
    /// profile's connection details or post-knock command.
    ///
    /// - Parameter profile: The updated ``Profile`` value to store.
    /// - Throws: A `Foundation` error if the file cannot be written.
    public func update(_ profile: Profile) throws {
        allProfiles[profile.name] = profile
        try save()
        syncEntries()
    }

    // MARK: - Private

    private func syncEntries() {
        profiles = allProfiles
            .map { ProfileEntry(name: $0.key, serverHost: $0.value.serverHost, serverUDPPort: $0.value.serverUDPPort) }
            .sorted { $0.name < $1.name }
    }

    /// Replaces **all** profiles with `profiles` and saves to disk.
    ///
    /// Used by `WatchConnectivity` synchronisation on watchOS to replace the
    /// entire local config with the version received from the paired iPhone.
    ///
    /// - Parameter profiles: Complete replacement dictionary of name → ``Profile``.
    /// - Throws: A `Foundation` error if the file cannot be written.
    public func replaceAll(_ profiles: [String: Profile]) throws {
        allProfiles = profiles
        try save()
        syncEntries()
    }

    /// All full ``Profile`` values indexed by name.
    ///
    /// Use this when you need access to private key material, for example to
    /// serialise profiles for a WatchConnectivity `transferUserInfo` payload.
    ///
    /// - Warning: The returned dictionary contains Ed25519 private keys.
    ///   Do not log, persist to iCloud, or transmit over unencrypted channels.
    public var profilesDictionary: [String: Profile] { allProfiles }

    private func save() throws {
        let yaml = ClientConfigParser.serialize(profiles: allProfiles)
        guard let data = yaml.data(using: .utf8) else { return }

        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: configURL, options: .atomic)

        #if !os(watchOS)
        // Enforce 0600 — file contains private keys. (watchOS ignores POSIX permissions)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        #endif
    }

    private static func defaultConfigURL() -> URL {
        // On iOS share the file with the widget via the App Group container so
        // that both processes read/write the same config.yaml.
        #if os(iOS)
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.org.merlos.openme") {
            return group
                .appendingPathComponent("Library/Application Support/openme", isDirectory: true)
                .appendingPathComponent("config.yaml")
        }
        #endif
        // macOS (sandboxed) and watchOS fall back to their own Application Support directory.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("openme/config.yaml")
    }
}
