import Foundation

// MARK: - Shared notification names

/// Notification names used to bridge App Intents → KnockManager across the app.
public extension Notification.Name {
    /// Post with `userInfo["profile": String]` to start continuous knocking.
    static let startContinuousKnock = Notification.Name("org.merlos.openme.startContinuousKnock")
    /// Post to stop the running continuous knock timer.
    static let stopContinuousKnock  = Notification.Name("org.merlos.openme.stopContinuousKnock")
    /// Post to open the Profile Manager window.
    static let openProfileManager   = Notification.Name("org.merlos.openme.openProfileManager")
    /// Post to open the Import Profile window.
    static let openImportProfile    = Notification.Name("org.merlos.openme.openImportProfile")
}
