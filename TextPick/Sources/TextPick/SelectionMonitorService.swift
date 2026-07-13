import AppKit

enum SelectionTriggerStyle: String {
    case compact = "compact"
    case popup = "popup"

    static var current: SelectionTriggerStyle {
        SelectionTriggerStyle(rawValue: UserDefaults.standard.string(forKey: "textpick.selectionTriggerStyle") ?? "compact") ?? .compact
    }
}

/// Polls AX selected text and auto-shows the popup when a selection stabilizes.
final class SelectionMonitorService {
    static let shared = SelectionMonitorService()

    var onSelectionReady: ((String) -> Void)?
    var onSelectionCleared: (() -> Void)?

    private var timer: Timer?
    private var pendingText: String?
    private var pendingSince: Date?
    private var lastShownText: String?
    private var lastLoggedApp: String?
    private var lastPolledText: String?  // dedupe per-poll noise

    private let debounceInterval: TimeInterval = 0.55
    private let minimumLength = 2

    private init() {}

    func start() {
        guard timer == nil else { return }
        syncEnabledState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pendingText = nil
        pendingSince = nil
    }

    /// Clears the last-shown cache so the same selection can re-trigger after the popup closes.
    func resetLastShown() {
        lastShownText = nil
    }

    @objc private func settingsChanged() {
        syncEnabledState()
    }

    private func syncEnabledState() {
        let enabled = UserDefaults.standard.bool(forKey: "textpick.autoShowOnSelection")
        print("[TextPick] SelectionMonitor syncEnabled: \(enabled)")
        if enabled {
            startPolling()
        } else {
            stopPolling()
            lastShownText = nil
        }
    }

    private func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        pendingText = nil
        pendingSince = nil
    }

    private func poll() {
        guard UserDefaults.standard.bool(forKey: "textpick.autoShowOnSelection") else { return }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let bid = frontApp?.bundleIdentifier ?? "nil"
        if bid != lastLoggedApp {
            lastLoggedApp = bid
            print("[TextPick] SelectionMonitor frontApp=\(bid) AXisProcessTrusted=\(AXIsProcessTrusted())")
        }
        if bid == Bundle.main.bundleIdentifier { return }

        let selected = TextCaptureService.shared.readSelectedText(from: frontApp)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if selected != lastPolledText {
            lastPolledText = selected
            print("[TextPick] SelectionMonitor poll: selectedLen=\(selected.count) sel=\"\(selected.prefix(40))\"")
        }

        if selected.count < minimumLength {
            if pendingText != nil {
                pendingText = nil
                pendingSince = nil
            }
            if lastShownText != nil {
                lastShownText = nil
                onSelectionCleared?()
            }
            return
        }

        if selected == lastShownText { return }

        if selected != pendingText {
            pendingText = selected
            pendingSince = Date()
            return
        }

        guard let pendingSince, Date().timeIntervalSince(pendingSince) >= debounceInterval else { return }

        print("[TextPick] SelectionMonitor fired: \"\(selected.prefix(60))\" (len=\(selected.count))")
        lastShownText = selected
        pendingText = nil
        self.pendingSince = nil
        onSelectionReady?(selected)
    }
}
