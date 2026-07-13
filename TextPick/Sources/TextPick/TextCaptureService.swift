import AppKit
import ApplicationServices

// MARK: - Captured Content

/// What the hotkey captured — either selected text or an image from the clipboard.
enum CapturedContent {
    case text(String)
    case image(NSImage, Data)   // NSImage for display; Data is PNG for API
}

enum CaptureMethod: String {
    case axFirst = "ax_first"
    case clipboard = "clipboard"
    case axOnly = "ax_only"

    static var current: CaptureMethod {
        CaptureMethod(rawValue: UserDefaults.standard.string(forKey: "textpick.captureMethod") ?? "ax_first") ?? .axFirst
    }
}

/// Captures the currently selected text using:
/// 1. Accessibility API (AXSelectedText) — no clipboard disruption
/// 2. ⌘C simulation — sends copy to the *source* app then reads clipboard
/// 3. Clipboard image — only when no text could be captured
class TextCaptureService {
    static let shared = TextCaptureService()
    private init() {}

    // MARK: - Public API

    /// Synchronous fast path — AX text only. Call on main thread.
    func captureFast(from sourceApp: NSRunningApplication?) -> CapturedContent? {
        guard CaptureMethod.current != .clipboard else { return nil }
        if let text = captureViaAccessibility(from: sourceApp), !text.isEmpty {
            print("[TextPick] Captured via AX: \(text.prefix(80))…")
            return .text(text)
        }
        return nil
    }

    /// Reads selected text via AX for selection monitoring (no clipboard side effects).
    func readSelectedText(from sourceApp: NSRunningApplication?) -> String? {
        captureViaAccessibility(from: sourceApp)
    }

    /// Full async capture: text first (respecting capture method), then clipboard image.
    func capture(from sourceApp: NSRunningApplication?, completion: @escaping (CapturedContent?) -> Void) {
        captureText(from: sourceApp) { text in
            if let text, !text.isEmpty {
                self.deliver(.text(text), to: completion)
                return
            }
            if let (image, data) = self.captureImageFromClipboard() {
                print("[TextPick] Captured image from clipboard: \(data.count) bytes")
                self.deliver(.image(image, data), to: completion)
                return
            }
            self.deliver(nil, to: completion)
        }
    }

    /// Legacy alias used by AppDelegate slow path.
    func captureClipboardFallback(from sourceApp: NSRunningApplication?, completion: @escaping (CapturedContent?) -> Void) {
        capture(from: sourceApp, completion: completion)
    }

    /// Legacy text-only capture (kept for compatibility)
    func captureSelectedText(completion: @escaping (String?) -> Void) {
        capture(from: NSWorkspace.shared.frontmostApplication) { content in
            if case .text(let t) = content { completion(t) }
            else { completion(nil) }
        }
    }

    // MARK: - Text Capture

    private func captureText(from sourceApp: NSRunningApplication?, completion: @escaping (String?) -> Void) {
        switch CaptureMethod.current {
        case .axFirst:
            if let text = captureViaAccessibility(from: sourceApp), !text.isEmpty {
                print("[TextPick] Captured via AX: \(text.prefix(80))…")
                completion(text)
                return
            }
            print("[TextPick] AX failed, falling back to clipboard simulation.")
            captureViaClipboard(sourceApp: sourceApp, completion: completion)

        case .clipboard:
            print("[TextPick] Using clipboard simulation.")
            captureViaClipboard(sourceApp: sourceApp, completion: completion)

        case .axOnly:
            completion(captureViaAccessibility(from: sourceApp))
        }
    }

    private func deliver(_ content: CapturedContent?, to completion: @escaping (CapturedContent?) -> Void) {
        if Thread.isMainThread {
            completion(content)
        } else {
            DispatchQueue.main.async { completion(content) }
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

        let axElement = element as! AXUIElement

        // Primary: selected text attribute (native apps, TextEdit, Safari partially).
        var selectedText: AnyObject?
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedText) == .success,
           let text = selectedText as? String, !text.isEmpty {
            return text
        }

        // Fallback: selected range + full value substring (Chromium browsers, web content).
        return selectedTextViaRange(in: axElement)
    }

    /// Reads the selected text by combining `kAXSelectedTextRangeAttribute` with `kAXValueAttribute`.
    /// Works for Chromium-based browsers that don't expose `kAXSelectedTextAttribute` directly.
    private func selectedTextViaRange(in element: AXUIElement) -> String? {
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else { return nil }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.length > 0 else { return nil }

        var fullValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &fullValue) == .success,
              let fullText = fullValue as? String else { return nil }

        guard range.location >= 0, range.location + range.length <= fullText.count else { return nil }
        let start = fullText.index(fullText.startIndex, offsetBy: range.location)
        let end = fullText.index(start, offsetBy: range.length)
        return String(fullText[start..<end])
    }

    // MARK: - Image Detection

    private func captureImageFromClipboard() -> (NSImage, Data)? {
        let pb = NSPasteboard.general
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff, .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
        ]
        for type in imageTypes {
            if let data = pb.data(forType: type),
               let image = NSImage(data: data) {
                let pngData = convertToPNG(image: image, originalData: data, originalType: type)
                return (image, pngData)
            }
        }
        return nil
    }

    private func convertToPNG(image: NSImage, originalData: Data, originalType: NSPasteboard.PasteboardType) -> Data {
        if originalType == .png { return originalData }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return originalData
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:]) ?? originalData
    }

    // MARK: - Clipboard Fallback

    private func captureViaClipboard(sourceApp: NSRunningApplication?, completion: @escaping (String?) -> Void) {
        let pb = NSPasteboard.general
        let saved = snapshotClipboard(pb)
        pb.clearContents()
        sendCopyEvent(to: sourceApp)
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

    private func sendCopyEvent(to app: NSRunningApplication?) {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)!
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)!
        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand

        if let pid = app?.processIdentifier {
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
