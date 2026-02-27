import Foundation
import Combine

/// Outcome of a single knock attempt.
public enum KnockResult {
    /// The UDP datagram was accepted by the OS for transmission.
    case success
    /// The knock could not be completed. The associated value is a human-readable
    /// error message suitable for display in the UI.
    case failure(String)
}

/// Orchstrates SPA knock operations for named profiles.
///
/// `KnockManager` is the recommended entry point for SwiftUI apps. It wraps
/// ``KnockService`` with profile resolution, result reporting, and a
/// **continuous knock** mode that automatically re-sends every 20 seconds so
/// firewall rules stay open during long sessions.
///
/// ## Usage
/// ```swift
/// @StateObject private var manager = KnockManager()
///
/// // Required: wire up the profile store
/// manager.store = profileStore
///
/// // Single knock
/// manager.knock(profile: "home") { result in ... }
///
/// // Keep rules alive while an SSH session is open
/// manager.startContinuousKnock(profile: "home")
/// defer { manager.stopContinuousKnock() }
/// ```
///
/// `KnockManager` must be used from the **main actor**. It is thread-safe
/// for observation via `@Published` properties.
@MainActor
public final class KnockManager: ObservableObject {

    // MARK: - Published state

    /// The profile name currently being knocked in continuous mode, or `nil` when idle.
    ///
    /// Bind this to a SwiftUI view to show a spinner or status indicator
    /// while the continuous timer is running.
    @Published public private(set) var continuousKnockProfile: String?

    /// The profile store used to resolve profile names to ``Profile`` values.
    ///
    /// Must be set before calling ``knock(profile:completion:)``
    /// or ``startContinuousKnock(profile:onResult:)``.
    public var store: ProfileStore?

    // MARK: - Init

    public init() {
        observeShortcutsNotifications()
    }

    // MARK: - Continuous knock

    private var continuousTimer: Timer?
    private let continuousInterval: TimeInterval = 20

    /// Starts knocking `profile` immediately and repeats every 20 seconds.
    ///
    /// Calling this while a continuous knock is already running first cancels
    /// the previous session before starting the new one. Use this during
    /// long-lived connections (e.g. SSH, VNC) to keep the firewall rule alive
    /// for the duration of the session.
    ///
    /// - Parameters:
    ///   - profile: Name of the profile to knock (must exist in ``store``).
    ///   - onResult: Optional callback invoked on the main queue after each
    ///     individual knock with its ``KnockResult``.
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

    /// Cancels the running continuous knock timer and clears ``continuousKnockProfile``.
    ///
    /// Safe to call even when no continuous knock is active.
    public func stopContinuousKnock() {
        continuousTimer?.invalidate()
        continuousTimer = nil
        continuousKnockProfile = nil
    }

    // MARK: - Single knock

    /// Sends a single SPA knock for `profile` and reports the outcome.
    ///
    /// Profile credentials are looked up in ``store``. If the store is not set
    /// or the profile is not found, `completion` is called immediately with
    /// ``KnockResult/failure(_:)``.
    ///
    /// - Parameters:
    ///   - profile: Name of the profile to knock.
    ///   - completion: Closure called on the main queue with a ``KnockResult``.
    ///     `.success` means the UDP packet was accepted by the OS for transmission
    ///     (not that the server opened a rule). `.failure` carries a human-readable
    ///     error message.
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
