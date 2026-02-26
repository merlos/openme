import Foundation
import OpenMeKit
import WatchConnectivity

/// Receives the profile list pushed from the paired iPhone and writes it into
/// the local `ProfileStore` so the watch always stays in sync.
final class WatchSessionDelegate: NSObject, WCSessionDelegate, ObservableObject {

    private var store: ProfileStore?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Call once the real `ProfileStore` @StateObject is available.
    func bind(store: ProfileStore) {
        guard self.store == nil else { return }
        self.store = store
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    /// Called for every `transferUserInfo` payload queued by the iPhone.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard
            let data = userInfo["profiles_json"] as? Data,
            let profiles = try? JSONDecoder().decode([String: Profile].self, from: data),
            let store
        else { return }

        Task { @MainActor in
            try? store.replaceAll(profiles)
        }
    }
}
