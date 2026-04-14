import AppKit
import Combine
import Foundation

@MainActor
final class StatusItemManager: NSObject {
    private let settingsManager: SettingsManager
    private let menuBuilder: MenuBuilder
    private let shortcutManager: KeyboardShortcutManager

    private var cancellables: Set<AnyCancellable> = []
    private var statusItems: [UUID: NSStatusItem] = [:]
    private var menuRetention: [UUID: NSMenu] = [:]

    override init() {
        self.settingsManager = .shared
        self.menuBuilder = .shared
        self.shortcutManager = .shared
        super.init()
        observeSettings()
        rebuildStatusItems(with: settingsManager.folders)
        shortcutManager.onShortcutTriggered = { [weak self] folderID in
            self?.showMenu(for: folderID)
        }
    }

    private func observeSettings() {
        settingsManager.$folders
            .dropFirst() // skip initial value, already handled in init
            .sink { [weak self] folders in
                Task { @MainActor in
                    self?.rebuildStatusItems(with: folders)
                    self?.shortcutManager.updateShortcuts(for: folders)
                }
            }
            .store(in: &cancellables)
    }

    private func rebuildStatusItems(with folders: [FolderConfiguration]) {
        let currentIDs = Set(statusItems.keys)
        let desiredIDs = Set(folders.map(\.id))

        for removedID in currentIDs.subtracting(desiredIDs) {
            if let item = statusItems.removeValue(forKey: removedID) {
                NSStatusBar.system.removeStatusItem(item)
            }
            menuRetention.removeValue(forKey: removedID)
        }

        for folder in folders {
            let item = statusItems[folder.id] ?? createStatusItem(for: folder.id)
            configure(item: item, with: folder)
        }
    }

    private func createStatusItem(for id: UUID) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItems[id] = item
        return item
    }

    private func configure(item: NSStatusItem, with folder: FolderConfiguration) {
        guard let button = item.button else {
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.appearsDisabled = false
        button.identifier = NSUserInterfaceItemIdentifier(folder.id.uuidString)

        let title = " \(folder.resolvedTitle)"
        switch folder.displayMode {
        case .icon:
            button.title = ""
            button.image = folder.statusImage
        case .title:
            button.title = folder.resolvedTitle
            button.image = nil
        case .iconAndTitle:
            button.title = title
            button.image = folder.statusImage
        }

        button.imagePosition = folder.displayMode == .icon ? .imageOnly : .imageLeading
        button.toolTip = folder.path
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let folderID = UUID(uuidString: sender.identifier?.rawValue ?? "") else {
            return
        }

        guard let folder = settingsManager.folders.first(where: { $0.id == folderID }) else {
            return
        }

        let currentEvent = NSApp.currentEvent
        let isAlternateOpen = currentEvent?.type == .rightMouseUp || currentEvent?.modifierFlags.contains(.option) == true

        if isAlternateOpen {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
            return
        }

        showMenu(for: folderID)
    }

    func showMenu(for folderID: UUID) {
        guard
            let folder = settingsManager.folders.first(where: { $0.id == folderID }),
            let statusItem = statusItems[folderID]
        else {
            return
        }

        let menu = menuBuilder.buildMenu(for: folder)
        menu.delegate = menuBuilder
        menuRetention[folderID] = menu

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
