import SwiftUI

/// Shows iCloud Keychain sync status for a profile's private key.
struct KeychainSyncView: View {
    let profileName: String

    @State private var isSynced  = false
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("iCloud Keychain", systemImage: "icloud.fill")
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else {
                        Text(isSynced ? "Enabled" : "Disabled")
                            .foregroundStyle(isSynced ? .green : .secondary)
                    }
                }
            } footer: {
                Text("When enabled, the private key for '\(profileName)' is stored in iCloud Keychain and available on all your Apple devices.")
            }

            Section {
                Button(isSynced ? "Disable sync" : "Enable sync") {
                    toggleSync()
                }
                .foregroundStyle(isSynced ? .red : .accentColor)
            }

            if let err = error {
                Section {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStatus() }
    }

    private func loadStatus() async {
        isLoading = true
        let synced = (try? KeychainStore.syncedAccounts()) ?? []
        isSynced  = synced.contains(profileName)
        isLoading = false
    }

    private func toggleSync() {
        isLoading = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Re-store the key with the new sync flag.
                let keyData = try KeychainStore.loadPrivateKey(account: profileName)
                try KeychainStore.storePrivateKey(keyData, account: profileName, syncToiCloud: !isSynced)
                DispatchQueue.main.async {
                    isSynced  = !isSynced
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}
