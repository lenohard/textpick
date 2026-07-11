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
        let sourceApp = NSWorkspace.shared.frontmostApplication

        // Fast path: AX / clipboard image — show popup immediately
        if let content = TextCaptureService.shared.captureFast(from: sourceApp) {
            showPopup(with: content)
            return
        }

        // Slow path: show popup instantly, fill in content when clipboard capture lands
        showPopup(with: .text(""), isCapturing: true)
        TextCaptureService.shared.captureClipboardFallback(from: sourceApp) { [weak self] content in
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

    private func showPopup(with content: CapturedContent, isCapturing: Bool = false) {
        popupWindowController?.close()
        popupWindowController = PopupWindowController(content: content, isCapturing: isCapturing)
        popupWindowController?.showWindow(nil)
    }
}
