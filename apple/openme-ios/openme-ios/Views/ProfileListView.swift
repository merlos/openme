import OpenMeKit
import SwiftUI

/// Main screen: list of configured profiles with knock buttons.
struct ProfileListView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var knockManager: KnockManager

    @State private var showImport         = false
    @State private var importInitialTab: ImportProfileView.Tab = .yaml
    @State private var rowKnockStatus: [String: String] = [:]

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
                Menu {
                    Button {
                        importInitialTab = .qr
                        showImport = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                    Button {
                        importInitialTab = .yaml
                        showImport = true
                    } label: {
                        Label("Load Config File", systemImage: "doc.text")
                    }
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showImport) {
            NavigationStack {
                ImportProfileView(initialTab: importInitialTab)
                    .environmentObject(store)
            }
        }
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
                    ProfileRowView(entry: entry, knockManager: knockManager,
                                  knockStatus: rowKnockStatus[entry.name] ?? "")
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
                            switch result {
                            case .success:
                                rowKnockStatus[entry.name] = "✓ Knock sent"
                            case .failure(let e):
                                rowKnockStatus[entry.name] = "✗ \(e)"
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                rowKnockStatus.removeValue(forKey: entry.name)
                            }
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
                Menu {
                    Button {
                        importInitialTab = .qr
                        showImport = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                    Button {
                        importInitialTab = .yaml
                        showImport = true
                    } label: {
                        Label("Load Config File", systemImage: "doc.text")
                    }
                } label: {
                    Text("Import Profile")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

// MARK: - Row

private struct ProfileRowView: View {
    let entry: ProfileEntry
    @ObservedObject var knockManager: KnockManager
    let knockStatus: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).fontWeight(.medium)
                if knockStatus.isEmpty {
                    Text("\(entry.serverHost):\(String(entry.serverUDPPort))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(knockStatus)
                        .font(.caption)
                        .foregroundStyle(knockStatus.hasPrefix("✓") ? .green : .red)
                        .transition(.opacity)
                }
            }

            Spacer()

            // Continuous knock indicator
            if knockManager.continuousKnockProfile == entry.name {
                Image(systemName: "waveform")
                    .foregroundStyle(.green)
                    .symbolEffect(.variableColor.iterative)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: knockStatus)
    }
}
