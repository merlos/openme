import SwiftUI
import OpenMeKit
import UniformTypeIdentifiers

/// Lets the user paste a YAML block (output of `openme add`) or drag-drop a .yaml file
/// to import one or more profiles into the local config.
struct ImportProfileView: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var yamlText: String = ""
    @State private var parsedProfiles: [String: Profile] = [:]
    @State private var parseError: String?
    @State private var importSuccess = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Profile")
                .font(.headline)

            Text("Paste the YAML block printed by `openme add`, or drag a `.yaml` config file onto the text area.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // ── YAML text area ───────────────────────────────────────────────
            TextEditor(text: $yamlText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 200)
                .border(isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor))
                .onDrop(of: [.yaml, .fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }
                .onChange(of: yamlText) {
                    parseError = nil
                    parsedProfiles = [:]
                    importSuccess = false
                }

            // ── Parse preview ────────────────────────────────────────────────
            if !parsedProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Will import:").font(.caption).foregroundStyle(.secondary)
                    ForEach(parsedProfiles.keys.sorted(), id: \.self) { name in
                        Label(name, systemImage: "lock.shield")
                            .font(.caption)
                    }
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }

            if let err = parseError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if importSuccess {
                Label("Profiles imported successfully.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            // ── Buttons ──────────────────────────────────────────────────────
            HStack {
                Button("Paste from Clipboard") {
                    if let str = NSPasteboard.general.string(forType: .string) {
                        yamlText = str
                    }
                }

                Button("Parse") { parseYAML() }
                    .disabled(yamlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Button("Import") {
                    importParsed()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(parsedProfiles.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520, height: 400)
    }

    // MARK: - Helpers

    private func parseYAML() {
        do {
            parsedProfiles = try ClientConfigParser.parse(yaml: yamlText)
            parseError = nil
        } catch {
            parsedProfiles = [:]
            parseError = error.localizedDescription
        }
    }

    private func importParsed() {
        do {
            try store.merge(parsedProfiles)
            importSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            DispatchQueue.main.async { yamlText = text }
        }
        return true
    }
}
