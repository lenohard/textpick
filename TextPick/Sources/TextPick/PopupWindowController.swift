import AppKit
import SwiftUI

/// NSHostingView on a non-activating panel won't receive clicks unless it accepts first mouse.
private final class AcceptsFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Defers close wiring until after NSWindowController.init (Swift init rules).
private final class CloseAction {
    var handler: (() -> Void)?
    func perform() { handler?() }
}

/// Defers expand wiring until after NSWindowController.init (Swift init rules).
private final class ExpandAction {
    var handler: (() -> Void)?
    func perform() { handler?() }
}

/// Holds cancellable work for the popup session.
final class PopupSession: ObservableObject {
    var processingTask: Task<Void, Never>?

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
    }
}

/// Observable content so slow-path clipboard capture can update the popup in place.
final class CapturedContentState: ObservableObject {
    @Published var content: CapturedContent
    @Published var isCapturing: Bool

    init(content: CapturedContent, isCapturing: Bool = false) {
        self.content = content
        self.isCapturing = isCapturing
    }
}

enum PopupDisplayMode {
    case full
    case compact
}

/// A floating, non-activating panel that appears near the mouse cursor.
class PopupWindowController: NSWindowController {
    private var keyMonitor: Any?
    private var clickOutsideMonitor: Any?
    /// Reflected into SwiftUI so the pin button can toggle it
    let pinnedState = PinnedState()
    private let session = PopupSession()
    private let contentState: CapturedContentState
    let autoOpened: Bool
    private let displayMode: PopupDisplayMode

    init(
        content: CapturedContent,
        isCapturing: Bool = false,
        displayMode: PopupDisplayMode = .full,
        autoOpened: Bool = false
    ) {
        contentState = CapturedContentState(content: content, isCapturing: isCapturing)
        self.displayMode = displayMode
        self.autoOpened = autoOpened
        let savedWidth = UserDefaults.standard.double(forKey: "textpick.popupWidth")
        let panelWidth = savedWidth > 0 ? savedWidth : 420
        let opacity = UserDefaults.standard.double(forKey: "textpick.opacity")
        let panelOpacity = opacity > 0 ? opacity : 1.0

        let panelHeight: CGFloat = displayMode == .compact ? 48 : 300
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
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

        let closeAction = CloseAction()
        let expandAction = ExpandAction()
        let rootView = PopupView(
            contentState: contentState,
            pinnedState: pinnedState,
            session: session,
            displayMode: displayMode,
            onClose: closeAction.perform,
            onExpandFromCompact: expandAction.perform
        )
        panel.contentView = AcceptsFirstMouseHostingView(rootView: rootView)

        super.init(window: panel)
        closeAction.handler = { [weak self] in self?.close() }
        expandAction.handler = { [weak self, weak panel] in
            guard let self, let panel else { return }
            let w = savedWidth > 0 ? savedWidth : 420
            panel.setContentSize(NSSize(width: w, height: 300))
            self.positionNearMouse(panel: panel)
        }

        positionNearMouse(panel: panel)

        // Sync pin/streaming state → close-on-outside-click behavior
        pinnedState.onChange = { [weak self] in
            self?.syncClickOutsideMonitor()
        }
        syncClickOutsideMonitor()

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

    private func syncClickOutsideMonitor() {
        if pinnedState.preventsAutoClose {
            removeClickOutsideMonitor()
        } else {
            addClickOutsideMonitor()
        }
    }

    private func addClickOutsideMonitor() {
        guard clickOutsideMonitor == nil else { return }
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let win = self.window else { return }
            if !win.isVisible { return }
            if self.pinnedState.preventsAutoClose { return }
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

    override func close() {
        session.cancelProcessing()
        pinnedState.setProcessing(false)
        super.close()
    }

    func updateContent(_ content: CapturedContent) {
        contentState.content = content
        contentState.isCapturing = false
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

/// Observable wrapper so SwiftUI can read/write popup session state
final class PinnedState: ObservableObject {
    @Published var pinned: Bool = false
    @Published var isProcessing: Bool = false
    var onChange: (() -> Void)?

    var preventsAutoClose: Bool { pinned || isProcessing }

    func toggle() {
        pinned.toggle()
        onChange?()
    }

    func setProcessing(_ value: Bool) {
        guard isProcessing != value else { return }
        isProcessing = value
        onChange?()
    }
}
