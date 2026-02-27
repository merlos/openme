#if os(iOS)
import Foundation
import OpenMeKit
import WatchConnectivity

final class PhoneSessionCoordinator: NSObject, WCSessionDelegate {
    private let store: ProfileStore
    private var cancellable: AnyObject?

    init(store: ProfileStore) {
        self.store = store
        super.init()

        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            pushLatestProfiles()
        }

        // Observe profile changes; post Notification.Name("OpenMeProfilesDidChange") whenever profiles are modified (merge/update/delete/replaceAll)
        cancellable = NotificationCenter.default.addObserver(
            forName: Notification.Name("OpenMeProfilesDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pushLatestProfiles()
        }
    }

    private func profilesPayload() -> [String: Any]? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(store.profilesDictionary) else { return nil }
        return ["profiles_json": data]
    }

    public func pushLatestProfiles() {
        guard let payload = profilesPayload() else { return }
        print("[PhoneWC] Pushing profiles payload to watch")
        do {
            try WCSession.default.updateApplicationContext(payload)
        } catch {
            print("[PhoneWC] Failed to update application context: \(error)")
        }
        WCSession.default.transferUserInfo(payload)
    }

    // MARK: - WCSessionDelegate

    func sessionDidBecomeInactive(_ session: WCSession) {
        // no-op
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // no-op
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        if session.isPaired && session.isWatchAppInstalled {
            print("[PhoneWC] Watch became paired/installed, pushing latest profiles")
            pushLatestProfiles()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[PhoneWC] Session activation failed: \(error)")
        } else {
            print("[PhoneWC] Session activated with state: \(activationState.rawValue)")
            pushLatestProfiles()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let request = message["request"] as? String, request == "sync" {
            print("[PhoneWC] Received sync request message, pushing latest profiles")
            pushLatestProfiles()
        }
    }
}
#else
import Foundation
import OpenMeKit
final class PhoneSessionCoordinator {
    init(store: ProfileStore) {}
    func pushLatestProfiles() {}
}
#endif

