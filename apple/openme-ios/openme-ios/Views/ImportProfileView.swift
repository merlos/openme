import OpenMeKit
import SwiftUI
import UniformTypeIdentifiers

/// Import profiles by pasting YAML or scanning a QR code.
struct ImportProfileView: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    enum Tab { case yaml, qr }
    @State private var tab: Tab = .yaml

    var body: some View {
        Group {
            switch tab {
            case .yaml: YAMLImportTab(onDone: { dismiss() })
                    .environmentObject(store)
            case .qr:   QRImportTab(onDone: { dismiss() })
                    .environmentObject(store)
            }
        }
        .navigationTitle("Import Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $tab) {
                    Label("YAML", systemImage: "doc.text").tag(Tab.yaml)
                    Label("QR", systemImage: "qrcode.viewfinder").tag(Tab.qr)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }
}

// MARK: - YAML tab

private struct YAMLImportTab: View {
    @EnvironmentObject var store: ProfileStore
    let onDone: () -> Void

    @State private var yamlText      = ""
    @State private var parsedCount   = 0
    @State private var parseError: String?
    @State private var isFileImporter = false

    var body: some View {
        Form {
            Section("Paste YAML") {
                TextEditor(text: $yamlText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 180)
            }
            Section {
                Button { isFileImporter = true } label: {
                    Label("Choose .yaml file…", systemImage: "folder")
                }
            }
            Section {
                if let err = parseError {
                    Text(err).foregroundStyle(.red).font(.caption)
                } else if parsedCount > 0 {
                    Text("\(parsedCount) profile(s) ready to import")
                        .foregroundStyle(.green)
                }
                Button("Import") { doImport() }
                    .disabled(yamlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .fileImporter(
            isPresented: $isFileImporter,
            allowedContentTypes: [.yaml, UTType(filenameExtension: "yaml") ?? .data]
        ) { result in
            if let url = try? result.get(), url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                yamlText = (try? String(contentsOf: url)) ?? yamlText
            }
        }
    }

    private func doImport() {
        parseError = nil
        do {
            let profiles = try ClientConfigParser.parse(yaml: yamlText)
            try store.merge(profiles)
            parsedCount = profiles.count
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onDone() }
        } catch {
            parseError = error.localizedDescription
        }
    }
}

// MARK: - QR tab

private struct QRImportTab: View {
    @EnvironmentObject var store: ProfileStore
    let onDone: () -> Void

    @State private var scannedYAML    = ""
    @State private var scanError: String?
    @State private var imported       = false

    var body: some View {
        VStack(spacing: 0) {
            QRScannerView { yaml in
                guard scannedYAML.isEmpty else { return }
                scannedYAML = yaml
                processScanned(yaml)
            }
            .ignoresSafeArea(edges: .horizontal)

            Group {
                if imported {
                    Label("Profile imported!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding()
                } else if let err = scanError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding()
                } else {
                    Text("Point the camera at a profile QR code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .frame(height: 60)
        }
    }

    private func processScanned(_ yaml: String) {
        do {
            let profiles = try ClientConfigParser.parse(yaml: yaml)
            try store.merge(profiles)
            imported = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onDone() }
        } catch {
            scanError = error.localizedDescription
        }
    }
}
