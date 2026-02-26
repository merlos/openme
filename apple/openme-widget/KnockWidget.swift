import AppIntents
import OpenMeKit
import SwiftUI
import WidgetKit

// MARK: - Timeline entry

struct KnockEntry: TimelineEntry {
    let date: Date
    let profiles: [ProfileEntry]
    let lastKnockDate: Date?
}

// MARK: - Provider

struct KnockProvider: AppIntentTimelineProvider {

    typealias Entry  = KnockEntry
    typealias Intent = KnockWidgetConfigIntent

    private var store: ProfileStore { ProfileStore() }

    func placeholder(in context: Context) -> KnockEntry {
        KnockEntry(date: .now, profiles: placeholderProfiles, lastKnockDate: nil)
    }

    func snapshot(for configuration: KnockWidgetConfigIntent, in context: Context) async -> KnockEntry {
        KnockEntry(date: .now, profiles: store.profiles, lastKnockDate: nil)
    }

    func timeline(for configuration: KnockWidgetConfigIntent, in context: Context) async -> Timeline<KnockEntry> {
        let entry = KnockEntry(date: .now, profiles: store.profiles, lastKnockDate: nil)
        // Refresh every 15 minutes so the profile list stays current.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private var placeholderProfiles: [ProfileEntry] {
        [ProfileEntry(name: "home", serverHost: "example.com", serverUDPPort: 7777)]
    }
}

// MARK: - Widget configuration intent

struct KnockWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource       = "openme Knock"
    static var description = IntentDescription("Knock a server from your Home Screen.")
}

// MARK: - Widget view

struct KnockWidgetEntryView: View {
    let entry: KnockEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:  smallView
        case .systemMedium: mediumView
        default:            smallView
        }
    }

    // ── Small: first profile + knock button ─────────────────────────────────
    private var smallView: some View {
        let profile = entry.profiles.first

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.tint)
                Spacer()
                if let d = entry.lastKnockDate {
                    Text(d, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let p = profile {
                Text(p.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(p.serverHost)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(intent: WidgetKnockIntent(profileName: p.name)) {
                    Label("Knock", systemImage: "lock.open.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else {
                Text("No profiles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // ── Medium: list of profiles ─────────────────────────────────────────────
    private var mediumView: some View {
        HStack(spacing: 0) {
            // Left: branding
            VStack {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                Text("openme")
                    .font(.caption.bold())
            }
            .frame(maxHeight: .infinity)
            .padding()
            .background(.tint.opacity(0.1))

            // Right: profile buttons
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.profiles.prefix(3)) { p in
                    Button(intent: WidgetKnockIntent(profileName: p.name)) {
                        HStack {
                            Text(p.name).font(.subheadline.bold()).lineLimit(1)
                            Spacer()
                            Image(systemName: "lock.open.fill")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemBackground).opacity(0.8))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if entry.profiles.isEmpty {
                    Text("Import a profile in the app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Button intent executed from widget

struct WidgetKnockIntent: AppIntent {
    static var title: LocalizedStringResource = "Knock from Widget"
    static var openAppWhenRun = false

    @Parameter(title: "Profile name")
    var profileName: String

    init() { profileName = "default" }
    init(profileName: String) { self.profileName = profileName }

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = KnockManager()
        manager.store = ProfileStore()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            manager.knock(profile: profileName) { result in
                switch result {
                case .success:        cont.resume()
                case .failure(let e): cont.resume(throwing: WidgetKnockError.failed(e))
                }
            }
        }
        return .result()
    }
}

enum WidgetKnockError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case .failed(let e) = self { return e }
        return nil
    }
}

// MARK: - Widget declaration

struct KnockWidget: Widget {
    let kind = "KnockWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: KnockWidgetConfigIntent.self, provider: KnockProvider()) { entry in
            KnockWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("openme Knock")
        .description("Knock a server directly from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
