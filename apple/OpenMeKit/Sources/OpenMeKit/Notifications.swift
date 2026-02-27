import Foundation

// MARK: - Shared notification names

/// Notification names used to bridge Apple Intents (Shortcuts, Siri) to
/// ``KnockManager`` without creating a direct import dependency.
///
/// The intended posting pattern is:
/// ```swift
/// NotificationCenter.default.post(
///     name: .startContinuousKnock,
///     object: nil,
///     userInfo: ["profile": "home"]
/// )
/// ```
public extension Notification.Name {
    /// Instructs ``KnockManager`` to begin continuous knocking for a profile.
    ///
    /// **userInfo keys:**
    /// - `"profile"` (`String`): Name of the profile to knock. Required.
    static let startContinuousKnock = Notification.Name("org.merlos.openme.startContinuousKnock")

    /// Instructs ``KnockManager`` to cancel the active continuous knock timer.
    ///
    /// No `userInfo` payload required.
    static let stopContinuousKnock  = Notification.Name("org.merlos.openme.stopContinuousKnock")

    /// Instructs the app to present the Profile Manager window / sheet.
    ///
    /// No `userInfo` payload required.
    static let openProfileManager   = Notification.Name("org.merlos.openme.openProfileManager")

    /// Instructs the app to present the Import Profile window / sheet.
    ///
    /// No `userInfo` payload required.
    static let openImportProfile    = Notification.Name("org.merlos.openme.openImportProfile")
}
