import AppKit
import Foundation
import ObjectiveC
import Quartz

@MainActor
final class MenuBuilder: NSObject, NSMenuDelegate {
    static let shared = MenuBuilder()

    private let dateFormatter: DateFormatter
    private var previewWindow: QuickLookFloatingWindow?

    private override init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        super.init()
    }

    func buildMenu(for folder: FolderConfiguration) -> QuickfilesMenu {
        let menu = QuickfilesMenu(title: folder.resolvedTitle)
        menu.autoenablesItems = false
        menu.delegate = self
        menu.menuBuilder = self
        menu.quickfilesContext = MenuContext(url: folder.url, folder: folder, isRoot: true)
        // Only show placeholder — menuNeedsUpdate will load actual contents when AppKit shows the menu
        populateLoadingState(into: menu)
        return menu
    }

    func menuDidClose(_ menu: NSMenu) {
        // Only dismiss Quick Look when the root menu closes
        if let ctx = menu.quickfilesContext, ctx.isRoot {
            previewWindow?.orderOut(nil)
            previewWindow = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loadContents(for: menu)
    }

    // MARK: - Quick Look (non-activating floating window)

    /// Called by QuickfilesMenu.performKeyEquivalent when Space is pressed during menu tracking.
    /// Returns true if handled (so the menu stays open).
    func handleSpaceKey(in menu: NSMenu) -> Bool {
        // Toggle: if preview is already showing, close it
        if let window = previewWindow, window.isVisible {
            window.orderOut(nil)
            previewWindow = nil
            return true
        }

        // Find the highlighted file across the menu hierarchy
        if let url = highlightedFileURL(in: menu) {
            showQuickLook(for: url)
            return true
        }

        return false
    }

    private func highlightedFileURL(in menu: NSMenu) -> URL? {
        // Check the deepest visible submenu first
        for item in menu.items {
            if item.isHighlighted, let submenu = item.submenu, submenu.numberOfItems > 0 {
                if let found = highlightedFileURL(in: submenu) {
                    return found
                }
            }
        }

        // Check this menu's highlighted item
        if let item = menu.highlightedItem {
            // Custom draggable view items store URL in the view
            if let dragView = item.view as? DraggableMenuItemView, !dragView.isDirectory {
                return dragView.fileURL
            }
            // Standard menu items store URL in representedObject
            if let url = item.representedObject as? URL {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if !isDir {
                    return url
                }
            }
        }

        return nil
    }

    private func showQuickLook(for url: URL) {
        if previewWindow == nil {
            previewWindow = QuickLookFloatingWindow()
        }
        previewWindow?.showPreview(for: url)
    }

    // MARK: - Menu Building

    private func loadContents(for menu: NSMenu) {
        guard let context = menu.quickfilesContext else {
            return
        }

        populateLoadingState(into: menu)

        let result = Self.buildEntries(for: context)
        apply(result: result, to: menu, context: context)
    }

    private func populateLoadingState(into menu: NSMenu) {
        menu.removeAllItems()
        let item = NSMenuItem(title: "Loading\u{2026}", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    nonisolated private static func buildEntries(for context: MenuContext) -> Result<[URL], Error> {
        do {
            let fileManager = FileManager.default
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isHiddenKey,
                .contentModificationDateKey,
                .creationDateKey,
                .localizedNameKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .typeIdentifierKey,
            ]

            var urls = try fileManager.contentsOfDirectory(
                at: context.url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants]
            )

            if !context.folder.showHiddenFiles {
                urls.removeAll { url in
                    let values = try? url.resourceValues(forKeys: [.isHiddenKey, .nameKey])
                    let isHidden = values?.isHidden == true || url.lastPathComponent.hasPrefix(".")
                    return isHidden
                }
            }

            // Pre-fetch resource values for sorting to avoid O(n log n) file system calls
            let sortKeys: Set<URLResourceKey> = [.localizedNameKey, .contentModificationDateKey, .creationDateKey, .typeIdentifierKey, .fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey]
            var valuesCache: [URL: URLResourceValues] = [:]
            for url in urls {
                valuesCache[url] = try? url.resourceValues(forKeys: sortKeys)
            }

            // Folders first, then files — within each group, sort by user preference
            let folders = urls.filter { valuesCache[$0]?.isDirectory == true }
                .sorted { compare(lhs: $0, rhs: $1, using: context.folder, cache: valuesCache) }
            let files = urls.filter { valuesCache[$0]?.isDirectory != true }
                .sorted { compare(lhs: $0, rhs: $1, using: context.folder, cache: valuesCache) }
            urls = folders + files

            if context.folder.maxItems > 0 {
                urls = Array(urls.prefix(context.folder.maxItems))
            }

            return .success(urls)
        } catch {
            return .failure(error)
        }
    }

    private func apply(result: Result<[URL], Error>, to menu: NSMenu, context: MenuContext) {
        menu.removeAllItems()

        switch result {
        case .success(let urls):
            if urls.isEmpty {
                let emptyItem = NSMenuItem(title: "Empty Folder", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                menu.addItem(emptyItem)
            } else {
                urls.forEach { url in
                    menu.addItem(makeItem(for: url, folderConfig: context.folder))
                }
            }

        case .failure(let error):
            let errorItem = NSMenuItem(title: "Unable to Read Folder", action: nil, keyEquivalent: "")
            errorItem.toolTip = error.localizedDescription
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        if context.isRoot {
            // Item count header
            if case .success(let urls) = result, !urls.isEmpty {
                let folderCount = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }.count
                let fileCount = urls.count - folderCount
                var parts: [String] = []
                if folderCount > 0 { parts.append("\(folderCount) folder\(folderCount == 1 ? "" : "s")") }
                if fileCount > 0 { parts.append("\(fileCount) file\(fileCount == 1 ? "" : "s")") }
                let countItem = NSMenuItem(title: parts.joined(separator: ", "), action: nil, keyEquivalent: "")
                countItem.isEnabled = false
                menu.insertItem(countItem, at: 0)
                menu.insertItem(.separator(), at: 1)
            }

            menu.addItem(.separator())
            menu.addItem(makeActionItem(title: "Open in Finder", action: #selector(openInFinder(_:)), representedObject: context.url))
            menu.addItem(makeActionItem(title: "Open in Terminal", action: #selector(openInTerminal(_:)), representedObject: context.url))
            menu.addItem(.separator())
            menu.addItem(makeActionItem(title: "Settings\u{2026}", action: #selector(openSettings(_:)), representedObject: nil))
            menu.addItem(makeActionItem(title: "Quit Quickfiles", action: #selector(quitApp(_:)), representedObject: nil))
        }
    }

    private func makeItem(for url: URL, folderConfig: FolderConfiguration) -> NSMenuItem {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = values?.isDirectory == true

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.representedObject = url
        item.target = self

        // Use draggable custom view for file/folder items
        let dragView = DraggableMenuItemView(
            title: url.lastPathComponent,
            icon: icon(for: url),
            fileURL: url,
            isDirectory: isDirectory
        )
        item.view = dragView

        if isDirectory {
            item.action = #selector(openFolder(_:))
            let submenu = QuickfilesMenu(title: url.lastPathComponent)
            submenu.autoenablesItems = false
            submenu.delegate = self
            submenu.menuBuilder = self
            submenu.quickfilesContext = MenuContext(url: url, folder: folderConfig, isRoot: false)
            submenu.addItem(makeActionItem(title: "Open in Finder", action: #selector(openFolder(_:)), representedObject: url))
            submenu.addItem(.separator())
            let placeholder = NSMenuItem(title: "Loading\u{2026}", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
            item.submenu = submenu
        } else {
            item.action = #selector(openFile(_:))
            item.submenu = buildFileSubmenu(for: url)
        }

        return item
    }

    private func buildFileSubmenu(for url: URL) -> QuickfilesMenu {
        let submenu = QuickfilesMenu(title: url.lastPathComponent)
        submenu.autoenablesItems = false
        submenu.menuBuilder = self

        submenu.addItem(makeActionItem(title: "Open", action: #selector(openFile(_:)), representedObject: url))
        submenu.addItem(makeActionItem(title: "Quick Look  \u{2423}", action: #selector(quickLookFile(_:)), representedObject: url))

        submenu.addItem(.separator())

        let sizeItem = NSMenuItem(title: "Size: \(FileUtils.fileSize(at: url))", action: nil, keyEquivalent: "")
        sizeItem.isEnabled = false
        submenu.addItem(sizeItem)

        let modified = FileUtils.fileDate(at: url, type: .modified).map(dateFormatter.string(from:)) ?? "Unknown"
        let modifiedItem = NSMenuItem(title: "Modified: \(modified)", action: nil, keyEquivalent: "")
        modifiedItem.isEnabled = false
        submenu.addItem(modifiedItem)

        submenu.addItem(.separator())
        submenu.addItem(makeActionItem(title: "Copy", action: #selector(copyFile(_:)), representedObject: url))
        submenu.addItem(makeActionItem(title: "Reveal in Finder", action: #selector(revealInFinder(_:)), representedObject: url))
        submenu.addItem(makeActionItem(title: "Copy Path", action: #selector(copyPath(_:)), representedObject: url))
        submenu.addItem(makeActionItem(title: "Move to Trash", action: #selector(moveToTrash(_:)), representedObject: url))
        submenu.addItem(.separator())
        submenu.addItem(makeOpenWithMenu(for: url))
        return submenu
    }

    private func makeOpenWithMenu(for url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        let submenu = QuickfilesMenu(title: "Open With")
        submenu.autoenablesItems = false
        submenu.menuBuilder = self

        let apps = FileUtils.appsForFile(at: url)
        if apps.isEmpty {
            let emptyItem = NSMenuItem(title: "No Available Apps", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for app in apps {
                let appItem = makeActionItem(title: app.name, action: #selector(openFileWithApp(_:)), representedObject: OpenWithContext(fileURL: url, appURL: app.url))
                appItem.image = NSWorkspace.shared.icon(forFile: app.url.path).resized(to: NSSize(width: 16, height: 16))
                submenu.addItem(appItem)
            }
        }

        item.submenu = submenu
        return item
    }

    private func makeActionItem(title: String, action: Selector, representedObject: Any?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        return item
    }

    // MARK: - Sorting

    nonisolated private static func compare(lhs: URL, rhs: URL, using folder: FolderConfiguration, cache: [URL: URLResourceValues]) -> Bool {
        let lhsValues = cache[lhs]
        let rhsValues = cache[rhs]

        let comparison: ComparisonResult = {
            switch folder.sortOrder {
            case .name:
                let lhsName = lhsValues?.localizedName ?? lhs.lastPathComponent
                let rhsName = rhsValues?.localizedName ?? rhs.lastPathComponent
                return lhsName.localizedCaseInsensitiveCompare(rhsName)

            case .dateModified:
                let lhsDate = lhsValues?.contentModificationDate ?? .distantPast
                let rhsDate = rhsValues?.contentModificationDate ?? .distantPast
                return lhsDate.compare(rhsDate)

            case .dateCreated:
                let lhsDate = lhsValues?.creationDate ?? .distantPast
                let rhsDate = rhsValues?.creationDate ?? .distantPast
                return lhsDate.compare(rhsDate)

            case .kind:
                let lhsKind = lhsValues?.typeIdentifier ?? lhs.pathExtension
                let rhsKind = rhsValues?.typeIdentifier ?? rhs.pathExtension
                let comparison = lhsKind.localizedCaseInsensitiveCompare(rhsKind)
                if comparison == .orderedSame {
                    let lhsName = lhsValues?.localizedName ?? lhs.lastPathComponent
                    let rhsName = rhsValues?.localizedName ?? rhs.lastPathComponent
                    return lhsName.localizedCaseInsensitiveCompare(rhsName)
                }
                return comparison

            case .size:
                let lhsSize = lhsValues?.totalFileAllocatedSize ?? lhsValues?.fileSize ?? 0
                let rhsSize = rhsValues?.totalFileAllocatedSize ?? rhsValues?.fileSize ?? 0
                if lhsSize == rhsSize {
                    let lhsName = lhsValues?.localizedName ?? lhs.lastPathComponent
                    let rhsName = rhsValues?.localizedName ?? rhs.lastPathComponent
                    return lhsName.localizedCaseInsensitiveCompare(rhsName)
                }
                return lhsSize < rhsSize ? .orderedAscending : .orderedDescending
            }
        }()

        if comparison == .orderedSame {
            let lhsName = lhsValues?.localizedName ?? lhs.lastPathComponent
            let rhsName = rhsValues?.localizedName ?? rhs.lastPathComponent
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        return folder.sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private func icon(for url: URL) -> NSImage {
        let original = NSWorkspace.shared.icon(forFile: url.path)
        // Copy to avoid mutating the shared workspace icon cache
        let copy = original.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    // MARK: - Actions

    @objc private func openFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quickLookFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        showQuickLook(for: url)
    }

    @objc private func openFolder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func copyFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    @objc private func moveToTrash(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func openFileWithApp(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? OpenWithContext else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([context.fileURL], withApplicationAt: context.appURL, configuration: configuration) { _, _ in }
    }

    @objc private func openInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    @objc private func openInTerminal(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let escapedPath = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"cd \\\"\(escapedPath)\\\"\"\nend tell"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}

// MARK: - QuickfilesMenu — custom NSMenu that intercepts Space for Quick Look

/// Subclass of NSMenu that intercepts Space bar during menu tracking.
/// `performKeyEquivalent` IS called during NSMenu's tracking loop, unlike
/// `NSEvent.addLocalMonitorForEvents` which Apple explicitly excludes from menu tracking.
/// Returning `true` consumes the event — the menu stays open.
@MainActor
final class QuickfilesMenu: NSMenu {
    weak var menuBuilder: MenuBuilder?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Intercept Space (keyCode 49) with no modifiers
        if event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            if let builder = menuBuilder, builder.handleSpaceKey(in: self) {
                return true // consumed — menu stays open
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Supporting Types

private struct MenuContext {
    let url: URL
    let folder: FolderConfiguration
    let isRoot: Bool
}

private struct OpenWithContext {
    let fileURL: URL
    let appURL: URL
}

private extension NSImage {
    func resized(to targetSize: NSSize) -> NSImage {
        let newImage = NSImage(size: targetSize, flipped: false) { rect in
            self.draw(in: rect)
            return true
        }
        newImage.isTemplate = isTemplate
        return newImage
    }
}

private var quickfilesMenuContextKey: UInt8 = 0

private extension NSMenu {
    var quickfilesContext: MenuContext? {
        get {
            objc_getAssociatedObject(self, &quickfilesMenuContextKey) as? MenuContext
        }
        set {
            objc_setAssociatedObject(self, &quickfilesMenuContextKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// MARK: - Non-activating Quick Look Window

@MainActor
private final class QuickLookFloatingWindow: NSPanel {
    private let previewView: QLPreviewView

    init() {
        previewView = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView(frame: .zero)
        let size = NSSize(width: 500, height: 400)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu + 1
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true

        previewView.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(previewView)
        if let contentView {
            NSLayoutConstraint.activate([
                previewView.topAnchor.constraint(equalTo: contentView.topAnchor),
                previewView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
        }
    }

    func showPreview(for url: URL) {
        previewView.previewItem = url as NSURL
        title = url.lastPathComponent

        if !isVisible {
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowSize = frame.size
                let x = screenFrame.midX - windowSize.width / 2
                let y = screenFrame.midY - windowSize.height / 2
                setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        orderFrontRegardless()
    }

    // Prevent this window from ever becoming key so the menu stays open
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
