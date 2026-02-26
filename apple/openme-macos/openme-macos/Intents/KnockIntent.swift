import AppIntents
import Foundation
import OpenMeKit

// MARK: - Knock intent

/// An App Intent that exposes `openme connect <profile>` to macOS Shortcuts.
///
/// Example use:
///   • Shortcuts automation: "When Focus changes → Knock home"
///   • Menu bar shortcut: ⌘⌃K
struct KnockIntent: AppIntent {

    static var title: LocalizedStringResource = "Knock Server"
    static var description = IntentDescription(
        "Send a Single Packet Authentication knock to open a firewall port.",
        categoryName: "openme"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Profile", description: "The profile name to knock (leave empty for the default profile).")
    var profileName: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let manager = KnockManager()
        let name = profileName ?? "default"

        let message: String = try await withCheckedThrowingContinuation { continuation in
            manager.knock(profile: name) { result in
                switch result {
                case .success:
                    continuation.resume(returning: "Knock sent for profile '\(name)'.")
                case .failure(let msg):
                    continuation.resume(throwing: KnockError.failed(profile: name, reason: msg))
                }
            }
        }
        return .result(value: message)
    }
}

// MARK: - Start / stop continuous knock intents

struct StartContinuousKnockIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Continuous Knock"
    static var description = IntentDescription(
        "Begin knocking every 20 seconds to keep the firewall port open.",
        categoryName: "openme"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Profile")
    var profileName: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let name = profileName ?? "default"
        // Delegate to the shared KnockManager via a notification so the app
        // can update its menu state accordingly.
        NotificationCenter.default.post(
            name: .startContinuousKnock,
            object: nil,
            userInfo: ["profile": name]
        )
        let message = "Started continuous knock for '\(name)'."
        return .result(value: message)
    }
}

struct StopContinuousKnockIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Continuous Knock"
    static var description = IntentDescription(
        "Stop the repeating knock timer.",
        categoryName: "openme"
    )
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        NotificationCenter.default.post(name: .stopContinuousKnock, object: nil)
        return .result(value: "Continuous knock stopped.")
    }
}

// MARK: - Shortcuts App Shortcuts (shown in the Shortcuts app without configuration)

struct OpenMeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: KnockIntent(),
            phrases: [
                "Knock with \(.applicationName)",
                "Open server with \(.applicationName)",
                "Connect \(.applicationName)"
            ],
            shortTitle: "Knock",
            systemImageName: "lock.open.fill"
        )
    }
}

// MARK: - Errors

enum KnockError: LocalizedError {
    case failed(profile: String, reason: String)
    var errorDescription: String? {
        if case .failed(let p, let r) = self {
            return "Knock failed for '\(p)': \(r)"
        }
        return "Unknown error"
    }
}
