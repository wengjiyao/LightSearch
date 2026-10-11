//
//  StatusBarController.swift
//  LightSearch
//
//  Menu bar status item for quick access and indexing progress
//

import SwiftUI
import AppKit

@MainActor
@Observable
class StatusBarController {
    private var statusItem: NSStatusItem?
    private var indexer: BackgroundIndexer?

    // Track indexing state
    var isIndexing = false
    var indexProgress: Double = 0.0

    init() {
        setupStatusItem()
        setupNotifications()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // Set default icon
        button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "LightSearch")
        button.action = #selector(statusBarButtonClicked)
        button.target = self

        updateMenu()
    }

    private func setupNotifications() {
        // Listen for indexing state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(indexingDidStart),
            name: .indexingDidStart,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(indexingDidUpdate),
            name: .indexingDidUpdate,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(indexingDidComplete),
            name: .indexingDidComplete,
            object: nil
        )
    }

    @objc private func statusBarButtonClicked() {
        guard let button = statusItem?.button else { return }
        statusItem?.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func updateMenu() {
        let menu = NSMenu()

        // Indexing status section
        if isIndexing {
            let progressItem = NSMenuItem(title: "Indexing: \(Int(indexProgress * 100))%", action: nil, keyEquivalent: "")
            progressItem.isEnabled = false
            menu.addItem(progressItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Quick actions
        menu.addItem(NSMenuItem(title: "Show LightSearch", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "New Search", action: #selector(newSearch), keyEquivalent: "f"))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Rebuild Index", action: #selector(rebuildIndex), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Update Index", action: #selector(updateIndex), keyEquivalent: "u"))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit LightSearch", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func newSearch() {
        showMainWindow()
        NotificationCenter.default.post(name: .focusSearch, object: nil)
    }

    @objc private func rebuildIndex() {
        NotificationCenter.default.post(name: .rebuildIndex, object: nil)
    }

    @objc private func updateIndex() {
        NotificationCenter.default.post(name: .updateIndex, object: nil)
    }

    @objc private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func indexingDidStart(_ notification: Notification) {
        isIndexing = true
        indexProgress = 0.0
        updateMenu()

        // Change icon to indicate indexing
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Indexing")
        }
    }

    @objc private func indexingDidUpdate(_ notification: Notification) {
        if let progress = notification.userInfo?["progress"] as? Double {
            indexProgress = progress
            updateMenu()
        }
    }

    @objc private func indexingDidComplete(_ notification: Notification) {
        isIndexing = false
        indexProgress = 0.0
        updateMenu()

        // Restore default icon
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "LightSearch")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Additional Notification Names

extension Notification.Name {
    static let indexingDidStart = Notification.Name("indexingDidStart")
    static let indexingDidUpdate = Notification.Name("indexingDidUpdate")
    static let indexingDidComplete = Notification.Name("indexingDidComplete")
}
