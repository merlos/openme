import OpenMeKit
import SwiftUI

/// Main view for the Apple Watch app: scrollable list of profiles.
struct WatchProfileListView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var knockManager: KnockManager
    @EnvironmentObject var sessionDelegate: WatchSessionDelegate

    @State private var selectedProfile: String?

    var body: some View {
        NavigationStack {
            List {
                if store.profiles.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                        Text("No profiles.\nPull to sync or open the iOS app.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.profiles) { entry in
                        NavigationLink(destination: WatchKnockView(profileName: entry.name)
                            .environmentObject(knockManager)
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).font(.headline)
                                Text(entry.serverHost).font(.caption2).foregroundStyle(.secondary)

                                if knockManager.continuousKnockProfile == entry.name {
                                    Label("Continuous", systemImage: "waveform")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
            .refreshable {
                print("[WatchProfileList] Pull-to-refresh triggered")
                sessionDelegate.requestSync()
                // Give the phone a moment to respond before the spinner disappears
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            .navigationTitle("openme")
        }
    }
}
