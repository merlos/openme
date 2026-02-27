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
            .frame(minWidth: 120, idealWidth: 140, maxWidth: 160)

            // ── Right: Profile detail ────────────────────────────────────────
            if let name = selection, let profile = store.profile(named: name) {
                ProfileDetailView(profile: profile, onSave: { updated in
                    do {
                        // If the user edited the profile name, remove the old
                        // entry before inserting the new one to avoid orphans.
                        if updated.name != name {
                            try store.delete(name: name)
                            selection = updated.name
                        }
                        try store.update(updated)
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                })
                // .id forces SwiftUI to recreate the detail view (and reset its
                // @State) whenever the selection changes, so the form always
                // reflects the currently selected profile.
                .id(name)
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
        .onChange(of: selection) {
            errorMessage = nil
        }
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
            errorMessage = nil
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
        VStack(spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Server ────────────────────────────────────────────────────
                GroupBox("Server") {
                    VStack(alignment: .leading, spacing: 12) {
                        FieldRow(label: "Profile name", hint: "my-server") {
                            TextField("my-server", text: $profile.name)
                        }
                        FieldRow(label: "Host", hint: "server.example.com") {
                            TextField("server.example.com", text: $profile.serverHost)
                        }
                        FieldRow(label: "UDP Port", hint: "54154") {
                            TextField("54154", value: $profile.serverUDPPort, format: .number)
                                .frame(maxWidth: 100)
                        }
                        FieldRow(label: "Server public key", hint: "base64 Curve25519 key") {
                            TextField("base64…", text: $profile.serverPubKey)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)

                // ── Client Keys ───────────────────────────────────────────────
                GroupBox("Client Keys") {
                    VStack(alignment: .leading, spacing: 12) {
                        FieldRow(label: "Private key", hint: "base64 Ed25519 private key") {
                            SecureField("base64…", text: $profile.privateKey)
                                .font(.system(.caption, design: .monospaced))
                        }
                        FieldRow(label: "Public key", hint: "base64 Ed25519 public key") {
                            TextField("base64…", text: $profile.publicKey)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)

                // ── Post-knock ────────────────────────────────────────────────
                GroupBox("Post-knock command (optional)") {
                    FieldRow(label: "Shell command", hint: "open ssh://server.example.com") {
                        TextField("ssh user@server.example.com", text: $profile.postKnock)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            } // ScrollView

            Divider()

            HStack {
                Spacer()
                Button("Save") { onSave(profile) }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        } // VStack
    }
}

// MARK: - FieldRow

/// A label above a field, with an optional greyed-out hint below.
/// The field stretches to fill available width by default.
private struct FieldRow<Field: View>: View {
    let label: String
    let hint: String
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.primary)
            field()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
