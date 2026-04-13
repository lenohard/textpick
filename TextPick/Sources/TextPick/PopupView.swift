import SwiftUI
import AppKit

// MARK: - Main Popup View

struct PopupView: View {
    let content: CapturedContent
    @ObservedObject var pinnedState: PinnedState
    let onClose: () -> Void

    @ObservedObject private var store = ActionsStore.shared

    // General settings
    @AppStorage("textpick.fontSize")        private var fontSize:       Double = 13
    @AppStorage("textpick.popupWidth")      private var popupWidthPref: Double = 420
    @AppStorage("textpick.autoCopy")        private var autoCopy:       Bool   = false
    @AppStorage("textpick.showInputText")   private var showInputText:  Bool   = true
    @AppStorage("textpick.switchToResult")  private var switchToResult: Bool   = true
    @AppStorage("textpick.closeOnEsc")      private var closeOnEsc:     Bool   = true

    @State private var result: String = ""
    @State private var isProcessing: Bool = false
    @State private var activeActionID: UUID? = nil
    @State private var customPrompt: String = ""

    // Which content is shown in the shared text region
    private enum ContentMode { case input, result }
    @State private var contentMode: ContentMode = .input

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

    var body: some View {
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

            // Pin button
            Button(action: { pinnedState.toggle() }) {
                Image(systemName: pinnedState.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundStyle(pinnedState.pinned ? .blue : .secondary)
                    .rotationEffect(.degrees(45))
            }
            .buttonStyle(.plain)
            .help(pinnedState.pinned ? "Unpin (auto-close on click away)" : "Pin (keep open)")
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
            ScrollView {
                Text(text)
                    .font(.system(size: CGFloat(fontSize)))
                    .foregroundStyle(.primary.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .background(Color.primary.opacity(0.03))

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
            if isProcessing {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.75)
                    Text("Processing…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.03))
            } else if !result.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result)
                            .font(.system(size: CGFloat(fontSize)))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        HStack {
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(result, forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                    .padding(12)
                }
                .background(Color.primary.opacity(0.03))
            } else {
                Color.clear
            }
        }
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

    // MARK: - Handlers (text)

    private func runTextAction(_ action: TextAction) {
        activeActionID = action.id
        isProcessing = true
        result = ""
        if switchToResult { contentMode = .result }
        let prompt = action.renderPrompt(with: capturedText)
        Task {
            let output = await TextProcessingService.shared.process(prompt)
            let usedModel = await TextProcessingService.shared.model
            await MainActor.run {
                result = output
                isProcessing = false
                contentMode = .result
                HistoryStore.shared.add(sourceText: capturedText, actionName: action.label, fullPrompt: prompt, result: output, modelName: usedModel)
                if autoCopy { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string) }
            }
        }
    }

    private func runCustomPrompt() {
        let instruction = customPrompt.trimmingCharacters(in: .whitespaces)
        guard !instruction.isEmpty else { return }
        activeActionID = nil
        isProcessing = true
        result = ""
        if switchToResult { contentMode = .result }
        Task {
            let output = await TextProcessingService.shared.process(instruction, userText: capturedText)
            let usedModel = await TextProcessingService.shared.model
            await MainActor.run {
                result = output
                isProcessing = false
                contentMode = .result
                let fullPrompt = "[System]\n\(instruction)\n\n[User]\n\(capturedText)"
                HistoryStore.shared.add(sourceText: capturedText, actionName: "Custom", fullPrompt: fullPrompt, result: output, modelName: usedModel)
                if autoCopy { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string) }
            }
        }
    }

    // MARK: - Handlers (vision)

    private func runVisionAction(_ action: TextAction) {
        guard case .image(_, let data) = content else { return }
        activeActionID = action.id
        isProcessing = true
        result = ""
        if switchToResult { contentMode = .result }
        Task {
            let output = await TextProcessingService.shared.processImage(imageData: data, prompt: action.prompt)
            let usedModel = await TextProcessingService.shared.visionModel
            await MainActor.run {
                result = output
                isProcessing = false
                contentMode = .result
                HistoryStore.shared.add(sourceText: "[Image]", actionName: action.label, fullPrompt: action.prompt, result: output, modelName: usedModel)
                if autoCopy { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string) }
            }
        }
    }

    private func runCustomVisionPrompt() {
        guard case .image(_, let data) = content else { return }
        let instruction = customPrompt.trimmingCharacters(in: .whitespaces)
        guard !instruction.isEmpty else { return }
        activeActionID = nil
        isProcessing = true
        result = ""
        if switchToResult { contentMode = .result }
        Task {
            let output = await TextProcessingService.shared.processImage(imageData: data, prompt: instruction)
            let usedModel = await TextProcessingService.shared.visionModel
            await MainActor.run {
                result = output
                isProcessing = false
                contentMode = .result
                HistoryStore.shared.add(sourceText: "[Image]", actionName: "Custom Vision", fullPrompt: instruction, result: output, modelName: usedModel)
                if autoCopy { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string) }
            }
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let action: TextAction
    let isActive: Bool
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 2) {
                if isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Image(systemName: action.icon).font(.system(size: 11))
                }
                Text(action.label).font(.system(size: 11))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .blue : nil)
        .controlSize(.mini)
    }
}
