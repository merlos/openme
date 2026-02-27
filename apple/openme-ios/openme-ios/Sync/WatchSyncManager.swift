import Combine
import Foundation
import OpenMeKit
import WatchConnectivity

/// Pushes the full profile list to the paired Apple Watch whenever it changes.
/// Uses `WCSession.transferUserInfo` so delivery is guaranteed even when the
/// watch is not currently reachable.
final class WatchSyncManager: NSObject, WCSessionDelegate, ObservableObject {

    private var store: ProfileStore?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Called once the real `ProfileStore` @StateObject is ready.
    func bind(store: ProfileStore) {
        guard self.store == nil else { return }   // bind once
        self.store = store
        store.$profiles
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.push() }
            .store(in: &cancellables)

        // Push current state immediately.
        push()
    }

    // MARK: - Private

    private func push() {
        guard
            WCSession.default.activationState == .activated,
            WCSession.default.isWatchAppInstalled,
            let dict = store?.profilesDictionary,
            let data = try? JSONEncoder().encode(dict)
        else { return }

        let payload: [String: Any] = ["profiles_json": data]

        if WCSession.default.isReachable {
            // Watch is in the foreground — deliver immediately.
            WCSession.default.sendMessage(payload, replyHandler: nil)
        } else {
            // Watch is not reachable — queue for guaranteed background delivery.
            WCSession.default.transferUserInfo(payload)
        }
    }

    // MARK: - WCSessionDelegate (required stubs)

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated { push() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after a watch switch.
        WCSession.default.activate()
    }

    /// Watch-initiated sync request: re-push the current profile list.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["request"] as? String == "sync" { push() }
    }
}
