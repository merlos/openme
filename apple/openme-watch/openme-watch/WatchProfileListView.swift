import OpenMeKit
import SwiftUI

/// Main view for the Apple Watch app: scrollable list of profiles.
struct WatchProfileListView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var knockManager: KnockManager

    @State private var selectedProfile: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.profiles.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                        Text("No profiles.\nOpen the iOS app to import.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    List(store.profiles) { entry in
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
            .navigationTitle("openme")
        }
    }
}
