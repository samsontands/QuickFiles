import AppKit
import Carbon
import Combine
import Foundation

@MainActor
final class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()

    var onShortcutTriggered: ((UUID) -> Void)?

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var hotKeyFolderIDs: [UInt32: UUID] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {
        installEventHandlerIfNeeded()
    }

    deinit {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
    }

    func updateShortcuts(for folders: [FolderConfiguration]) {
        unregisterAll()

        for folder in folders {
            guard
                let shortcut = folder.keyboardShortcut,
                let parsed = Self.parseShortcut(shortcut)
            else {
                continue
            }

            let hotKeyID = EventHotKeyID(signature: OSType(0x5146494C), id: nextID)
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(parsed.keyCode, parsed.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
            if status == noErr, let hotKeyRef {
                hotKeyRefs[nextID] = hotKeyRef
                hotKeyFolderIDs[nextID] = folder.id
                nextID += 1
            }
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        hotKeyFolderIDs.removeAll()
        nextID = 1
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard
                let userData,
                let event
            else {
                return noErr
            }

            let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr else {
                return status
            }

            Task { @MainActor in
                manager.handleHotKey(withID: hotKeyID.id)
            }

            return noErr
        }

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, pointer, &eventHandler)
    }

    private func handleHotKey(withID id: UInt32) {
        guard let folderID = hotKeyFolderIDs[id] else {
            return
        }

        onShortcutTriggered?(folderID)
    }

    static func displayString(for shortcut: String?) -> String {
        guard let shortcut, !shortcut.isEmpty else {
            return "None"
        }

        return shortcut
            .split(separator: "+")
            .map { token in
                switch token.lowercased() {
                case "cmd":
                    return "⌘"
                case "shift":
                    return "⇧"
                case "option":
                    return "⌥"
                case "control":
                    return "⌃"
                default:
                    return token.uppercased()
                }
            }
            .joined()
    }

    static func shortcutString(from event: NSEvent) -> String? {
        guard event.type == .keyDown else {
            return nil
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []

        if flags.contains(.command) { parts.append("cmd") }
        if flags.contains(.option) { parts.append("option") }
        if flags.contains(.control) { parts.append("control") }
        if flags.contains(.shift) { parts.append("shift") }

        guard let key = keyToken(for: event) else {
            return nil
        }

        parts.append(key)
        return parts.joined(separator: "+")
    }

    private static func parseShortcut(_ shortcut: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let tokens = shortcut
            .split(separator: "+")
            .map { String($0).lowercased() }

        guard let last = tokens.last, let keyCode = keyCodeMap[last] else {
            return nil
        }

        let modifiers = tokens.dropLast().reduce(UInt32(0)) { partial, token in
            switch token {
            case "cmd":
                return partial | UInt32(cmdKey)
            case "shift":
                return partial | UInt32(shiftKey)
            case "option":
                return partial | UInt32(optionKey)
            case "control":
                return partial | UInt32(controlKey)
            default:
                return partial
            }
        }

        return (keyCode: keyCode, modifiers: modifiers)
    }

    private static func keyToken(for event: NSEvent) -> String? {
        let specialMap: [UInt16: String] = [
            UInt16(kVK_Return): "return",
            UInt16(kVK_Tab): "tab",
            UInt16(kVK_Space): "space",
            UInt16(kVK_Delete): "delete",
            UInt16(kVK_Escape): "escape",
            UInt16(kVK_LeftArrow): "left",
            UInt16(kVK_RightArrow): "right",
            UInt16(kVK_UpArrow): "up",
            UInt16(kVK_DownArrow): "down",
        ]

        if let special = specialMap[event.keyCode] {
            return special
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased(), let scalar = characters.unicodeScalars.first else {
            return nil
        }

        if CharacterSet.alphanumerics.contains(scalar) {
            return String(scalar)
        }

        return nil
    }

    private static let keyCodeMap: [String: UInt32] = [
        "a": UInt32(kVK_ANSI_A),
        "b": UInt32(kVK_ANSI_B),
        "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D),
        "e": UInt32(kVK_ANSI_E),
        "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G),
        "h": UInt32(kVK_ANSI_H),
        "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J),
        "k": UInt32(kVK_ANSI_K),
        "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M),
        "n": UInt32(kVK_ANSI_N),
        "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P),
        "q": UInt32(kVK_ANSI_Q),
        "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S),
        "t": UInt32(kVK_ANSI_T),
        "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V),
        "w": UInt32(kVK_ANSI_W),
        "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y),
        "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0),
        "1": UInt32(kVK_ANSI_1),
        "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4),
        "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6),
        "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        "space": UInt32(kVK_Space),
        "tab": UInt32(kVK_Tab),
        "return": UInt32(kVK_Return),
        "escape": UInt32(kVK_Escape),
        "delete": UInt32(kVK_Delete),
        "left": UInt32(kVK_LeftArrow),
        "right": UInt32(kVK_RightArrow),
        "up": UInt32(kVK_UpArrow),
        "down": UInt32(kVK_DownArrow),
    ]
}
