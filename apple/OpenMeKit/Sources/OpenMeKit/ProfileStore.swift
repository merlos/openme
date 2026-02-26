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

    private func save() throws {
        let yaml = ClientConfigParser.serialize(profiles: allProfiles)
        guard let data = yaml.data(using: .utf8) else { return }

        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])
        try data.write(to: configURL, options: .atomic)

        // Enforce 0600 — file contains private keys.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private static func defaultConfigURL() -> URL {
        // Sandboxed: ~/Library/Containers/<bundle-id>/Data/Library/Application Support/openme/config.yaml
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("openme/config.yaml")
    }
}
