//
//  openme_macosApp.swift
//  openme-macos
//
//  Created by Merlos on 2/26/26.
//

import SwiftUI
import OpenMeKit

@main
struct openme_macosApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var knockManager = KnockManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(store)
                .environmentObject(knockManager)
                .onAppear {
                    knockManager.store = store
                }
        } label: {
            Image(systemName: "lock.shield")
        }
        .menuBarExtraStyle(.menu)

        Window("Manage Profiles", id: "profile-manager") {
            ProfileManagerView()
                .environmentObject(store)
                .frame(minWidth: 580, minHeight: 400)
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Import Profile", id: "import-profile") {
            ImportProfileView()
                .environmentObject(store)
                .frame(minWidth: 440, minHeight: 360)
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
