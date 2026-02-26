import Foundation
import Combine

public enum KnockResult {
    case success
    case failure(String)
}

/// Manages knock operations using the native Swift KnockService.
/// Conforms to ObservableObject so SwiftUI views can react to continuous-knock state.
@MainActor
public final class KnockManager: ObservableObject {

    // MARK: - Published state

    /// The profile name currently being knocked continuously, or nil.
    @Published public private(set) var continuousKnockProfile: String?

    /// Reference to the profile store for resolving profile details.
    public var store: ProfileStore?

    // MARK: - Init

    public init() {
        observeShortcutsNotifications()
    }

    // MARK: - Continuous knock

    private var continuousTimer: Timer?
    private let continuousInterval: TimeInterval = 20

    public func startContinuousKnock(profile: String, onResult: @escaping (KnockResult) -> Void = { _ in }) {
        stopContinuousKnock()
        continuousKnockProfile = profile

        // Knock immediately, then on the timer.
        knock(profile: profile, completion: onResult)
        continuousTimer = Timer.scheduledTimer(withTimeInterval: continuousInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.knock(profile: profile, completion: onResult)
            }
        }
    }

    public func stopContinuousKnock() {
        continuousTimer?.invalidate()
        continuousTimer = nil
        continuousKnockProfile = nil
    }

    // MARK: - Single knock

    /// Sends a native SPA knock for the given profile name.
    public func knock(profile: String, completion: @escaping (KnockResult) -> Void = { _ in }) {
        guard let store else {
            completion(.failure("Profile store not available"))
            return
        }
        guard let p = store.profile(named: profile) else {
            completion(.failure("Profile '\(profile)' not found"))
            return
        }

        KnockService.knock(
            serverHost: p.serverHost,
            serverPort: p.serverUDPPort,
            serverPubKeyBase64: p.serverPubKey,
            clientPrivKeyBase64: p.privateKey
        ) { result in
            switch result {
            case .success:
                completion(.success)
            case .failure(let error):
                completion(.failure(error.localizedDescription))
            }
        }
    }

    // MARK: - Shortcuts notification wiring

    private func observeShortcutsNotifications() {
        NotificationCenter.default.addObserver(
            forName: .startContinuousKnock, object: nil, queue: .main
        ) { [weak self] note in
            guard let name = note.userInfo?["profile"] as? String else { return }
            Task { @MainActor [weak self] in
                self?.startContinuousKnock(profile: name)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .stopContinuousKnock, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopContinuousKnock()
            }
        }
    }
}
