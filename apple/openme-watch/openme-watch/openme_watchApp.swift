import OpenMeKit
import SwiftUI

@main
struct openme_watchApp: App {
    @StateObject private var store        = ProfileStore()
    @StateObject private var knockManager = KnockManager()
    /// Receives profile updates pushed from the paired iPhone.
    @StateObject private var sessionDelegate = WatchSessionDelegate()

    var body: some Scene {
        WindowGroup {
            WatchProfileListView()
                .environmentObject(store)
                .environmentObject(knockManager)
                .onAppear {
                    knockManager.store = store
                    sessionDelegate.bind(store: store)
                }
        }
    }
}
