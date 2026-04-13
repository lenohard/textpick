import SwiftUI

// MARK: - Main Popup View

struct PopupView: View {
    let capturedText: String
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

    private var enabledActions: [TextAction] {
        store.actions.filter(\.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            // Shared content region: input text ↔ result
            if showInputText || contentMode == .result || isProcessing {
                contentRegion
                Divider()
            }
            actionButtonsView
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
            Image(systemName: "text.cursor")
                .foregroundStyle(.blue)
                .font(.system(size: 13))
            Text("TextPick")
                .font(.system(size: 13, weight: .semibold))
            Spacer()

            // Tab switcher — only show when result is available
            if !result.isEmpty || isProcessing {
                Picker("", selection: $contentMode) {
                    Text("Input").tag(ContentMode.input)
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
                    .rotationEffect(.degrees(45))  // pin icon looks better at 45°
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
            // Input text
            inputTextView
                .opacity(contentMode == .input ? 1 : 0)

            // Result / processing
            resultContentView
                .opacity(contentMode == .result ? 1 : 0)
        }
        .frame(minHeight: 80, maxHeight: 200)
        .animation(.easeInOut(duration: 0.18), value: contentMode)
    }

    private var inputTextView: some View {
        ScrollView {
            Text(capturedText)
                .font(.system(size: CGFloat(fontSize)))
                .foregroundStyle(.primary.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .textSelection(.enabled)
        }
        .background(Color.primary.opacity(0.03))
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
                    Text(result)
                        .font(.system(size: CGFloat(fontSize)))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .background(Color.primary.opacity(0.03))
            } else {
                Color.clear
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtonsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(enabledActions) { action in
                    ActionButton(
                        action: action,
                        isActive: activeActionID == action.id,
                        isLoading: isProcessing && activeActionID == action.id
                    ) {
                        runAction(action)
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Custom Prompt

    private var customPromptView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pencil.and.sparkles")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                TextField("Custom instruction for the selected text…", text: $customPrompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { runCustomPrompt() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: runCustomPrompt) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(canSubmitCustom ? .blue : Color.secondary.opacity(0.4))
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

    // MARK: - Handlers

    private func runAction(_ action: TextAction) {
        activeActionID = action.id
        isProcessing = true
        result = ""
        if switchToResult { contentMode = .result }
        let prompt = action.renderPrompt(with: capturedText)
        Task {
            let output = await TextProcessingService.shared.process(prompt)
            await MainActor.run {
                result = output
                isProcessing = false
                contentMode = .result
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
            await MainActor.run {
                result = output
                isProcessing = false
                contentMode = .result
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
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Image(systemName: action.icon).font(.system(size: 11))
                }
                Text(action.label).font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .blue : nil)
        .controlSize(.mini)
    }
}
