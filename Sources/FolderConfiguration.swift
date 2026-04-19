import AppKit
import Foundation
import SwiftUI

enum FolderDisplayMode: String, Codable, CaseIterable, Identifiable {
    case icon
    case title
    case iconAndTitle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .icon:
            return "Icon"
        case .title:
            return "Title"
        case .iconAndTitle:
            return "Icon & Title"
        }
    }
}

enum FolderSortOrder: String, Codable, CaseIterable, Identifiable {
    case name
    case dateModified
    case dateCreated
    case kind
    case size

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name:
            return "Name"
        case .dateModified:
            return "Date Modified"
        case .dateCreated:
            return "Date Created"
        case .kind:
            return "Kind"
        case .size:
            return "Size"
        }
    }
}

struct FolderConfiguration: Codable, Identifiable, Equatable {
    var id: UUID
    var path: String
    var displayMode: FolderDisplayMode
    var iconName: String
    var iconColor: String
    var title: String
    var sortOrder: FolderSortOrder
    var sortAscending: Bool
    var maxItems: Int
    var showHiddenFiles: Bool
    var keyboardShortcut: String?

    init(
        id: UUID = UUID(),
        path: String,
        displayMode: FolderDisplayMode = .icon,
        iconName: String = "folder",
        iconColor: String = "#007AFF",
        title: String? = nil,
        sortOrder: FolderSortOrder = .name,
        sortAscending: Bool = true,
        maxItems: Int = 0,
        showHiddenFiles: Bool = false,
        keyboardShortcut: String? = nil
    ) {
        self.id = id
        self.path = path
        self.displayMode = displayMode
        self.iconName = iconName
        self.iconColor = iconColor
        self.title = title ?? URL(fileURLWithPath: path).lastPathComponent
        self.sortOrder = sortOrder
        self.sortAscending = sortAscending
        self.maxItems = maxItems
        self.showHiddenFiles = showHiddenFiles
        self.keyboardShortcut = keyboardShortcut
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var resolvedTitle: String {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return url.lastPathComponent
        }

        return title
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }

    var nsColor: NSColor {
        NSColor(hexString: iconColor) ?? .systemBlue
    }

    var statusImage: NSImage? {
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [nsColor])
        let config = sizeConfig.applying(colorConfig)
        guard let image = NSImage(systemSymbolName: iconName, accessibilityDescription: resolvedTitle)?
            .withSymbolConfiguration(config) else {
            return nil
        }
        image.isTemplate = false
        return image
    }
}

extension FolderConfiguration {
    static func desktopDefault() -> FolderConfiguration {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        return FolderConfiguration(path: desktopURL.path)
    }
}

extension NSColor {
    convenience init?(hexString: String) {
        let normalized = hexString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard normalized.count == 6, let hex = Int(normalized, radix: 16) else {
            return nil
        }

        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else {
            return "#007AFF"
        }

        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
