import SwiftUI
import OpenMeKit

@main
struct openme_iosApp: App {

    @StateObject private var store        = ProfileStore()
    @StateObject private var knockManager = KnockManager()
    @StateObject private var biometric    = BiometricGuard()
    /// Keeps the paired Apple Watch in sync with the current profile list.
    @StateObject private var watchSync    = WatchSyncManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if biometric.isUnlocked {
                    ContentView()
                        .environmentObject(store)
                        .environmentObject(knockManager)
                        .onAppear { knockManager.store = store }
                } else {
                    LockView(biometric: biometric)
                }
            }
            .task { await biometric.authenticate() }
            .onAppear { watchSync.bind(store: store) }
        }
    }
}
