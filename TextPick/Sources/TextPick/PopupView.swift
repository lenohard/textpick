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
    @AppStorage("textpick.customPromptTemplate") private var customPromptTemplate: String = PromptTemplate.defaultCustomTemplate

    @State private var result: String = ""
    @State private var thinking: String = ""
    @State private var isThinkingExpanded: Bool = false
    @State private var isProcessing: Bool = false
    @State private var costEstimate: String? = nil
    @State private var activeActionID: UUID? = nil
    @State private var customPrompt: String = ""
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
            customPromptView
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
        ZStack(alignment: .topLeading) {
            // Input: text or image
            inputContentView
                .opacity(contentMode == .input ? 1 : 0)

            // Result / processing
            resultContentView
                .opacity(contentMode == .result ? 1 : 0)
        }
        .frame(minHeight: isImageMode ? 140 : 80, maxHeight: isImageMode ? 260 : 200)
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
                        withAnimation { proxy.scrollTo("result-bottom", anchor: .bottom) }
                    }
                    .onChange(of: thinking) { _ in
                        withAnimation { proxy.scrollTo("result-bottom", anchor: .bottom) }
                    }
                }
                .background(Color.primary.opacity(0.03))
            } else {
                Color.clear
            }
        }
    }

    private var thinkingSection: some View {
        DisclosureGroup(isExpanded: $isThinkingExpanded) {
            Text(thinking)
                .font(.system(size: CGFloat(max(fontSize - 1, 11))))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                Text("Thinking")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }

    @ViewBuilder
    private var resultBodyView: some View {
        Text(result)
            .font(.system(size: CGFloat(fontSize)))
            .lineSpacing(3)
            .textSelection(.enabled)
    }

    // MARK: - Action Buttons (text mode)

    private var actionButtonsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(enabledActions) { action in
                    ActionButton(
                        action: action,
                        isActive: activeActionID == action.id,
                        isLoading: isProcessing && activeActionID == action.id,
                        isDisabled: action.requiresUserInput && customPrompt.trimmingCharacters(in: .whitespaces).isEmpty
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
                        isLoading: isProcessing && activeActionID == action.id,
                        isDisabled: action.requiresUserInput && customPrompt.trimmingCharacters(in: .whitespaces).isEmpty
                    ) {
                        runVisionAction(action)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Custom Prompt

    private var customPromptView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isImageMode ? "questionmark.bubble" : "pencil.and.sparkles")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                TextField(
                    isImageMode ? "Ask about this image…" : "Custom instruction for the selected text…",
                    text: $customPrompt
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit {
                    if isImageMode { runCustomVisionPrompt() }
                    else { runCustomPrompt() }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: { if isImageMode { runCustomVisionPrompt() } else { runCustomPrompt() } }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(canSubmitCustom ? (isImageMode ? .purple : .blue) : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitCustom)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var canSubmitCustom: Bool {
        !customPrompt.trimmingCharacters(in: .whitespaces).isEmpty && !isProcessing
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
        let userInput = customPrompt.trimmingCharacters(in: .whitespaces)
        let prompt = action.renderPrompt(with: capturedText, userInput: userInput)
        beginProcessing(actionID: action.id) {
            let streamResult = await TextProcessingService.shared.processStreaming(prompt) { update in
                applyStreamUpdate(update)
            }
            guard !Task.isCancelled else { return }
            let usedModel = await TextProcessingService.shared.model
            result = streamResult.content
            thinking = streamResult.thinking
            contentMode = .result
            HistoryStore.shared.add(sourceText: capturedText, actionName: action.label, fullPrompt: prompt, result: streamResult.content, modelName: usedModel)
            if autoCopy { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(streamResult.content, forType: .string) }
            costEstimate = Self.computeCost(modelID: usedModel, input: prompt, output: streamResult.content)
        }
    }

    private func runCustomPrompt() {
        let userInput = customPrompt.trimmingCharacters(in: .whitespaces)
        guard !userInput.isEmpty else { return }
        let template = customPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? PromptTemplate.defaultCustomTemplate
            : customPromptTemplate
        let prompt = PromptTemplate.render(template, text: capturedText, userInput: userInput)
        beginProcessing {
            let streamResult = await TextProcessingService.shared.processStreaming(prompt) { update in
                applyStreamUpdate(update)
            }
            guard !Task.isCancelled else { return }
            let usedModel = await TextProcessingService.shared.model
            result = streamResult.content
            thinking = streamResult.thinking
            contentMode = .result
            HistoryStore.shared.add(sourceText: capturedText, actionName: "Custom", fullPrompt: prompt, result: streamResult.content, modelName: usedModel)
            if autoCopy { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(streamResult.content, forType: .string) }
            costEstimate = Self.computeCost(modelID: usedModel, input: prompt, output: streamResult.content)
        }
    }

    // MARK: - Handlers (vision)

    private func runVisionAction(_ action: TextAction) {
        guard case .image(_, let data) = content else { return }
        let userInput = customPrompt.trimmingCharacters(in: .whitespaces)
        let prompt = action.renderPrompt(with: "", userInput: userInput)
        beginProcessing(actionID: action.id, resetSavedFile: true) {
            let streamResult = await TextProcessingService.shared.processImageStreaming(imageData: data, prompt: prompt) { update in
                applyStreamUpdate(update)
            }
            guard !Task.isCancelled else { return }
            let usedModel = await TextProcessingService.shared.visionModel
            result = streamResult.content
            thinking = streamResult.thinking
            contentMode = .result
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

    private func runCustomVisionPrompt() {
        guard case .image(_, let data) = content else { return }
        let userInput = customPrompt.trimmingCharacters(in: .whitespaces)
        guard !userInput.isEmpty else { return }
        let template = customPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? PromptTemplate.defaultCustomTemplate
            : customPromptTemplate
        let prompt = PromptTemplate.render(template, text: "", userInput: userInput)
        beginProcessing {
            let streamResult = await TextProcessingService.shared.processImageStreaming(imageData: data, prompt: prompt) { update in
                applyStreamUpdate(update)
            }
            guard !Task.isCancelled else { return }
            let usedModel = await TextProcessingService.shared.visionModel
            result = streamResult.content
            thinking = streamResult.thinking
            contentMode = .result
            HistoryStore.shared.add(sourceText: "[Image]", actionName: "Custom Vision", fullPrompt: prompt, result: streamResult.content, modelName: usedModel)
            if autoCopy { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(streamResult.content, forType: .string) }
            costEstimate = Self.computeCost(modelID: usedModel, input: prompt, output: streamResult.content)
        }
    }

    private static func computeCost(modelID: String, input: String, output: String) -> String? {
        guard let cost = TextProcessingService.estimateCost(modelID: modelID, inputText: input, outputText: output) else { return nil }
        return TextProcessingService.formatCost(cost)
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
            HStack(spacing: 2) {
                Image(systemName: action.icon).font(.system(size: 11))
                Text(action.label).font(.system(size: 11))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(isActive || isLoading ? .blue : nil)
        .controlSize(.mini)
        .disabled(isLoading || isDisabled)
    }
}
