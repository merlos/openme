import Combine
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
    @State private var showPrivateKey = false
    @State private var countdown: Int = 20

    var body: some View {
        Group {
            if var p = draft {
                Form {
                    // ── Profile ────────────────────────────────────────
                    Section("Profile") {
                        TextField("Profile name", text: Binding(
                            get: { p.name },
                            set: { p.name = $0; draft = p }
                        ))
                        .autocapitalization(.none)
                    }

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
                            TextField("54154", value: Binding(
                                get: { Int(p.serverUDPPort) },
                                set: { p.serverUDPPort = UInt16($0); draft = p }
                            ), format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                        }
                    }

                    // ── Keys ──────────────────────────────────────────
                    Section("Keys") {
                        LabeledContent("Public key") {
                            TextField("base64 public key", text: Binding(
                                get: { p.publicKey },
                                set: { p.publicKey = $0; draft = p }
                            ))
                            .font(.caption.monospaced())
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        }
                        LabeledContent("Private key") {
                            HStack {
                                if showPrivateKey {
                                    TextField("base64 private key", text: Binding(
                                        get: { p.privateKey },
                                        set: { p.privateKey = $0; draft = p }
                                    ))
                                    .font(.caption.monospaced())
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                } else {
                                    SecureField("private key", text: Binding(
                                        get: { p.privateKey },
                                        set: { p.privateKey = $0; draft = p }
                                    ))
                                    .font(.caption.monospaced())
                                }
                                Button {
                                    showPrivateKey.toggle()
                                } label: {
                                    Image(systemName: showPrivateKey ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
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
                .scrollContentBackground(.hidden)
                .background { AnimatedGradientBackground() }
                .navigationTitle(draft?.name ?? profileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard let p = draft else { return }
                            isSaving = true
                            if p.name != profileName {
                                try? store.delete(name: profileName)
                            }
                            try? store.update(p)
                            isSaving = false
                            if p.name != profileName { dismiss() }
                        }
                        .disabled(isSaving)
                    }
                }
                .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                    guard isContinuous else { return }
                    countdown -= 1
                    if countdown <= 0 { countdown = 20 }
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
            .controlSize(.large)

            Toggle(isOn: $isContinuous) {
                Label("Continuous knock (every 20 s)", systemImage: "repeat")
                    .font(.subheadline)
            }
            .onChange(of: isContinuous) { _, on in
                if on {
                    countdown = 20
                    knockManager.startContinuousKnock(profile: profileName)
                } else {
                    countdown = 20
                    knockManager.stopContinuousKnock()
                }
            }
            .onAppear { isContinuous = knockManager.continuousKnockProfile == profileName }

            if isContinuous {
                Text("Next knock in \(countdown)s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.vertical, 4)
    }
}
