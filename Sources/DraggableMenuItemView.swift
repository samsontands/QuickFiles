import AppKit
import UniformTypeIdentifiers

/// A custom NSView used as an NSMenuItem's view that supports dragging files out of the menu.
/// Looks like a native menu item (icon + title + submenu arrow) but allows drag initiation.
final class DraggableMenuItemView: NSView, NSDraggingSource {
    let fileURL: URL
    let isDirectory: Bool
    private let fileIcon: NSImage
    private let fileTitle: String
    private var trackingArea: NSTrackingArea?
    private var isHighlighted = false
    private var dragStartPoint: NSPoint?

    private static let itemHeight: CGFloat = 22
    private static let iconSize: CGFloat = 16
    private static let leadingPadding: CGFloat = 20
    private static let iconTextGap: CGFloat = 6
    private static let trailingPadding: CGFloat = 30 // room for submenu arrow
    private static let font = NSFont.menuFont(ofSize: 0)

    init(title: String, icon: NSImage, fileURL: URL, isDirectory: Bool) {
        self.fileURL = fileURL
        self.isDirectory = isDirectory
        self.fileIcon = icon
        self.fileTitle = title
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: Self.itemHeight))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = (fileTitle as NSString).size(withAttributes: [.font: Self.font]).width
        let width = Self.leadingPadding + Self.iconSize + Self.iconTextGap + textWidth + Self.trailingPadding
        return NSSize(width: max(width, 200), height: Self.itemHeight)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4)
            path.fill()
        }

        // Draw icon
        let iconRect = NSRect(
            x: Self.leadingPadding,
            y: (bounds.height - Self.iconSize) / 2,
            width: Self.iconSize,
            height: Self.iconSize
        )
        fileIcon.draw(in: iconRect)

        // Draw title
        let textColor: NSColor = isHighlighted ? .white : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: textColor,
        ]
        let textX = Self.leadingPadding + Self.iconSize + Self.iconTextGap
        let textSize = (fileTitle as NSString).size(withAttributes: attrs)
        let maxTextWidth = bounds.width - textX - Self.trailingPadding
        let textRect = NSRect(
            x: textX,
            y: (bounds.height - textSize.height) / 2,
            width: min(textSize.width, maxTextWidth),
            height: textSize.height
        )
        (fileTitle as NSString).draw(in: textRect, withAttributes: attrs)

        // Draw submenu arrow
        let arrowAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 10),
            .foregroundColor: isHighlighted ? NSColor.white.withAlphaComponent(0.8) : NSColor.tertiaryLabelColor,
        ]
        let arrow = "\u{25B8}"
        let arrowSize = (arrow as NSString).size(withAttributes: arrowAttrs)
        let arrowRect = NSRect(
            x: bounds.width - 16,
            y: (bounds.height - arrowSize.height) / 2,
            width: arrowSize.width,
            height: arrowSize.height
        )
        (arrow as NSString).draw(in: arrowRect, withAttributes: arrowAttrs)
    }

    // MARK: - Tracking & Highlight

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
    }

    // MARK: - Mouse Handling for Drag

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = dragStartPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        let dx = current.x - startPoint.x
        let dy = current.y - startPoint.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance > 4 else { return }
        dragStartPoint = nil
        startDrag(from: event)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartPoint = nil
        // Click (not drag) — trigger the menu item's action
        if let menuItem = enclosingMenuItem {
            if menuItem.hasSubmenu {
                // Let the menu handle submenu display
            } else if let action = menuItem.action, let target = menuItem.target {
                NSApp.sendAction(action, to: target, from: menuItem)
                menuItem.menu?.cancelTracking()
            }
        }
    }

    // MARK: - Drag Session

    private func startDrag(from event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

        let iconImage = fileIcon
        let dragSize = NSSize(width: 32, height: 32)
        let dragFrame = NSRect(
            origin: NSPoint(x: bounds.midX - dragSize.width / 2, y: bounds.midY - dragSize.height / 2),
            size: dragSize
        )
        draggingItem.setDraggingFrame(dragFrame, contents: iconImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            return [.copy, .move]
        case .withinApplication:
            return .copy
        @unknown default:
            return .copy
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        enclosingMenuItem?.menu?.cancelTracking()
    }
}
