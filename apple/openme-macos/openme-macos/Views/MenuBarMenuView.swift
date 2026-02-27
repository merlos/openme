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

    var body: some View {
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
        Button("Website") {
            NSWorkspace.shared.open(URL(string: "https://openme.merlos.org")!)
        }

        Button("Documentation") {
            NSWorkspace.shared.open(URL(string: "https://openme.merlos.org/docs")!)
        }

        Divider()

        Button("Quit openme") {
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
                    showFeedback(for: result, profile: entry.name)
                }
            }

            if isContinuous {
                Button("Stop Continuous Knock") {
                    knockManager.stopContinuousKnock()
                }
                .foregroundStyle(.orange)
            } else {
                Button("Start Continuous Knock") {
                    knockManager.startContinuousKnock(profile: entry.id) { result in
                        showFeedback(for: result, profile: entry.name)
                    }
                }
            }
        }
    }

    // MARK: - Feedback

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
