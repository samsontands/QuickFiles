import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedFolderID: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 270)
        } detail: {
            detail
        }
        .onAppear {
            if selectedFolderID == nil {
                selectedFolderID = settings.folders.first?.id
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedFolderID) {
                ForEach(settings.folders) { folder in
                    HStack(spacing: 10) {
                        Image(systemName: folder.iconName)
                            .foregroundStyle(folder.swiftUIColor)
                            .font(.system(size: 16))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.resolvedTitle)
                                .font(.body.weight(.medium))
                            Text(abbreviatePath(folder.path))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .tag(folder.id)
                }
                .onMove(perform: moveFolders)
            }
            .listStyle(.sidebar)

            Divider()

            // Toolbar: +/- buttons
            HStack(spacing: 2) {
                Button(action: addFolder) {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.borderless)

                Button(action: removeSelectedFolder) {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(selectedFolder == nil || settings.folders.count <= 1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // Bottom section: launch at login, quit
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quickfiles")
                            .font(.subheadline.weight(.semibold))
                        Text("Version 1.0")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selectedFolder {
            FolderSettingsView(folder: selectedFolder)
                .id(selectedFolder.id)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)
                Text("No Folder Selected")
                    .font(.headline)
                Text("Add a folder or select one from the sidebar.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Helpers

    private var selectedFolder: FolderConfiguration? {
        if let selectedFolderID {
            return settings.folders.first(where: { $0.id == selectedFolderID })
        }
        return settings.folders.first
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        panel.message = "Choose a folder to add to the menu bar."

        if panel.runModal() == .OK, let url = panel.url {
            settings.addFolder(path: url.path)
            selectedFolderID = settings.folders.last?.id
        }
    }

    private func removeSelectedFolder() {
        guard let selectedFolderID else { return }
        settings.removeFolder(id: selectedFolderID)
        self.selectedFolderID = settings.folders.first?.id
    }

    private func moveFolders(from offsets: IndexSet, to destination: Int) {
        settings.moveFolder(fromOffsets: offsets, toOffset: destination)
    }

}

func abbreviatePath(_ path: String) -> String {
    if let home = ProcessInfo.processInfo.environment["HOME"], path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}
