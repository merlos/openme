import Combine
import Foundation

/// Observable store that loads and persists `~/.openme/config.yaml`.
/// All writes are performed with 0600 permissions (config contains private keys).
public final class ProfileStore: ObservableObject {

    @Published public var profiles: [ProfileEntry] = []
    @Published public var lastError: String?

    private var allProfiles: [String: Profile] = [:]
    private let configURL: URL

    public init(configURL: URL? = nil) {
        self.configURL = configURL ?? ProfileStore.defaultConfigURL()
        reload()
    }

    // MARK: - Public API

    public func profile(named name: String) -> Profile? {
        allProfiles[name]
    }

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

    /// Merges `newProfiles` into the current config and saves the file.
    public func merge(_ newProfiles: [String: Profile]) throws {
        allProfiles.merge(newProfiles) { _, new in new }
        try save()
        syncEntries()
    }

    public func delete(name: String) throws {
        allProfiles.removeValue(forKey: name)
        try save()
        syncEntries()
    }

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

    /// Replaces all profiles (used by WatchConnectivity sync on watchOS).
    public func replaceAll(_ profiles: [String: Profile]) throws {
        allProfiles = profiles
        try save()
        syncEntries()
    }

    /// Exposes all full profiles for serialisation / watch sync.
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
