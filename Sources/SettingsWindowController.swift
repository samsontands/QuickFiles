import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let windowDelegate = SettingsWindowDelegate()

    private init() {}

    func showSettings() {
        if let window {
            // Reuse existing window
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .frame(minWidth: 860, minHeight: 560)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quickfiles Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.minSize = NSSize(width: 700, height: 450)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = windowDelegate

        self.window = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    fileprivate func windowDidClose() {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.shared.windowDidClose()
    }
}
