import OpenMeKit
import SwiftUI

/// Main screen: list of configured profiles with knock buttons.
struct ProfileListView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var knockManager: KnockManager

    @State private var showImport     = false
    @State private var showKeyGen     = false
    @State private var lastResult: KnockResult?
    @State private var resultProfile  = ""

    var body: some View {
        Group {
            if store.profiles.isEmpty {
                emptyState
            } else {
                profileList
            }
        }
        .navigationTitle("openme")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showKeyGen = true } label: {
                    Label("Generate Keys", systemImage: "key.fill")
                }
                Button { showImport = true } label: {
                    Label("Import Profile", systemImage: "qrcode.viewfinder")
                }
            }
        }
        .sheet(isPresented: $showImport) {
            NavigationStack {
                ImportProfileView()
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showKeyGen) {
            NavigationStack {
                KeyGenerationView(store: store)
            }
        }
        .alert(resultTitle, isPresented: .constant(lastResult != nil), actions: {
            Button("OK") { lastResult = nil }
        }, message: {
            if case .failure(let msg) = lastResult {
                Text(msg)
            }
        })
    }

    // MARK: - Subviews

    private var profileList: some View {
        List {
            ForEach(store.profiles) { entry in
                NavigationLink {
                    ProfileDetailView(profileName: entry.name)
                        .environmentObject(store)
                        .environmentObject(knockManager)
                } label: {
                    ProfileRowView(entry: entry, knockManager: knockManager) { result in
                        resultProfile = entry.name
                        lastResult = result
                    }
                }
            }
            .onDelete { idx in
                for i in idx {
                    try? store.delete(name: store.profiles[i].name)
                }
            }
        }
        .refreshable { store.reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No profiles yet")
                .font(.title2)
            Text("Import a profile from a YAML file or QR code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Import Profile") { showImport = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var resultTitle: String {
        switch lastResult {
        case .success:          return "Knock sent"
        case .failure:          return "Knock failed"
        case .none:             return ""
        }
    }
}

// MARK: - Row

private struct ProfileRowView: View {
    let entry: ProfileEntry
    @ObservedObject var knockManager: KnockManager
    let onResult: (KnockResult) -> Void

    @State private var isKnocking = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).fontWeight(.medium)
                Text("\(entry.serverHost):\(entry.serverUDPPort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Continuous knock indicator
            if knockManager.continuousKnockProfile == entry.name {
                Image(systemName: "waveform")
                    .foregroundStyle(.green)
                    .symbolEffect(.variableColor.iterative)
            }

            Button {
                isKnocking = true
                knockManager.knock(profile: entry.name) { result in
                    isKnocking = false
                    onResult(result)
                }
            } label: {
                Image(systemName: isKnocking ? "circle.dotted" : "lock.open.fill")
                    .symbolEffect(.bounce, value: isKnocking)
            }
            .buttonStyle(.borderless)
        }
    }
}
