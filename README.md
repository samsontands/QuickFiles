# Quickfiles

A macOS menu bar app for browsing folders directly from the menu bar. Inspired by [Folder Peek](https://sindresorhus.com/folder-peek) by Sindre Sorhus.

## Features

### Menu Bar
- Add one or more folders to the menu bar, each as its own status item
- Display as icon, title, or icon + title
- Click to browse folder contents via native NSMenu with recursive submenus
- Right-click or Option+click the menu bar icon to open the folder directly in Finder
- Type to search while the menu is open (native NSMenu behavior)

### File Browsing
- Files and folders shown with their system icons (16×16)
- Folders expand into submenus (lazy-loaded on hover)
- Click a file to open it in its default app
- Click a folder to open it in Finder

### File Actions (submenu per file)
- **Open** — open the file in its default app
- **Quick Look** (Space) — preview the file in a floating window without closing the menu
- **Size** and **Modified date** displayed as info
- **Copy** — copy the file to clipboard (paste in Finder with ⌘V)
- **Reveal in Finder** — show the file in Finder
- **Copy Path** — copy the file's full path as text
- **Move to Trash** — send the file to Trash
- **Open With ▸** — submenu listing all apps that can open the file

### Quick Look Preview
- Press **Space** while hovering over a file to open a Quick Look preview
- Preview appears in a non-activating floating window — the menu stays open
- Press **Space** again to dismiss the preview
- Preview window automatically closes when the menu is dismissed
- Supports all file types that macOS Quick Look supports (images, PDFs, videos, documents, etc.)

### Folder Menu Footer
- **Open in Finder** — open the folder in Finder
- **Open in Terminal** — open a new Terminal window at the folder path
- **Settings…** — open the settings window

### Per-Folder Settings
- **Folder path** with "Change…" button
- **Display mode** — icon / title / icon & title
- **Custom title** — override the folder name shown in the menu bar
- **Icon picker** — grid of SF Symbols (folder, tray, archivebox, doc, briefcase, etc.)
- **Icon color** — full color picker
- **Sort order** — name, date modified, date created, kind, size
- **Sort direction** — ascending / descending
- **Max items** — limit how many items are shown (0 = unlimited, up to 100)
- **Show hidden files** — toggle visibility of dotfiles and hidden items
- **Keyboard shortcut** — global hotkey to open/close this folder's menu

### Global Settings
- **Launch at Login** — via SMAppService
- **About** section with app name and version

### Keyboard Shortcuts
- **Space** — Quick Look preview (while browsing menu)
- **Option+click** menu bar icon — open folder in Finder
- **Right-click** menu bar icon — open folder in Finder
- Custom global hotkeys per folder (configured in settings)

## Building

### Requirements
- macOS 13+ (Ventura or later)
- Xcode Command Line Tools or Xcode
- Swift 5.9+

### Build & Run

```bash
# Debug build and run directly
swift build && .build/debug/Quickfiles

# Or build the .app bundle (release)
./build.sh
open build/Quickfiles.app
```

### Project Structure

```
Quickfiles/
├── Package.swift                 # SPM manifest, macOS 13+
├── build.sh                      # Builds release .app bundle
├── README.md
├── Resources/
│   └── Info.plist                # LSUIElement=true, bundle metadata
└── Sources/
    ├── QuickfilesApp.swift       # @main entry, SwiftUI Settings scene
    ├── AppDelegate.swift         # Initializes StatusItemManager
    ├── StatusItemManager.swift   # One NSStatusItem per folder, click handling
    ├── MenuBuilder.swift         # Builds NSMenu trees, Quick Look, all file actions
    ├── FolderConfiguration.swift # Data model, display mode, sort order, hex color
    ├── SettingsManager.swift     # UserDefaults persistence, ObservableObject
    ├── SettingsView.swift        # NavigationSplitView settings with sidebar
    ├── FolderSettingsView.swift  # Per-folder configuration UI
    ├── KeyboardShortcutManager.swift # Global hotkeys via Carbon API
    └── FileUtils.swift           # File size, dates, thumbnails, app lookup
```

## Technical Notes

- Menu bar app only (no Dock icon) — uses `NSApplication.setActivationPolicy(.accessory)`
- File browsing uses `NSMenu` / `NSMenuItem` for native menu bar behavior
- Submenus are lazy-loaded via `NSMenuDelegate.menuNeedsUpdate(_:)` 
- Quick Look uses a non-activating `NSPanel` with `QLPreviewView` so the menu stays open
- File icons via `NSWorkspace.shared.icon(forFile:)`
- "Open With" apps discovered via `NSWorkspace.shared.urlsForApplications(toOpen:)`
- Global shortcuts via Carbon `RegisterEventHotKey` API
- Settings persisted in UserDefaults as JSON-encoded `[FolderConfiguration]`
