import SwiftUI
import OpenMeKit
import AppKit

/// The SwiftUI content shown inside the `MenuBarExtra` menu.
struct MenuBarMenuView: View {

    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var knockManager: KnockManager

    // Last feedback message shown briefly at the top of the menu.
    @State private var feedbackMessage: String? = nil
    @State private var feedbackTimer: Timer? = nil

    // Tracks which profiles have already had their post-knock action run during
    // the current continuous knock session. Cleared when continuous knock stops.
    @State private var continuousPostKnockFired: Set<String> = []

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1-dev"
    }

    var body: some View {
        // ── App name & version (non-interactive header) ───────────────────
        Text("OpenMe \(appVersion)")
            .foregroundStyle(.secondary)
            .font(.caption)

        Divider()

        // ── Per-profile knock actions ─────────────────────────────────────
        if store.profiles.isEmpty {
            Text("No profiles configured")
                .foregroundStyle(.secondary)
        } else {
            ForEach(store.profiles) { entry in
                profileMenu(for: entry)
            }
        }

        Divider()

        // ── Continuous knock controls ─────────────────────────────────────
        if let active = knockManager.continuousKnockProfile {
            Button("Stop Continuous Knock (\(active))") {
                knockManager.stopContinuousKnock()
            }
            .foregroundStyle(.orange)
        }

        // ── Feedback banner ───────────────────────────────────────────────
        if let msg = feedbackMessage {
            Text(msg)
                .foregroundStyle(.secondary)
                .font(.caption)
        }

        Divider()

        // ── Management actions ────────────────────────────────────────────
        // openWindow(id:) is unreliable inside a .menu-style MenuBarExtra because
        // the menu view is torn down before the action fires. We post notifications
        // instead; openme_macosApp observes them and calls openWindow from a
        // stable Scene context.
        Button("Manage Profiles…") {
            NotificationCenter.default.post(name: .openProfileManager, object: nil)
        }

        Button("Import Profile…") {
            NotificationCenter.default.post(name: .openImportProfile, object: nil)
        }

        Divider()

        // ── Links ─────────────────────────────────────────────────────────
        Button("openme.merlos.org") {
            NSWorkspace.shared.open(URL(string: "https://openme.merlos.org")!)
        }

        Button("OpenMe Docs") {
            NSWorkspace.shared.open(URL(string: "https://openme.merlos.org/docs")!)
        }

        Divider()

        Button("Quit OpenMe") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Per-profile submenu

    @ViewBuilder
    private func profileMenu(for entry: ProfileEntry) -> some View {
        let isContinuous = knockManager.continuousKnockProfile == entry.id

        Menu(entry.name) {
            Button("Knock") {
                knockManager.knock(profile: entry.id) { result in
                    handleKnockResult(result, entry: entry)
                }
            }

            if isContinuous {
                Button("Stop Continuous Knock") {
                    continuousPostKnockFired.remove(entry.id)
                    knockManager.stopContinuousKnock()
                }
                .foregroundStyle(.orange)
            } else {
                Button("Start Continuous Knock") {
                    continuousPostKnockFired.remove(entry.id)
                    knockManager.startContinuousKnock(profile: entry.id) { result in
                        handleKnockResult(result, entry: entry, isContinuous: true)
                    }
                }
            }

            Divider()

            Button("Edit…") {
                NotificationCenter.default.post(
                    name: .openProfileManager,
                    object: entry.id
                )
            }

            Button("Delete…") {
                confirmDelete(entry: entry)
            }
        }
    }

    // MARK: - Delete confirmation

    /// Shows a modal NSAlert asking the user to confirm deletion of `entry`.
    /// NSAlert is used instead of SwiftUI confirmationDialog because the menu
    /// view is torn down as soon as a menu item is selected, which prevents
    /// SwiftUI sheet/alert modifiers from presenting reliably.
    private func confirmDelete(entry: ProfileEntry) {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(entry.name)\"?"
        alert.informativeText = "This profile will be permanently removed. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        // Make Delete the destructive (first) button red.
        alert.buttons.first?.hasDestructiveAction = true

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            do {
                try store.delete(name: entry.id)
            } catch {
                let err = NSAlert()
                err.messageText = "Could not delete profile"
                err.informativeText = error.localizedDescription
                err.alertStyle = .critical
                err.runModal()
            }
        }
    }

    // MARK: - Feedback

    private func handleKnockResult(_ result: KnockResult, entry: ProfileEntry, isContinuous: Bool = false) {
        switch result {
        case .failure(let msg):
            showFeedbackText("✗ \(entry.name): \(msg)")

        case .success:
            guard let profile = store.profile(named: entry.id) else {
                showFeedbackText("✓ Knocked \(entry.name)")
                return
            }

            let action = profile.postKnock.trimmingCharacters(in: .whitespacesAndNewlines)

            // In continuous mode only run the post-knock action on the first
            // successful knock; subsequent re-knocks just refresh the firewall rule.
            let shouldRunAction = !action.isEmpty &&
                (!isContinuous || !continuousPostKnockFired.contains(entry.id))

            guard shouldRunAction else {
                showFeedbackText("✓ Knocked \(entry.name)")
                return
            }

            if isContinuous {
                continuousPostKnockFired.insert(entry.id)
            }

            switch runPostKnockAction(action) {
            case .success:
                showFeedbackText("✓ Knocked \(entry.name) • post-knock launched")
            case .failure(let err):
                let msg = err.localizedDescription
                print("[OpenMe] post-knock failed for '\(entry.name)': \(msg)")
                showFeedbackText("✓ Knocked \(entry.name) • post-knock failed: \(msg)")
            }
        }
    }

    private func showFeedbackText(_ text: String) {
        feedbackTimer?.invalidate()
        feedbackMessage = text
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
            Task { @MainActor in
                self.feedbackMessage = nil
            }
        }
    }

    /// Opens a URL after a successful knock using the default macOS handler.
    ///
    /// Supported schemes include anything registered with macOS — for example:
    /// `ssh://`, `http://`, `https://`, `vnc://`, `rdp://`, `ftp://`.
    ///
    /// Returns a failure if no application is registered for the scheme or if
    /// `NSWorkspace` cannot open the URL.
    private func runPostKnockAction(_ action: String) -> Result<Void, PostKnockError> {
        guard let url = URL(string: action),
              let scheme = url.scheme,
              !scheme.isEmpty else {
            return .failure(PostKnockError("'\(action)' is not a valid URL. Use a URL scheme such as ssh://, https://, or vnc://."))
        }

        if NSWorkspace.shared.urlForApplication(toOpen: url) == nil {
            return .failure(PostKnockError("No app is registered for the '\(scheme)://' URL scheme."))
        }
        guard NSWorkspace.shared.open(url) else {
            return .failure(PostKnockError("Could not open URL: \(action)"))
        }
        return .success(())
    }

    private func showFeedback(for result: KnockResult, profile: String) {
        feedbackTimer?.invalidate()
        switch result {
        case .success:
            feedbackMessage = "✓ Knocked \(profile)"
        case .failure(let msg):
            feedbackMessage = "✗ \(profile): \(msg)"
        }
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
            Task { @MainActor in
                self.feedbackMessage = nil
            }
        }
    }
}

// MARK: - PostKnockError

/// Lightweight `Error` wrapper for post-knock action failures.
/// Used as the `Failure` type in `Result<Void, PostKnockError>` so that
/// `Result` satisfies the `Error`-conforming constraint on its `Failure` type.
private struct PostKnockError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
