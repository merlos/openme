import OpenMeKit
import SwiftUI
import UniformTypeIdentifiers

/// Main screen: list of configured profiles with knock buttons.
struct ProfileListView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var knockManager: KnockManager

    @State private var showImport         = false
    @State private var importInitialTab: ImportProfileView.Tab = .yaml
    @State private var showAddMenu          = false
    @State private var showFileImporter     = false
    @State private var lastResult: KnockResult?
    @State private var resultProfile        = ""

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
                Button { showAddMenu = true } label: {
                    Label("Add Profile", systemImage: "plus")
                }
            }
        }
        .confirmationDialog("Add Profile", isPresented: $showAddMenu, titleVisibility: .visible) {
            Button("Scan QR Code") {
                importInitialTab = .qr
                showImport = true
            }
            Button("Load Config File") {
                showFileImporter = true
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.yaml, UTType(filenameExtension: "yaml") ?? .data]
        ) { result in
            guard let url = try? result.get(),
                  url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let yaml = try? String(contentsOf: url),
               let profiles = try? ClientConfigParser.parse(yaml: yaml) {
                try? store.merge(profiles)
            }
        }
        .sheet(isPresented: $showImport) {
            NavigationStack {
                ImportProfileView(initialTab: importInitialTab)
                    .environmentObject(store)
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
                    ProfileRowView(entry: entry, knockManager: knockManager)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        try? store.delete(name: entry.name)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        knockManager.knock(profile: entry.name) { result in
                            resultProfile = entry.name
                            lastResult = result
                        }
                    } label: {
                        Label("Knock", systemImage: "lock.open.fill")
                    }
                    .tint(.green)
                }
            }
            .onDelete { idx in
                for i in idx {
                    try? store.delete(name: store.profiles[i].name)
                }
            }
        }
        .refreshable { store.reload() }
        .scrollContentBackground(.hidden)
        .background { AnimatedGradientBackground() }
    }

    private var emptyState: some View {
        ZStack {
            AnimatedGradientBackground()
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
                Button("Import Profile") { showAddMenu = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
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
        }
    }
}
