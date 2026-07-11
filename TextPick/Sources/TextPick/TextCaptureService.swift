import AppKit
import ApplicationServices

// MARK: - Captured Content

/// What the hotkey captured — either selected text or an image from the clipboard.
enum CapturedContent {
    case text(String)
    case image(NSImage, Data)   // NSImage for display; Data is PNG for API
}

/// Captures the currently selected text using:
/// 1. Accessibility API (AXSelectedText) — no clipboard disruption
/// 2. Clipboard image detection — if no text selected and clipboard has an image
/// 3. ⌘C simulation — sends copy to the *source* app then reads clipboard
class TextCaptureService {
    static let shared = TextCaptureService()
    private init() {}

    // MARK: - Public API (async — call from AppDelegate hotkey handler)

    /// Synchronous fast path — AX text or clipboard image. Call on main thread.
    func captureFast(from sourceApp: NSRunningApplication?) -> CapturedContent? {
        if let text = captureViaAccessibility(from: sourceApp), !text.isEmpty {
            print("[TextPick] Captured via AX: \(text.prefix(80))…")
            return .text(text)
        }
        if let (image, data) = captureImageFromClipboard() {
            print("[TextPick] Captured image from clipboard: \(data.count) bytes")
            return .image(image, data)
        }
        return nil
    }

    /// Asynchronously captures content. Calls `completion` on main thread.
    func captureContent(completion: @escaping (CapturedContent?) -> Void) {
        let sourceApp = NSWorkspace.shared.frontmostApplication

        if let content = captureFast(from: sourceApp) {
            deliver(content, to: completion)
            return
        }

        print("[TextPick] AX failed, falling back to clipboard simulation.")
        captureViaClipboard(sourceApp: sourceApp) { text in
            self.deliver(text.map { .text($0) }, to: completion)
        }
    }

    private func deliver(_ content: CapturedContent?, to completion: @escaping (CapturedContent?) -> Void) {
        if Thread.isMainThread {
            completion(content)
        } else {
            DispatchQueue.main.async { completion(content) }
        }
    }

    /// Clipboard fallback when AX already failed. Pass the original source app captured before showing UI.
    func captureClipboardFallback(from sourceApp: NSRunningApplication?, completion: @escaping (CapturedContent?) -> Void) {
        print("[TextPick] AX failed, falling back to clipboard simulation.")
        captureViaClipboard(sourceApp: sourceApp) { text in
            self.deliver(text.map { .text($0) }, to: completion)
        }
    }

    /// Legacy text-only capture (kept for compatibility)
    func captureSelectedText(completion: @escaping (String?) -> Void) {
        captureContent { content in
            if case .text(let t) = content { completion(t) }
            else { completion(nil) }
        }
    }

    // MARK: - Accessibility

    private func captureViaAccessibility(from app: NSRunningApplication?) -> String? {
        guard AXIsProcessTrusted() else {
            print("[TextPick] AX not trusted — grant Accessibility permission in System Settings")
            return nil
        }
        guard let app = app else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else { return nil }

        var selectedText: AnyObject?
        let r = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        return r == .success ? selectedText as? String : nil
    }

    // MARK: - Image Detection

    private func captureImageFromClipboard() -> (NSImage, Data)? {
        let pb = NSPasteboard.general
        // Check for image types
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff, .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
        ]
        for type in imageTypes {
            if let data = pb.data(forType: type),
               let image = NSImage(data: data) {
                // Convert to PNG for API use
                let pngData = convertToPNG(image: image, originalData: data, originalType: type)
                return (image, pngData)
            }
        }
        return nil
    }

    private func convertToPNG(image: NSImage, originalData: Data, originalType: NSPasteboard.PasteboardType) -> Data {
        // If already PNG, return as-is
        if originalType == .png { return originalData }
        // Convert via CGImage
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return originalData
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:]) ?? originalData
    }

    // MARK: - Clipboard Fallback

    private func captureViaClipboard(sourceApp: NSRunningApplication?, completion: @escaping (String?) -> Void) {
        let pb = NSPasteboard.general

        // Save current clipboard
        let saved = snapshotClipboard(pb)

        // Clear so we can detect a new write
        pb.clearContents()

        // Send ⌘C to the SOURCE app's process (not the current process)
        sendCopyEvent(to: sourceApp)

        // Poll clipboard — return as soon as copy lands (50ms intervals, 250ms max)
        pollClipboard(pb, snapshot: saved, attempt: 0, completion: completion)
    }

    private func pollClipboard(
        _ pb: NSPasteboard,
        snapshot saved: ClipboardSnapshot,
        attempt: Int,
        completion: @escaping (String?) -> Void
    ) {
        let captured = pb.string(forType: .string)
        if let text = captured, !text.isEmpty {
            restoreClipboard(pb, snapshot: saved)
            print("[TextPick] Captured via clipboard: \(text.prefix(80))…")
            completion(text)
            return
        }
        if attempt >= 5 {
            restoreClipboard(pb, snapshot: saved)
            print("[TextPick] No text captured.")
            completion(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.pollClipboard(pb, snapshot: saved, attempt: attempt + 1, completion: completion)
        }
    }

    /// Sends a ⌘C keystroke targeted at `app`'s process.
    /// When targeting a specific PID the event goes there even if it's not frontmost.
    private func sendCopyEvent(to app: NSRunningApplication?) {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)!
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)!
        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand

        if let pid = app?.processIdentifier {
            // Target the source app directly — bypasses whoever currently has focus
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Clipboard Save/Restore

    private struct ClipboardSnapshot {
        let changeCount: Int
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private func snapshotClipboard(_ pb: NSPasteboard) -> ClipboardSnapshot {
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pb.pasteboardItems ?? [] {
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            items.append(dict)
        }
        return ClipboardSnapshot(changeCount: pb.changeCount, items: items)
    }

    private func restoreClipboard(_ pb: NSPasteboard, snapshot: ClipboardSnapshot) {
        pb.clearContents()
        for itemDict in snapshot.items {
            let item = NSPasteboardItem()
            for (type, data) in itemDict { item.setData(data, forType: type) }
            pb.writeObjects([item])
        }
    }
}
