import AppKit
import SwiftUI

/// A floating, non-activating panel that appears near the mouse cursor.
class PopupWindowController: NSWindowController {
    private var keyMonitor: Any?
    private var clickOutsideMonitor: Any?
    /// Reflected into SwiftUI so the pin button can toggle it
    private let pinnedBinding = PinnedState()

    init(content: CapturedContent) {
        let savedWidth = UserDefaults.standard.double(forKey: "textpick.popupWidth")
        let panelWidth = savedWidth > 0 ? savedWidth : 420
        let opacity = UserDefaults.standard.double(forKey: "textpick.opacity")
        let panelOpacity = opacity > 0 ? opacity : 1.0

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 300),
            styleMask: [
                .titled,
                .closable,
                .fullSizeContentView,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false  // accessory apps never "activate", so keep visible
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.alphaValue = CGFloat(panelOpacity)

        let rootView = PopupView(
            content: content,
            pinnedState: pinnedBinding,
            onClose: { panel.close() }
        )
        panel.contentView = NSHostingView(rootView: rootView)

        super.init(window: panel)

        positionNearMouse(panel: panel)

        // Sync pin toggle → close-on-outside-click behavior
        pinnedBinding.onChange = { [weak self] pinned in
            if pinned {
                self?.removeClickOutsideMonitor()
            } else {
                self?.addClickOutsideMonitor()
            }
        }
        // Default: close on click outside
        addClickOutsideMonitor()

        // ESC closes
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                let closeOnEsc = UserDefaults.standard.object(forKey: "textpick.closeOnEsc") as? Bool ?? true
                if closeOnEsc { self?.close() }
                return nil
            }
            return event
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let m = keyMonitor          { NSEvent.removeMonitor(m) }
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m) }
    }

    private func addClickOutsideMonitor() {
        guard clickOutsideMonitor == nil else { return }
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let win = self.window else { return }
            if !win.isVisible { return }
            self.close()
        }
    }

    private func removeClickOutsideMonitor() {
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m); clickOutsideMonitor = nil }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.orderFrontRegardless()
    }

    private func positionNearMouse(panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let size  = panel.frame.size
        let screen = NSScreen.main?.visibleFrame ?? .zero

        var x = mouse.x + 12
        var y = mouse.y - size.height - 12
        if x + size.width  > screen.maxX { x = mouse.x - size.width - 12 }
        if y < screen.minY               { y = mouse.y + 20 }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Observable wrapper so SwiftUI can read/write pin state
final class PinnedState: ObservableObject {
    @Published var pinned: Bool = false
    var onChange: ((Bool) -> Void)?

    func toggle() {
        pinned.toggle()
        onChange?(pinned)
    }
}
