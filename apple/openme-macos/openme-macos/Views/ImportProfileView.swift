import SwiftUI
import OpenMeKit
import UniformTypeIdentifiers
import AppKit

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
            // YAMLTextEditor is an NSViewRepresentable wrapper around NSTextView
            // that intercepts file drops at the AppKit level. Plain TextEditor
            // cannot be used here because NSTextView handles Finder file drops
            // internally (inserting the file path) before SwiftUI's .onDrop
            // ever fires.
            YAMLTextEditor(
                text: $yamlText,
                isDropTargeted: $isDropTargeted,
                onFileDrop: { content in
                    yamlText = content
                }
            )
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: 200)
            .border(isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor))
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
}

// MARK: - YAMLTextEditor

/// A SwiftUI-compatible text editor backed by `NSTextView` that intercepts
/// file drops at the AppKit level.
///
/// `TextEditor` cannot be used for this purpose because `NSTextView` handles
/// drops from Finder by inserting the file path as plain text, completely
/// bypassing SwiftUI's `.onDrop` modifier. This wrapper subclasses `NSTextView`
/// to override `draggingEntered(_:)` and `performDragOperation(_:)` so that
/// dropped files are read and their contents placed in the editor instead.
private struct YAMLTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isDropTargeted: Bool
    var onFileDrop: (String) -> Void
    var font: NSFont = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FileDropTextView()
        textView.onFileDrop = onFileDrop
        textView.onDropTargetChanged = { targeted in
            DispatchQueue.main.async { isDropTargeted = targeted }
        }
        textView.isEditable = true
        textView.isRichText = false
        textView.font = font
        textView.delegate = context.coordinator
        textView.string = text
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only update if the binding changed externally (e.g. "Paste from Clipboard"),
        // to avoid clobbering the cursor position while the user is typing.
        if textView.string != text {
            textView.string = text
        }
        textView.font = font
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: YAMLTextEditor
        init(_ parent: YAMLTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

extension YAMLTextEditor {
    /// Applies a monospaced font to the editor.
    func font(_ font: NSFont) -> YAMLTextEditor {
        var copy = self
        copy.font = font
        return copy
    }
}

// MARK: - FileDropTextView

/// `NSTextView` subclass that intercepts file drops and calls `onFileDrop`
/// with the file contents instead of inserting the file path.
private final class FileDropTextView: NSTextView {
    var onFileDrop: ((String) -> Void)?
    var onDropTargetChanged: ((Bool) -> Void)?

    private static let fileTypes = [UTType.fileURL.identifier]

    // MARK: NSDraggingDestination overrides

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if fileURL(from: sender) != nil {
            onDropTargetChanged?(true)
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDropTargetChanged?(false)
        super.draggingExited(sender)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDropTargetChanged?(false)
        super.draggingEnded(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = fileURL(from: sender),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            DispatchQueue.main.async { self.onFileDrop?(content) }
            return true
        }
        return super.performDragOperation(sender)
    }

    // MARK: Helpers

    /// Extracts the first file URL from the drag pasteboard, if any.
    private func fileURL(from info: NSDraggingInfo) -> URL? {
        let pb = info.draggingPasteboard
        guard let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return nil }
        return urls.first
    }
}

