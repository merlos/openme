import SwiftUI
import OpenMeKit

/// Shows all configured profiles in a list with inline editing and deletion.
struct ProfileManagerView: View {
    @EnvironmentObject var store: ProfileStore
    @State private var selection: String?
    @State private var editingProfile: Profile?
    @State private var errorMessage: String?

    var body: some View {
        HSplitView {
            // ── Left: Profile list ───────────────────────────────────────────
            VStack(spacing: 0) {
                List(store.profiles, id: \.name, selection: $selection) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).fontWeight(.medium)
                        Text("\(entry.serverHost):\(entry.serverUDPPort)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button(role: .destructive) {
                        deleteSelected()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    .help("Remove selected profile")
                    Spacer()
                }
                .padding(6)
            }
            .frame(minWidth: 160, idealWidth: 180)

            // ── Right: Profile detail ────────────────────────────────────────
            if let name = selection, let profile = store.profile(named: name) {
                ProfileDetailView(profile: profile, onSave: { updated in
                    do {
                        try store.update(updated)
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                })
                .frame(minWidth: 280)
            } else {
                VStack {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Select a profile")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .overlay(alignment: .bottom) {
            if let msg = errorMessage {
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(8)
            }
        }
    }

    private func deleteSelected() {
        guard let name = selection else { return }
        do {
            try store.delete(name: name)
            selection = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Profile detail / edit form

private struct ProfileDetailView: View {
    @State var profile: Profile
    let onSave: (Profile) -> Void

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Profile name") {
                    TextField("default", text: $profile.name)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Host") {
                    TextField("server.example.com", text: $profile.serverHost)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("UDP Port") {
                    TextField("7777", value: $profile.serverUDPPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Server public key") {
                    TextField("base64…", text: $profile.serverPubKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }
            }

            Section("Client Keys") {
                LabeledContent("Private key") {
                    SecureField("base64…", text: $profile.privateKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }
                LabeledContent("Public key") {
                    TextField("base64…", text: $profile.publicKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }
            }

            Section("Post-knock command (optional)") {
                TextField("ssh user@server.example.com", text: $profile.postKnock)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .formStyle(.grouped)
        .padding()

        HStack {
            Spacer()
            Button("Save") { onSave(profile) }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }
}
