import AppKit
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var popupWindowController: PopupWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusBar()
        setupHotKey()
        setupSelectionMonitor()
        requestAccessibilityPermission()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyConfigChanged(_:)),
            name: .hotkeyConfigChanged,
            object: nil
        )
    }

    // MARK: - Main Menu (Fixes copy/paste shortcuts)

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "TextPick")
        appMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit TextPick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "TextPick")
            button.action = #selector(statusBarClicked)
            button.target = self
        }
    }

    @objc private func statusBarClicked() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Selected Text  ⌘⇧Space", action: #selector(captureText), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit TextPick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openSettings() {
        SettingsWindowController.showSettings()
    }

    // MARK: - Global Hotkey

    private func setupHotKey() {
        let cfg = HotkeySettingsTab.loadConfig()
        registerHotKey(cfg)
    }

    private func registerHotKey(_ cfg: HotkeyConfig) {
        hotKey = nil  // deregister old
        guard let key = Key(string: cfg.key) else {
            print("[TextPick] Unknown key: \(cfg.key)")
            return
        }
        var mods: NSEvent.ModifierFlags = []
        if cfg.modifiers.contains("command")  { mods.insert(.command) }
        if cfg.modifiers.contains("shift")    { mods.insert(.shift) }
        if cfg.modifiers.contains("option")   { mods.insert(.option) }
        if cfg.modifiers.contains("control")  { mods.insert(.control) }
        hotKey = HotKey(key: key, modifiers: mods)
        hotKey?.keyUpHandler = { [weak self] in
            self?.captureText()
        }
        print("[TextPick] Hotkey registered: \(cfg.displayString)")
    }

    @objc private func hotkeyConfigChanged(_ notification: Notification) {
        if let cfg = notification.object as? HotkeyConfig {
            registerHotKey(cfg)
        }
    }

    // MARK: - Accessibility Permission Check

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            print("[TextPick] Accessibility permission not granted — prompting user.")
        }
    }

    // MARK: - Capture

    @objc func captureText() {
        // HotKey may fire off the main thread — always show UI on main.
        DispatchQueue.main.async { [weak self] in
            self?.captureTextOnMain()
        }
    }

    private func captureTextOnMain() {
        presentCapture(from: NSWorkspace.shared.frontmostApplication, autoOpened: false)
    }

    // MARK: - Selection Monitor

    private func setupSelectionMonitor() {
        SelectionMonitorService.shared.onSelectionReady = { [weak self] text in
            DispatchQueue.main.async {
                self?.showSelectionPopup(with: text)
            }
        }
        SelectionMonitorService.shared.onSelectionCleared = { [weak self] in
            DispatchQueue.main.async {
                guard let self, let popup = self.popupWindowController, popup.autoOpened else { return }
                if !popup.pinnedState.isProcessing && !popup.pinnedState.pinned {
                    popup.close()
                    SelectionMonitorService.shared.resetLastShown()
                }
            }
        }
        SelectionMonitorService.shared.start()
    }

    private func showSelectionPopup(with text: String) {
        let style = SelectionTriggerStyle.current
        let displayMode: PopupDisplayMode = style == .compact ? .compact : .full
        showPopup(with: .text(text), displayMode: displayMode, autoOpened: true)
    }

    private func presentCapture(from sourceApp: NSRunningApplication?, autoOpened: Bool) {
        if let content = TextCaptureService.shared.captureFast(from: sourceApp) {
            showPopup(with: content, autoOpened: autoOpened)
            return
        }

        showPopup(with: .text(""), isCapturing: true, autoOpened: autoOpened)
        TextCaptureService.shared.capture(from: sourceApp) { [weak self] content in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let content else {
                    self.popupWindowController?.close()
                    return
                }
                self.popupWindowController?.updateContent(content)
            }
        }
    }

    // MARK: - Popup

    private func showPopup(
        with content: CapturedContent,
        isCapturing: Bool = false,
        displayMode: PopupDisplayMode = .full,
        autoOpened: Bool = false
    ) {
        popupWindowController?.close()
        if !autoOpened {
            // Hotkey-driven popup shouldn't suppress the next selection trigger.
            SelectionMonitorService.shared.resetLastShown()
        }
        popupWindowController = PopupWindowController(
            content: content,
            isCapturing: isCapturing,
            displayMode: displayMode,
            autoOpened: autoOpened
        )
        popupWindowController?.showWindow(nil)
    }
}
