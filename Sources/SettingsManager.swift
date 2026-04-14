import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var folders: [FolderConfiguration]
    @Published var launchAtLogin: Bool

    private let foldersKey = "quickfiles.folders"
    private let launchAtLoginKey = "quickfiles.launchAtLogin"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if
            let data = defaults.data(forKey: foldersKey),
            let decoded = try? decoder.decode([FolderConfiguration].self, from: data),
            !decoded.isEmpty
        {
            folders = decoded
        } else {
            folders = [FolderConfiguration.desktopDefault()]
        }

        launchAtLogin = defaults.bool(forKey: launchAtLoginKey)
        persistFolders()
        syncLaunchAtLoginStateFromSystem()
    }

    func addFolder(path: String) {
        let newFolder = FolderConfiguration(path: path)
        folders.append(newFolder)
        persistFolders()
    }

    func removeFolder(id: UUID) {
        folders.removeAll { $0.id == id }

        if folders.isEmpty {
            folders = [FolderConfiguration.desktopDefault()]
        }

        persistFolders()
    }

    func updateFolder(_ folder: FolderConfiguration) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else {
            return
        }

        folders[index] = folder
        persistFolders()
    }

    func moveFolder(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        folders.move(fromOffsets: offsets, toOffset: destination)
        persistFolders()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        defaults.set(enabled, forKey: launchAtLoginKey)

        guard #available(macOS 13, *) else {
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Keep the UI responsive even when registration is unavailable in ad-hoc builds.
        }
    }

    private func persistFolders() {
        guard let data = try? encoder.encode(folders) else {
            return
        }

        defaults.set(data, forKey: foldersKey)
    }

    private func syncLaunchAtLoginStateFromSystem() {
        guard #available(macOS 13, *) else {
            return
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin = true
        case .notFound, .notRegistered, .requiresApproval:
            break
        @unknown default:
            break
        }
    }
}
