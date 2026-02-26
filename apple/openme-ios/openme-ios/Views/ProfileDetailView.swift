import OpenMeKit
import SwiftUI

/// View and edit a single profile.
struct ProfileDetailView: View {
    let profileName: String
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var knockManager: KnockManager
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Profile?
    @State private var isContinuous = false
    @State private var knockStatus  = ""
    @State private var isSaving     = false

    var body: some View {
        Group {
            if var p = draft {
                Form {
                    // ── Status ─────────────────────────────────────────
                    Section {
                        knockControls
                    }

                    // ── Server ─────────────────────────────────────────
                    Section("Server") {
                        LabeledContent("Host") {
                            TextField("hostname or IP", text: Binding(
                                get: { p.serverHost },
                                set: { p.serverHost = $0; draft = p }
                            ))
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                        }
                        LabeledContent("UDP Port") {
                            TextField("7777", value: Binding(
                                get: { Int(p.serverUDPPort) },
                                set: { p.serverUDPPort = UInt16($0); draft = p }
                            ), format: .number)
                            .keyboardType(.numberPad)
                        }
                    }

                    // ── Keys (read-only) ───────────────────────────────
                    Section("Keys") {
                        LabeledContent("Public key") {
                            Text(p.publicKey.isEmpty ? "—" : String(p.publicKey.prefix(20)) + "…")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Private key") {
                            Text(p.privateKey.isEmpty ? "—" : "••••••••")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        NavigationLink("Regenerate Keys") {
                            KeyGenerationView(store: store, prefilledName: profileName)
                        }
                    }

                    // ── Post-knock ─────────────────────────────────────
                    Section("Post-knock URL") {
                        TextField("https://...", text: Binding(
                            get: { p.postKnock },
                            set: { p.postKnock = $0; draft = p }
                        ))
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    }

                    // ── iCloud sync ────────────────────────────────────
                    Section("iCloud Keychain") {
                        NavigationLink("Manage sync") {
                            KeychainSyncView(profileName: profileName)
                        }
                    }
                }
                .navigationTitle(profileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            isSaving = true
                            try? store.update(p)
                            isSaving = false
                        }
                        .disabled(isSaving)
                    }
                }
            } else {
                ContentUnavailableView("Profile not found", systemImage: "questionmark.folder")
            }
        }
        .onAppear { draft = store.profile(named: profileName) }
    }

    // MARK: - Knock controls

    private var knockControls: some View {
        VStack(spacing: 12) {
            if !knockStatus.isEmpty {
                Text(knockStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                knockStatus = "Sending…"
                knockManager.knock(profile: profileName) { result in
                    switch result {
                    case .success:        knockStatus = "✓ Knock sent"
                    case .failure(let e): knockStatus = "✗ \(e)"
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { knockStatus = "" }
                }
            } label: {
                Label("Knock Now", systemImage: "lock.open.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Toggle(isOn: $isContinuous) {
                Label("Continuous knock (every 20 s)", systemImage: "repeat")
                    .font(.subheadline)
            }
            .onChange(of: isContinuous) { _, on in
                if on {
                    knockManager.startContinuousKnock(profile: profileName)
                } else {
                    knockManager.stopContinuousKnock()
                }
            }
            .onAppear { isContinuous = knockManager.continuousKnockProfile == profileName }
        }
        .padding(.vertical, 4)
    }
}
