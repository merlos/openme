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

    /// Asks the paired iPhone to re-push the full profile list.
    /// Returns immediately if the watch is not currently reachable.
    func requestSync() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["request": "sync"], replyHandler: nil)
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    /// Called for every `transferUserInfo` payload queued by the iPhone.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    /// Called when the iPhone sends a direct message (watch is reachable/foreground).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    private func handle(_ payload: [String: Any]) {
        guard
            let data = payload["profiles_json"] as? Data,
            let profiles = try? JSONDecoder().decode([String: Profile].self, from: data),
            let store
        else { return }

        Task { @MainActor in
            try? store.replaceAll(profiles)
        }
    }
}
