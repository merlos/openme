import Foundation
import OpenMeKit
import WatchConnectivity

/// Receives the profile list pushed from the paired iPhone and writes it into
/// the local `ProfileStore` so the watch always stays in sync.
final class WatchSessionDelegate: NSObject, WCSessionDelegate, ObservableObject {

    private var store: ProfileStore?

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            print("[WatchDelegate] WCSession not supported")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        print("[WatchDelegate] WCSession activation requested")
    }

    /// Call once the real `ProfileStore` @StateObject is available.
    func bind(store: ProfileStore) {
        guard self.store == nil else { return }
        self.store = store
        print("[WatchDelegate] Store bound")

        // Apply whatever the iPhone already stored in the application context.
        // This runs after the store is ready, so handle() can actually save the data.
        let ctx = WCSession.default.receivedApplicationContext
        print("[WatchDelegate] Checking receivedApplicationContext after bind — keys: \(ctx.keys.joined(separator: ", "))")
        if !ctx.isEmpty {
            handle(ctx)
        } else {
            // Nothing cached yet — ask the phone for a fresh push.
            requestSync()
        }
    }

    /// Asks the paired iPhone to re-push the full profile list.
    func requestSync() {
        let reachable = WCSession.default.isReachable
        print("[WatchDelegate] requestSync — isReachable: \(reachable)")

        // If the phone is reachable, ask it to push fresh data immediately.
        if reachable {
            print("[WatchDelegate] Sending sync request via sendMessage")
            WCSession.default.sendMessage(["request": "sync"], replyHandler: nil)
            return
        }

        // Not reachable — queue a sync request via transferUserInfo so the
        // phone handles it the next time it processes the queue.
        print("[WatchDelegate] Not reachable, queuing sync request via transferUserInfo")
        WCSession.default.transferUserInfo(["request": "sync"])
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        print("[WatchDelegate] activationDidComplete — state: \(activationState.rawValue), error: \(String(describing: error))")
        // bind() hasn't been called yet at this point — defer data handling to bind().
    }

    /// Called when the iPhone updates its application context.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("[WatchDelegate] didReceiveApplicationContext keys: \(applicationContext.keys.joined(separator: ", "))")
        handle(applicationContext)
    }

    /// Called for every `transferUserInfo` payload queued by the iPhone.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        print("[WatchDelegate] didReceiveUserInfo keys: \(userInfo.keys.joined(separator: ", "))")
        handle(userInfo)
    }

    /// Called when the iPhone sends a direct message (watch is reachable/foreground).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        print("[WatchDelegate] didReceiveMessage keys: \(message.keys.joined(separator: ", "))")
        handle(message)
    }

    private func handle(_ payload: [String: Any]) {
        guard
            let data = payload["profiles_json"] as? Data,
            let profiles = try? JSONDecoder().decode([String: Profile].self, from: data),
            let store
        else {
            if payload["profiles_json"] != nil {
                print("[WatchDelegate] handle() — failed to decode profiles_json")
            }
            return
        }
        print("[WatchDelegate] Decoded \(profiles.count) profile(s), storing")
        Task { @MainActor in
            try? store.replaceAll(profiles)
            print("[WatchDelegate] Store updated with \(profiles.count) profile(s)")
        }
    }
}
