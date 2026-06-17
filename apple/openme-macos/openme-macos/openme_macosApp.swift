//
//  openme_macosApp.swift
//  openme-macos
//
//  Created by Merlos on 2/26/26.
//

import SwiftUI
import OpenMeKit
import AppKit
import Combine

@main
struct openme_macosApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var knockManager = KnockManager()
    /// Carries the profile name that should be pre-selected when the
    /// Profile Manager window opens via the "Edit…" menu item.
    @StateObject private var profileManagerConfig = ProfileManagerConfig()

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(store)
                .environmentObject(knockManager)
                .onAppear {
                    knockManager.store = store
                }
        } label: {
            // The label view lives for the full app lifetime, making it the
            // right place to observe notifications that need to open windows.
            // (MenuBarMenuView is torn down when the menu closes, so
            // @Environment(\.openWindow) called from there is unreliable.)
            MenuBarLabelView()
                .environmentObject(profileManagerConfig)
        }
        .menuBarExtraStyle(.menu)

        Window("Manage Profiles", id: "profile-manager") {
            ProfileManagerView()
                .environmentObject(store)
                .environmentObject(profileManagerConfig)
                .frame(minWidth: 580, minHeight: 400)
                .onAppear  { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Import Profile", id: "import-profile") {
            ImportProfileView()
                .environmentObject(store)
                .frame(minWidth: 440, minHeight: 360)
                .onAppear  { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// Carries state shared between the persistent menu-bar label view and the
/// Profile Manager window — specifically which profile should be pre-selected
/// when the window is opened via the "Edit…" menu item.
final class ProfileManagerConfig: ObservableObject {
    /// When non-nil, ProfileManagerView should select this profile on appear.
    @Published var pendingSelection: String? = nil
}

/// Persistent status-bar label view that owns the notification observers for
/// opening windows. Because this view is always alive (unlike the menu content
/// which is torn down when the menu closes), `@Environment(\.openWindow)` is
/// reliable here.
private struct MenuBarLabelView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var profileManagerConfig: ProfileManagerConfig

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .onReceive(NotificationCenter.default.publisher(for: .openProfileManager)) { notification in
                // The notification object carries an optional profile name.
                // When present (Edit… menu item), pre-select that profile.
                profileManagerConfig.pendingSelection = notification.object as? String
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "profile-manager")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openImportProfile)) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "import-profile")
            }
    }
}

