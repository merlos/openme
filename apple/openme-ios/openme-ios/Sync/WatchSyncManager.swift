import Combine
import Foundation
import OpenMeKit
import WatchConnectivity

/// Pushes the full profile list to the paired Apple Watch whenever it changes.
/// Uses `updateApplicationContext` (latest-value delivery, reliable in the simulator)
/// and additionally `sendMessage` when the watch is reachable for instant delivery.
final class WatchSyncManager: NSObject, WCSessionDelegate, ObservableObject {

    private var store: ProfileStore?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            print("[WatchSync] WCSession not supported on this device")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        print("[WatchSync] WCSession activation requested")
    }

    /// Called once the real `ProfileStore` @StateObject is ready.
    func bind(store: ProfileStore) {
        guard self.store == nil else { return }   // bind once
        self.store = store
        print("[WatchSync] Store bound, profile count: \(store.profiles.count)")
        store.$profiles
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] profiles in
                print("[WatchSync] Profiles changed (\(profiles.count) profiles), triggering push")
                self?.push()
            }
            .store(in: &cancellables)

        // Push current state immediately.
        push()
    }

    // MARK: - Private

    private func push() {
        let state = WCSession.default.activationState
        let reachable = WCSession.default.isReachable
        print("[WatchSync] push() — activationState: \(state.rawValue), isReachable: \(reachable)")

        guard
            state == .activated,
            let dict = store?.profilesDictionary,
            let data = try? JSONEncoder().encode(dict)
        else {
            print("[WatchSync] push() aborted — session not activated or encode failed")
            return
        }

        print("[WatchSync] Pushing \(dict.count) profile(s), payload \(data.count) bytes")
        let payload: [String: Any] = ["profiles_json": data]

        // updateApplicationContext: always succeeds when session is activated;
        // delivers the latest snapshot as soon as the watch app wakes —
        // most reliable channel on a real device.
        do {
            try WCSession.default.updateApplicationContext(payload)
            print("[WatchSync] updateApplicationContext succeeded")
        } catch let error as NSError where error.domain == "WCErrorDomain" && error.code == 7006 {
            // WCErrorCodeWatchAppNotInstalled — normal in the simulator when the
            // watch app hasn't been launched yet. sendMessage below will handle it.
            print("[WatchSync] updateApplicationContext skipped — watch app not installed (simulator?)")
        } catch {
            print("[WatchSync] updateApplicationContext error: \(error)")
        }

        // Also send directly when the watch is reachable for instant delivery.
        if reachable {
            print("[WatchSync] Sending via sendMessage (watch reachable)")
            WCSession.default.sendMessage(payload, replyHandler: nil) { error in
                print("[WatchSync] sendMessage error: \(error)")
            }
        }
    }

    // MARK: - WCSessionDelegate (required stubs)

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        print("[WatchSync] activationDidComplete — state: \(activationState.rawValue), error: \(String(describing: error))")
        if activationState == .activated { push() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("[WatchSync] sessionDidBecomeInactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("[WatchSync] sessionDidDeactivate — reactivating")
        WCSession.default.activate()
    }

    /// Watch-initiated sync request via direct message (watch reachable).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        print("[WatchSync] didReceiveMessage: \(message.keys.joined(separator: ", "))")
        if message["request"] as? String == "sync" { push() }
    }

    /// Watch-initiated sync request via userInfo (background/simulator fallback).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        print("[WatchSync] didReceiveUserInfo: \(userInfo.keys.joined(separator: ", "))")
        if userInfo["request"] as? String == "sync" { push() }
    }
}
