import SwiftUI
import AppKit

// MARK: - Main Popup View

struct PopupView: View {
    @ObservedObject var contentState: CapturedContentState
    @ObservedObject var pinnedState: PinnedState
    let session: PopupSession
    let displayMode: PopupDisplayMode
    let onClose: () -> Void
    var onExpandFromCompact: (() -> Void)? = nil

    @ObservedObject private var store = ActionsStore.shared

    // General settings
    @AppStorage("textpick.fontSize")        private var fontSize:       Double = 13
    @AppStorage("textpick.popupWidth")      private var popupWidthPref: Double = 420
    @AppStorage("textpick.autoCopy")        private var autoCopy:       Bool   = false
    @AppStorage("textpick.showInputText")   private var showInputText:  Bool   = true
    @AppStorage("textpick.switchToResult")  private var switchToResult: Bool   = true
    @AppStorage("textpick.closeOnEsc")      private var closeOnEsc:     Bool   = true
    @State private var result: String = ""
    @State private var thinking: String = ""
    @State private var isThinkingExpanded: Bool = false
    @State private var isProcessing: Bool = false
    @State private var costEstimate: String? = nil
    @State private var activeActionID: UUID? = nil
    @State private var followUpQuestion: String = ""
    /// Conversation history for follow-up. Reassigned (not appended in place) to trigger @State updates.
    @State private var messages: [[String: Any]] = []
    @State private var savedFilePath: URL? = nil
    @State private var saveError: String? = nil
    @State private var copyFeedback: Bool = false
    @State private var expandedFromCompact: Bool = false

    // Which content is shown in the shared text region
    private enum ContentMode { case input, result }
    @State private var contentMode: ContentMode = .input

    private var content: CapturedContent { contentState.content }

    private var isImageMode: Bool {
        if case .image = content { return true }
        return false
    }

    private var capturedText: String {
        if case .text(let t) = content { return t }
        return ""
    }

    private var enabledActions: [TextAction] {
        store.actions.filter(\.isEnabled)
    }

    private var enabledVisionActions: [TextAction] {
        store.visionActions.filter(\.isEnabled)
    }

    private var isCompactLayout: Bool {
        displayMode == .compact && !expandedFromCompact && !isProcessing && result.isEmpty
    }

    var body: some View {
        Group {
            if isCompactLayout {
                compactBody
            } else {
                fullBody
            }
        }
        .onAppear {
            setupKeyCopyMonitor()
        }
        .onDisappear {
            removeKeyCopyMonitor()
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            // Shared content region: input text/image ↔ result
            if showInputText || contentMode == .result || isProcessing {
                contentRegion
                Divider()
            }
            if isImageMode {
                visionActionButtonsView
            } else {
                actionButtonsView
            }
            Divider()
            followUpView
        }
        .frame(width: CGFloat(popupWidthPref > 0 ? popupWidthPref : 420))
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var compactBody: some View {
        HStack(spacing: 4) {
            if isImageMode {
                visionActionButtonsView
            } else {
                actionButtonsView
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 8) {
            if isImageMode {
                Image(systemName: "photo")
                    .foregroundStyle(.purple)
                    .font(.system(size: 13))
                Text("TextPick · Image")
                    .font(.system(size: 13, weight: .semibold))
            } else {
                Image(systemName: "text.cursor")
                    .foregroundStyle(.blue)
                    .font(.system(size: 13))
                Text("TextPick")
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()

            // Tab switcher — only show when result is available
            if !result.isEmpty || isProcessing {
                Picker("", selection: $contentMode) {
                    Text(isImageMode ? "Image" : "Input").tag(ContentMode.input)
                    Text("Result").tag(ContentMode.result)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .labelsHidden()
            }

            // Copy button — visible only when result is available
            if contentMode == .result && !result.isEmpty {
                Button(action: copyResult) {
                    ZStack {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                            .opacity(copyFeedback ? 1 : 0)
                            .scaleEffect(copyFeedback ? 1 : 0.5)

                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .opacity(copyFeedback ? 0 : 1)
                            .scaleEffect(copyFeedback ? 0.5 : 1)
                    }
                    .frame(width: 16, height: 16)
                    .animation(.spring(duration: 0.2), value: copyFeedback)
                }
                .buttonStyle(.plain)
                .help("Copy result (C)")
            }

            if isProcessing {
                Button {
                    session.cancelProcessing()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Stop generating")
            }

            // Close button — always functional, even during streaming
            Button(action: {
                session.cancelProcessing()
                onClose()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")

            // Pin button
            Button(action: { pinnedState.toggle() }) {
                Image(systemName: pinnedState.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundStyle(pinnedState.pinned ? .blue : .secondary)
                    .rotationEffect(.degrees(45))
            }
            .buttonStyle(.plain)
            .help(pinnedState.pinned ? "Unpin (auto-close on click away)" : "Pin (keep open while streaming or pinned)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Shared Content Region

    private var contentRegion: some View {
        Group {
            // Keep only one scroll view alive. The old opacity-based ZStack kept
            // both input and result trees active, which made every stream update
            // do roughly twice the layout work.
            if contentMode == .input {
                inputContentView
            } else {
                resultContentView
            }
        }
        .frame(minHeight: isImageMode ? 140 : 96, maxHeight: isImageMode ? 260 : 240)
        .animation(.easeInOut(duration: 0.18), value: contentMode)
    }

    @ViewBuilder
    private var inputContentView: some View {
        switch content {
        case .text(let text):
            if contentState.isCapturing && text.isEmpty {
                Text("Capturing selection…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
                    .background(Color.primary.opacity(0.03))
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(size: CGFloat(fontSize)))
                        .foregroundStyle(.primary.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .background(Color.primary.opacity(0.03))
            }

        case .image(let image, _):
            imagePreviewView(image: image)
        }
    }

    private func imagePreviewView(image: NSImage) -> some View {
        ZStack {
            Color.black.opacity(0.06)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .cornerRadius(6)
                .padding(10)
        }
    }

    private var resultContentView: some View {
        Group {
            if isProcessing && result.isEmpty && thinking.isEmpty {
                Text("Processing…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.03))
            } else if !result.isEmpty || !thinking.isEmpty || isProcessing {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if !thinking.isEmpty {
                                thinkingSection
                            }
                            if !result.isEmpty || (isProcessing && thinking.isEmpty) {
                                resultBodyView
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else if isProcessing && !thinking.isEmpty {
                                Text("Generating…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Spacer()
                                if let savedURL = savedFilePath {
                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                                    } label: {
                                        Label("Show in Finder", systemImage: "folder")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .tint(.green)
                                }
                                if let cost = costEstimate {
                                    Text(cost)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                if let errMsg = saveError {
                                    Text(errMsg)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        .padding(12)
                        .id("result-bottom")
                    }
                    .onChange(of: result) { _ in
                        guard isProcessing else { return }
                        // Streaming updates are deliberately not animated. A
                        // scroll animation per token makes long answers feel
                        // laggy and can fight the user's own scrolling.
                        proxy.scrollTo("result-bottom", anchor: .bottom)
                    }
                    .onChange(of: thinking) { _ in
                        guard isProcessing else { return }
                        proxy.scrollTo("result-bottom", anchor: .bottom)
                    }
                    .onChange(of: isProcessing) { processing in
                        if !processing {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo("result-bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .background(Color.primary.opacity(0.03))
            } else {
                Color.clear
            }
        }
    }

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tappable label row
            HStack(spacing: 6) {
                Image(systemName: isThinkingExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                Text("Thinking")
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isThinkingExpanded.toggle()
                }
            }
            .padding(.vertical, 4)

            // Collapsible content
            if isThinkingExpanded {
                Text(thinking)
                    .font(.system(size: CGFloat(max(fontSize - 1, 11))))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var resultBodyView: some View {
        // Markdown is rendered during streaming too. SSE updates are already
        // coalesced in TextProcessingService, so this stays responsive while
        // avoiding the confusing transition from raw syntax to formatted text.
        MarkdownResultView(markdown: result, fontSize: CGFloat(fontSize))
    }

    // MARK: - Action Buttons (text mode)

    private var actionButtonsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(enabledActions) { action in
                    ActionButton(
                        action: action,
                        isActive: activeActionID == action.id,
                        isLoading: isProcessing && activeActionID == action.id
                    ) {
                        runTextAction(action)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Vision Action Buttons (image mode)

    private var visionActionButtonsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(enabledVisionActions) { action in
                    ActionButton(
                        action: action,
                        isActive: activeActionID == action.id,
                        isLoading: isProcessing && activeActionID == action.id
                    ) {
                        runVisionAction(action)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Follow-up Input

    private var followUpView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                TextField(
                    followUpPlaceholder,
                    text: $followUpQuestion
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { runFollowUp() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: runFollowUp) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(canSubmitFollowUp ? (isImageMode ? .purple : .blue) : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitFollowUp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var followUpPlaceholder: String {
        if messages.isEmpty {
            return isImageMode ? "Ask anything about this image…" : "Ask anything about the selected text…"
        }
        return isImageMode ? "Ask a follow-up about this image…" : "Ask a follow-up about the result…"
    }

    private var canSubmitFollowUp: Bool {
        !followUpQuestion.trimmingCharacters(in: .whitespaces).isEmpty
            && !isProcessing
    }

    // MARK: - Key Monitor

    @State private var keyCopyMonitor: Any? = nil

    private func setupKeyCopyMonitor() {
        removeKeyCopyMonitor()
        keyCopyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 'c' keyCode == 8, no modifier keys
            if event.keyCode == 8
                && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
                && self.contentMode == .result
                && !self.result.isEmpty {
                // Don't intercept while a text field has focus (let it receive the keystroke)
                if let fr = event.window?.firstResponder, fr is NSText {
                    return event
                }
                self.copyResult()
                return nil  // consume event
            }
            return event
        }
    }

    private func removeKeyCopyMonitor() {
        if let m = keyCopyMonitor { NSEvent.removeMonitor(m); keyCopyMonitor = nil }
    }

    // MARK: - Copy Helper

    private func copyResult() {
        guard !result.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        withAnimation(.spring(duration: 0.2)) { copyFeedback = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(duration: 0.2)) { copyFeedback = false }
        }
    }

    // MARK: - Processing Helpers

    private func applyStreamUpdate(_ update: TextProcessingService.StreamResult) {
        thinking = update.thinking
        result = update.content
    }

    private func beginProcessing(actionID: UUID? = nil, resetSavedFile: Bool = false, _ work: @escaping () async -> Void) {
        session.cancelProcessing()
        activeActionID = actionID
        isProcessing = true
        pinnedState.setProcessing(true)
        if displayMode == .compact && !expandedFromCompact {
            expandedFromCompact = true
            onExpandFromCompact?()
        }
        result = ""
        thinking = ""
        isThinkingExpanded = false
        costEstimate = nil
        if resetSavedFile {
            savedFilePath = nil
            saveError = nil
        }
        if switchToResult { contentMode = .result }

        session.processingTask = Task { @MainActor in
            defer {
                isProcessing = false
                pinnedState.setProcessing(false)
            }
            await work()
        }
    }

    // MARK: - Handlers (text)

    private func runTextAction(_ action: TextAction) {
        let prompt = action.renderPrompt(with: capturedText)
        let initial: [[String: Any]] = [
            ["role": "system", "content": prompt]
        ]
        messages = initial
        beginProcessing(actionID: action.id) {
            let streamResult = await TextProcessingService.shared.processMessagesStreaming(messages: initial) { update in
                applyStreamUpdate(update)
            }
            guard !Task.isCancelled else { return }
            let usedModel = await TextProcessingService.shared.model
            result = streamResult.content
            thinking = streamResult.thinking
            contentMode = .result
            messages = initial + [["role": "assistant", "content": streamResult.content]]
            HistoryStore.shared.add(sourceText: capturedText, actionName: action.label, fullPrompt: prompt, result: streamResult.content, modelName: usedModel)
            if autoCopy { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(streamResult.content, forType: .string) }
            costEstimate = Self.computeCost(modelID: usedModel, input: prompt, output: streamResult.content)
        }
    }

    /// Send a follow-up turn. If no action has been run yet, build a default user message
    /// from the captured text/image (text mode: "背景：.../问题：..."; image mode: image+question
    /// content parts). Otherwise append a plain text turn to the existing chain.
    private func runFollowUp() {
        let question = followUpQuestion.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty, !isProcessing else { return }

        let chain: [[String: Any]]
        let historyPrompt: String
        let historySource: String
        let historyAction: String

        if messages.isEmpty {
            // No action clicked — direct ask using the captured content as context.
            if isImageMode, case .image(_, let data) = content {
                let base64 = data.base64EncodedString()
                let imageURL = "data:image/png;base64,\(base64)"
                let userContent: [[String: Any]] = [
                    ["type": "image_url", "image_url": ["url": imageURL]],
                    ["type": "text", "text": "问题：\(question)"],
                ]
                chain = [["role": "user", "content": userContent]]
                historySource = "[Image]"
            } else {
                let body = capturedText.isEmpty
                    ? question
                    : "背景：\(capturedText)\n问题：\(question)"
                chain = [["role": "user", "content": body]]
                historySource = capturedText
            }
            historyPrompt = question
            historyAction = "Direct Ask"
        } else {
            chain = messages + [["role": "user", "content": question]]
            historySource = "[Follow-up]"
            historyPrompt = question
            historyAction = "Follow-up"
        }

        followUpQuestion = ""
        beginProcessing {
            let streamResult = await TextProcessingService.shared.processMessagesStreaming(messages: chain) { update in
                applyStreamUpdate(update)
            }
            guard !Task.isCancelled else { return }
            let hasVision = chain.contains { ($0["content"] as? [[String: Any]]) != nil }
            let usedModel = hasVision
                ? await TextProcessingService.shared.visionModel
                : await TextProcessingService.shared.model
            result = streamResult.content
            thinking = streamResult.thinking
            contentMode = .result
            messages = chain + [["role": "assistant", "content": streamResult.content]]
            HistoryStore.shared.add(sourceText: historySource, actionName: historyAction, fullPrompt: historyPrompt, result: streamResult.content, modelName: usedModel)
            if autoCopy { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(streamResult.content, forType: .string) }
            costEstimate = Self.computeCost(modelID: usedModel, input: historyPrompt, output: streamResult.content)
        }
    }

    // MARK: - Handlers (vision)

    private func runVisionAction(_ action: TextAction) {
        guard case .image(_, let data) = content else { return }
        let prompt = action.renderPrompt(with: "")
        let base64 = data.base64EncodedString()
        let imageURL = "data:image/png;base64,\(base64)"
        let userContent: [[String: Any]] = [
            ["type": "image_url", "image_url": ["url": imageURL]],
            ["type": "text", "text": ""]
        ]
        let initial: [[String: Any]] = [
            ["role": "system", "content": prompt],
            ["role": "user", "content": userContent]
        ]
        messages = initial
        beginProcessing(actionID: action.id, resetSavedFile: true) {
            let streamResult = await TextProcessingService.shared.processMessagesStreaming(messages: initial) { update in
                applyStreamUpdate(update)
            }
            guard !Task.isCancelled else { return }
            let usedModel = await TextProcessingService.shared.visionModel
            result = streamResult.content
            thinking = streamResult.thinking
            contentMode = .result
            messages = initial + [["role": "assistant", "content": streamResult.content]]
            HistoryStore.shared.add(sourceText: "[Image]", actionName: action.label, fullPrompt: prompt, result: streamResult.content, modelName: usedModel)
            if autoCopy { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(streamResult.content, forType: .string) }
            costEstimate = Self.computeCost(modelID: usedModel, input: prompt, output: streamResult.content)
            if action.saveToFile {
                switch saveResultToFile(result: streamResult.content, action: action) {
                case .success(let url): savedFilePath = url
                case .failure(let err): saveError = "Save failed: \(err.localizedDescription)"
                }
            }
        }
    }

    // MARK: - File Save Helper

    private func saveResultToFile(result: String, action: TextAction) -> Result<URL, Error> {
        // Resolve save directory
        let dirPath = action.saveDirectory.isEmpty
            ? (NSString(string: "~/Pictures/TextPick").expandingTildeInPath)
            : (NSString(string: action.saveDirectory).expandingTildeInPath)
        let dirURL = URL(fileURLWithPath: dirPath)

        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            return .failure(error)
        }

        // Build filename
        let timestamp: String = {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            return fmt.string(from: Date())
        }()

        let descriptionPart: String = {
            // First non-empty line of result, max 60 chars, sanitized
            let firstLine = result.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first(where: { !$0.isEmpty }) ?? "untitled"
            let truncated = String(firstLine.prefix(60))
            // Remove chars invalid in filenames
            let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
            return truncated.components(separatedBy: invalid).joined(separator: "-")
        }()

        let baseName: String
        switch action.filenameFormat {
        case .descriptionOnly:      baseName = descriptionPart
        case .timestampOnly:        baseName = timestamp
        case .timestampDescription: baseName = "\(timestamp)_\(descriptionPart)"
        }

        var fileURL = dirURL.appendingPathComponent(baseName).appendingPathExtension("md")
        // Avoid overwrite — append counter if needed
        var counter = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = dirURL.appendingPathComponent("\(baseName)_\(counter)").appendingPathExtension("md")
            counter += 1
        }

        do {
            try result.write(to: fileURL, atomically: true, encoding: .utf8)
            return .success(fileURL)
        } catch {
            return .failure(error)
        }
    }

    private static func computeCost(modelID: String, input: String, output: String) -> String? {
        guard let cost = TextProcessingService.estimateCost(modelID: modelID, inputText: input, outputText: output) else { return nil }
        return TextProcessingService.formatCost(cost)
    }
}

// MARK: - Markdown Result

/// Native Foundation Markdown rendering keeps the app lightweight while
/// supporting headings, emphasis, links, lists, block quotes, and code spans.
/// The fallback preserves the raw response if a provider returns malformed
/// Markdown.
struct MarkdownResultView: View {
    let markdown: String
    let fontSize: CGFloat

    @State private var renderedText: AttributedString

    init(markdown: String, fontSize: CGFloat = 13) {
        self.markdown = markdown
        self.fontSize = fontSize
        _renderedText = State(initialValue: Self.parse(markdown))
    }

    var body: some View {
        Text(renderedText)
            .font(.system(size: fontSize))
            .lineSpacing(3)
            .textSelection(.enabled)
            .tint(.accentColor)
            .onChange(of: markdown) { newValue in
                renderedText = Self.parse(newValue)
            }
    }

    private static func parse(_ value: String) -> AttributedString {
        let normalized = value
            // Some gateways/models return escaped line breaks in the content
            // string instead of actual newlines. Markdown needs real newlines
            // for paragraphs, lists, and fenced code blocks.
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")

        // Markdown treats single \n as soft wrap (space). Convert single
        // newlines to hard breaks (two trailing spaces) so LLM output preserves
        // line structure. Skip inside fenced code blocks (``` ... ```).
        let paragraphs = normalized.components(separatedBy: "\n\n")
        let hardened = paragraphs.map { para -> String in
            // Don't touch fenced code blocks
            if para.hasPrefix("```") { return para }
            // Single \n → hard break (two spaces before \n)
            return para.replacingOccurrences(of: "\n", with: "  \n")
        }.joined(separator: "\n\n")

        return (try? AttributedString(markdown: hardened)) ?? AttributedString(hardened)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let action: TextAction
    let isActive: Bool
    let isLoading: Bool
    var isDisabled: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.65)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: action.icon).font(.system(size: 11))
                }
                Text(action.label).font(.system(size: 11))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
        }
        .buttonStyle(.bordered)
        .tint(isActive || isLoading ? .blue : nil)
        .controlSize(.mini)
        .disabled(isLoading || isDisabled)
    }
}
