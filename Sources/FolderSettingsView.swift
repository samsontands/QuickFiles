import AppKit
import Carbon
import SwiftUI

struct FolderSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var draft: FolderConfiguration

    private let iconNames = [
        "folder", "folder.fill",
        "tray", "tray.fill",
        "archivebox", "archivebox.fill",
        "doc.on.doc", "doc.text",
        "briefcase", "briefcase.fill",
        "books.vertical", "books.vertical.fill",
        "externaldrive", "externaldrive.fill",
        "desktopcomputer", "display",
        "star", "star.fill",
        "heart", "heart.fill",
        "bookmark", "bookmark.fill",
        "tag", "tag.fill",
        "paperplane", "paperplane.fill",
        "tray.2", "tray.full",
        "shippingbox", "shippingbox.fill",
    ]

    init(folder: FolderConfiguration) {
        _draft = State(initialValue: folder)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                folderSection
                displaySection
                sortingSection
                shortcutSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(settings.$folders) { folders in
            if let refreshed = folders.first(where: { $0.id == draft.id }) {
                draft = refreshed
            }
        }
    }

    // MARK: - Folder Path

    private var folderSection: some View {
        GroupBox {
            HStack(alignment: .top) {
                Image(systemName: draft.iconName)
                    .foregroundStyle(draft.swiftUIColor)
                    .font(.system(size: 28))
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.resolvedTitle)
                        .font(.headline)
                    Text(abbreviatePath(draft.path))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                Spacer()

                Button("Change\u{2026}", action: changeFolder)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Folder")
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Menu Bar Style", selection: binding(\.displayMode)) {
                    ForEach(FolderDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Custom Title", text: binding(\.title))
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon")
                        .font(.subheadline.weight(.medium))
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 10), spacing: 6) {
                        ForEach(iconNames, id: \.self) { iconName in
                            Button {
                                draft.iconName = iconName
                                commit()
                            } label: {
                                Image(systemName: iconName)
                                    .font(.system(size: 14))
                                    .frame(width: 30, height: 30)
                                    .foregroundStyle(draft.iconName == iconName ? .white : draft.swiftUIColor)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(draft.iconName == iconName ? draft.swiftUIColor : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(
                                                draft.iconName == iconName ? Color.clear : Color.secondary.opacity(0.15),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ColorPicker("Icon Color", selection: Binding(
                    get: { draft.swiftUIColor },
                    set: {
                        draft.iconColor = NSColor($0).hexString
                        commit()
                    }
                ))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Display")
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Sorting

    private var sortingSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Sort By", selection: binding(\.sortOrder)) {
                    ForEach(FolderSortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }

                Toggle("Ascending", isOn: binding(\.sortAscending))
                    .toggleStyle(.checkbox)

                Stepper(value: Binding(
                    get: { draft.maxItems },
                    set: {
                        draft.maxItems = min(max($0, 0), 100)
                        commit()
                    }
                ), in: 0...100) {
                    Text(draft.maxItems == 0 ? "Max Items: Unlimited" : "Max Items: \(draft.maxItems)")
                }

                Toggle("Show Hidden Files", isOn: binding(\.showHiddenFiles))
                    .toggleStyle(.checkbox)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Sorting & Filtering")
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Keyboard Shortcut

    private var shortcutSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                KeyboardShortcutRecorder(shortcut: Binding(
                    get: { draft.keyboardShortcut },
                    set: {
                        draft.keyboardShortcut = $0
                        commit()
                    }
                ))
                Text("Press a combination of Command, Option, Control, or Shift with a letter or number.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("Keyboard Shortcut")
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Helpers

    private func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"

        if panel.runModal() == .OK, let url = panel.url {
            let oldName = URL(fileURLWithPath: draft.path).lastPathComponent
            draft.path = url.path
            // Auto-update title if it was still the default (matching old folder name)
            if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || draft.title == oldName {
                draft.title = url.lastPathComponent
            }
            commit()
        }
    }

    private func commit() {
        settings.updateFolder(draft)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<FolderConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: {
                draft[keyPath: keyPath] = $0
                commit()
            }
        )
    }

}

// MARK: - Keyboard Shortcut Recorder

private struct KeyboardShortcutRecorder: View {
    @Binding var shortcut: String?
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                isRecording.toggle()
            } label: {
                Text(isRecording ? "Press shortcut\u{2026}" : KeyboardShortcutManager.displayString(for: shortcut))
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 160, minHeight: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isRecording ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .overlay {
                ShortcutCaptureRepresentable(isRecording: $isRecording, shortcut: $shortcut)
                    .allowsHitTesting(false)
            }

            if shortcut != nil {
                Button("Clear") {
                    shortcut = nil
                    isRecording = false
                }
                .controlSize(.small)
            }
        }
    }
}

private struct ShortcutCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var shortcut: String?

    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView()
        view.onCapture = { event in
            if event.keyCode == UInt16(kVK_Escape) {
                isRecording = false
                return
            }

            if let newShortcut = KeyboardShortcutManager.shortcutString(from: event) {
                shortcut = newShortcut
                isRecording = false
            }
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {
        nsView.isRecording = isRecording
        if isRecording, nsView.window != nil {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class ShortcutCaptureView: NSView {
    var onCapture: ((NSEvent) -> Void)?
    var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        onCapture?(event)
    }
}
