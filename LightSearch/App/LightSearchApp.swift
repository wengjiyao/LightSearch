//
//  LightSearchApp.swift
//  LightSearch
//
//  Main application entry point
//

import SwiftUI

@main
struct LightSearchApp: App {
    @State private var statusBarController = StatusBarController()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // Remove "New" from File menu (not applicable for search app)
            CommandGroup(replacing: .newItem) {}

            // Add View menu commands
            CommandGroup(after: .sidebar) {
                Divider()

                Button("Focus Search") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Clear Search") {
                    NotificationCenter.default.post(name: .clearSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Rebuild Index") {
                    NotificationCenter.default.post(name: .rebuildIndex, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Update Index") {
                    NotificationCenter.default.post(name: .updateIndex, object: nil)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }

            // Add Help menu content
            CommandGroup(replacing: .help) {
                Button("LightSearch Help") {
                    showKeyboardShortcuts()
                }
                .keyboardShortcut("?", modifiers: [.command, .shift])

                Divider()

                Link("View on GitHub", destination: URL(string: "https://github.com/yourusername/lightsearch")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/yourusername/lightsearch/issues")!)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Helper Functions

private func showKeyboardShortcuts() {
    let alert = NSAlert()
    alert.messageText = "LightSearch Keyboard Shortcuts"
    alert.informativeText = """
    Global Shortcuts:
    • ⌘F - Focus Search
    • ⌘K - Clear Search
    • ⌘, - Preferences

    Indexing:
    • ⌘⇧R - Rebuild Index
    • ⌘⇧U - Update Index

    Detail View:
    • Esc - Close
    • ← → - Navigate photos
    • Space - Toggle zoom
    • ⌘+ / ⌘- - Zoom in/out
    • ⌘0 - Reset zoom
    • ⌘R - Reveal in Finder

    For more information, see KEYBOARD_SHORTCUTS.md
    """
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

// MARK: - Notification Names for Menu Commands

extension Notification.Name {
    static let focusSearch = Notification.Name("focusSearch")
    static let clearSearch = Notification.Name("clearSearch")
    static let rebuildIndex = Notification.Name("rebuildIndex")
    static let updateIndex = Notification.Name("updateIndex")
}
