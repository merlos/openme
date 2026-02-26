import OpenMeKit
import SwiftUI

/// Generates a new Ed25519 key pair and stores it in the Keychain.
/// Can optionally be pre-filled with a profile name to regenerate keys for an
/// existing profile.
struct KeyGenerationView: View {
    let store: ProfileStore
    var prefilledName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var profileName   = ""
    @State private var syncToiCloud  = false
    @State private var generatedPair: SecureEnclaveKeyGen.KeyPair?
    @State private var error: String?
    @State private var isGenerating  = false

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Profile name", text: $profileName)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }

            Section("iCloud Keychain") {
                Toggle("Sync private key to iCloud", isOn: $syncToiCloud)

                Text("When enabled, the private key is stored in iCloud Keychain and syncs to all your Apple devices signed in with the same Apple ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    generate()
                } label: {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Label("Generate Keys", systemImage: "key.fill")
                    }
                }
                .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

            if let pair = generatedPair {
                Section("Public Key (share with server admin)") {
                    Text(pair.publicKeyBase64)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    ShareLink(item: pair.publicKeyBase64) {
                        Label("Share Public Key", systemImage: "square.and.arrow.up")
                    }
                }
                Section("Next step") {
                    Text("Copy the public key above and provide it to your server admin, or run:\n\nopenme update-pubkey \(profileName) \(pair.publicKeyBase64)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let err = error {
                Section {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .navigationTitle("Generate Keys")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear {
            if let name = prefilledName { profileName = name }
        }
    }

    private func generate() {
        isGenerating = true
        error = nil
        generatedPair = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let pair = try SecureEnclaveKeyGen.generateAndStore(
                    profileName: profileName,
                    syncToiCloud: syncToiCloud
                )

                // Update the profile in the store if it already exists.
                if var profile = store.profile(named: profileName) {
                    profile.privateKey = pair.privateKeyBase64
                    profile.publicKey  = pair.publicKeyBase64
                    try store.update(profile)
                }

                DispatchQueue.main.async {
                    generatedPair = pair
                    isGenerating  = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}
