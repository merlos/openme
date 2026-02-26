import SwiftUI
import OpenMeKit

/// Root navigation container.
struct ContentView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var knockManager: KnockManager

    var body: some View {
        NavigationStack {
            ProfileListView()
        }
    }
}
