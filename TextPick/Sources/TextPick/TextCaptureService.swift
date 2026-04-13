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

    /// Asynchronously captures content. Calls `completion` on main thread.
    func captureContent(completion: @escaping (CapturedContent?) -> Void) {
        // Snapshot the frontmost app NOW, before TextPick gets involved
        let sourceApp = NSWorkspace.shared.frontmostApplication

        // 1. Try AX for text selection — instant, no side effects
        if let text = captureViaAccessibility(from: sourceApp), !text.isEmpty {
            print("[TextPick] Captured via AX: \(text.prefix(80))…")
            DispatchQueue.main.async { completion(.text(text)) }
            return
        }

        // 2. Check clipboard for an image (user copied/screenshotted something)
        if let (image, data) = captureImageFromClipboard() {
            print("[TextPick] Captured image from clipboard: \(data.count) bytes")
            DispatchQueue.main.async { completion(.image(image, data)) }
            return
        }

        // 3. Fall back to ⌘C clipboard simulation
        print("[TextPick] AX failed, falling back to clipboard simulation.")
        captureViaClipboard(sourceApp: sourceApp) { text in
            if let text = text {
                completion(.text(text))
            } else {
                completion(nil)
            }
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

        // Wait async — don't block main thread
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let captured = pb.string(forType: .string)

            // Restore original clipboard
            self.restoreClipboard(pb, snapshot: saved)

            if let text = captured, !text.isEmpty {
                print("[TextPick] Captured via clipboard: \(text.prefix(80))…")
                completion(text)
            } else {
                print("[TextPick] No text captured.")
                completion(nil)
            }
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
