import AppKit
import SwiftUI

@main
struct QuickfilesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        // No visible scenes — everything is managed via menu bar and SettingsWindowController
        Settings {
            EmptyView()
        }
    }
}
