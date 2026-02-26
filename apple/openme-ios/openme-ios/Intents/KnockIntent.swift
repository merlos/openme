import AppIntents
import Foundation
import OpenMeKit

// MARK: - Knock intent

/// App Intent exposed to Siri / Shortcuts on iOS.
struct KnockIntent: AppIntent {

    static var title: LocalizedStringResource = "Knock Server"
    static var description = IntentDescription(
        "Send a Single Packet Authentication knock to open a firewall port.",
        categoryName: "openme"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Profile", description: "Leave empty for 'default'.")
    var profileName: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let manager = KnockManager()
        manager.store = ProfileStore()
        let name = profileName ?? "default"

        let message: String = try await withCheckedThrowingContinuation { cont in
            manager.knock(profile: name) { result in
                switch result {
                case .success:
                    cont.resume(returning: "Knock sent for profile '\(name)'.")
                case .failure(let msg):
                    cont.resume(throwing: KnockIntentError.failed(profile: name, reason: msg))
                }
            }
        }
        return .result(value: message)
    }
}

// MARK: - Continuous knock intents

struct StartContinuousKnockIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Continuous Knock"
    static var description = IntentDescription(
        "Keep knocking every 20 seconds to maintain firewall access.",
        categoryName: "openme"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Profile")
    var profileName: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let name = profileName ?? "default"
        NotificationCenter.default.post(
            name: .startContinuousKnock,
            object: nil,
            userInfo: ["profile": name]
        )
        return .result(value: "Started continuous knock for '\(name)'.")
    }
}

struct StopContinuousKnockIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Continuous Knock"
    static var description = IntentDescription("Stop the repeating knock timer.", categoryName: "openme")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        NotificationCenter.default.post(name: .stopContinuousKnock, object: nil)
        return .result(value: "Continuous knock stopped.")
    }
}

// MARK: - App Shortcuts (visible in Shortcuts app without configuration)

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

enum KnockIntentError: LocalizedError {
    case failed(profile: String, reason: String)
    var errorDescription: String? {
        if case .failed(let p, let r) = self {
            return "Knock failed for '\(p)': \(r)"
        }
        return "Unknown knock error"
    }
}
