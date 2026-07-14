import SwiftUI

// MARK: - Settings Root

struct SettingsView: View {
    var body: some View {
        TabView {
            ActionsSettingsTab()
                .tabItem { Label("Actions", systemImage: "bolt.fill") }

            VisionActionsSettingsTab()
                .tabItem { Label("Vision", systemImage: "eye") }

            APIAndModelTab()
                .tabItem { Label("API & Model", systemImage: "cpu") }

            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }

            HistorySettingsTab()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 720, height: 580)
        .padding(16)
    }
}

// MARK: - Actions Tab

struct ActionsSettingsTab: View {
    @ObservedObject private var store = ActionsStore.shared
    @State private var selectedID: UUID? = nil
    @State private var showingAddSheet = false
    @State private var editingAction: TextAction? = nil

    var body: some View {
        HSplitView {
            // Left: list
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(store.actions) { action in
                        ActionRow(action: action)
                            .tag(action.id)
                    }
                    .onDelete(perform: store.delete)
                    .onMove(perform: store.move)
                }
                .listStyle(.bordered)

                Divider()

                HStack(spacing: 4) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)

                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedID == nil)

                    Spacer()

                    Button("Reset Defaults") {
                        store.resetToDefaults()
                        selectedID = nil
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(minWidth: 200, maxWidth: 240)

            // Right: editor
            Group {
                if let id = selectedID,
                   let action = store.actions.first(where: { $0.id == id }) {
                    ActionEditor(action: action) { updated in
                        store.update(updated)
                    }
                    .id(id)  // force re-init when selection changes
                } else {
                    VStack {
                        Image(systemName: "arrow.left")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                        Text("Select an action to edit")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NewActionSheet(isVision: false) { newAction in
                store.add(newAction)
                selectedID = newAction.id
            }
        }
    }

    private func deleteSelected() {
        guard let id = selectedID,
              let idx = store.actions.firstIndex(where: { $0.id == id }) else { return }
        store.delete(at: IndexSet([idx]))
        selectedID = nil
    }
}

// MARK: - Action Row

struct ActionRow: View {
    @ObservedObject private var store = ActionsStore.shared
    let action: TextAction
    var isVision: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { action.isEnabled },
                set: { val in
                    var a = action; a.isEnabled = val
                    if isVision { store.updateVision(a) } else { store.update(a) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: action.icon)
                .frame(width: 18)
                .foregroundStyle(isVision ? .purple : .blue)

            Text(action.label)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Action Editor (right pane)

struct ActionEditor: View {
    let action: TextAction
    var isVision: Bool = false
    let onSave: (TextAction) -> Void

    @State private var label: String
    @State private var icon: String
    @State private var prompt: String
    @State private var isEnabled: Bool
    @State private var saveToFile: Bool
    @State private var saveDirectory: String
    @State private var filenameFormat: FilenameFormat

    // Common SF Symbols for text actions
    private let iconOptions = [
        "wand.and.stars", "text.magnifyingglass", "checkmark.circle",
        "questionmark.bubble", "globe", "doc.on.doc", "pencil",
        "lightbulb", "brain", "sparkles", "quote.bubble",
        "arrow.triangle.2.circlepath", "scissors", "list.bullet",
        "doc.text.viewfinder", "eye", "photo", "list.bullet.rectangle",
    ]

    init(action: TextAction, isVision: Bool = false, onSave: @escaping (TextAction) -> Void) {
        self.action = action
        self.isVision = isVision
        self.onSave = onSave
        _label         = State(initialValue: action.label)
        _icon          = State(initialValue: action.icon)
        _prompt        = State(initialValue: action.prompt)
        _isEnabled     = State(initialValue: action.isEnabled)
        _saveToFile    = State(initialValue: action.saveToFile)
        _saveDirectory = State(initialValue: action.saveDirectory)
        _filenameFormat = State(initialValue: action.filenameFormat)
    }

    var isDirty: Bool {
        label != action.label || icon != action.icon
            || prompt != action.prompt || isEnabled != action.isEnabled
            || saveToFile != action.saveToFile
            || saveDirectory != action.saveDirectory
            || filenameFormat != action.filenameFormat
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Label + icon row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Label").font(.caption).foregroundStyle(.secondary)
                    TextField("Action name", text: $label)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Icon").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: icon.isEmpty ? "questionmark" : icon)
                            .frame(width: 24, height: 24)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 5))

                        Picker("", selection: $icon) {
                            ForEach(iconOptions, id: \.self) { sym in
                                Label(sym, systemImage: sym).tag(sym)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }

                Spacer()

                Toggle("Enabled", isOn: $isEnabled)
                    .fixedSize()
            }

            // Prompt editor
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Prompt").font(.caption).foregroundStyle(.secondary)
                    if isVision {
                        Text("(sent directly to the vision model with the image)")
                            .font(.caption).foregroundStyle(.tertiary)
                    } else {
                        Text("(use {{text}} and {{userInput}} placeholders)")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                TextEditor(text: $prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .border(Color.secondary.opacity(0.3), width: 1)
            }

            // Save-to-file (vision actions only)
            if isVision {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Save result to file", isOn: $saveToFile)
                        .font(.system(size: 13))

                    if saveToFile {
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Save directory").font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    TextField("~/Pictures/TextPick", text: $saveDirectory)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Browse…") {
                                        let panel = NSOpenPanel()
                                        panel.canChooseFiles = false
                                        panel.canChooseDirectories = true
                                        panel.canCreateDirectories = true
                                        panel.prompt = "Select"
                                        if panel.runModal() == .OK, let url = panel.url {
                                            saveDirectory = url.path
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Filename format").font(.caption).foregroundStyle(.secondary)
                                Picker("", selection: $filenameFormat) {
                                    ForEach(FilenameFormat.allCases, id: \.self) { fmt in
                                        Text(fmt.displayName).tag(fmt)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize()
                            }

                            let previewDir = saveDirectory.isEmpty ? "~/Pictures/TextPick" : saveDirectory
                            let previewName: String = {
                                switch filenameFormat {
                                case .descriptionOnly:      return "<description>.md"
                                case .timestampOnly:        return "2024-01-15_14-30-00.md"
                                case .timestampDescription: return "2024-01-15_14-30-00_<description>.md"
                                }
                            }()
                            Text("Preview: \(previewDir)/\(previewName)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }

            // Save button
            HStack {
                Spacer()
                Button("Save") {
                    var updated = action
                    updated.label = label
                    updated.icon = icon
                    updated.prompt = prompt
                    updated.isEnabled = isEnabled
                    updated.saveToFile = saveToFile
                    updated.saveDirectory = saveDirectory
                    updated.filenameFormat = filenameFormat
                    onSave(updated)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty || label.isEmpty || prompt.isEmpty)
            }
        }
        .padding(16)
        .onChange(of: action.id) { _ in
            // Reset local state when selection changes
            label = action.label
            icon = action.icon
            prompt = action.prompt
            isEnabled = action.isEnabled
            saveToFile = action.saveToFile
            saveDirectory = action.saveDirectory
            filenameFormat = action.filenameFormat
        }
    }
}

// MARK: - New Action Sheet

struct NewActionSheet: View {
    var isVision: Bool = false
    let onCreate: (TextAction) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var icon = "sparkles"
    @State private var prompt = ""

    private let iconOptions = [
        "wand.and.stars", "text.magnifyingglass", "checkmark.circle",
        "questionmark.bubble", "globe", "doc.on.doc", "pencil",
        "lightbulb", "brain", "sparkles", "quote.bubble",
        "arrow.triangle.2.circlepath", "scissors", "list.bullet",
        "doc.text.viewfinder", "eye", "photo", "list.bullet.rectangle",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Action").font(.headline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Label").font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. Summarize", text: $label)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Icon").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .frame(width: 24, height: 24)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        Picker("", selection: $icon) {
                            ForEach(iconOptions, id: \.self) { sym in
                                Label(sym, systemImage: sym).tag(sym)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Prompt").font(.caption).foregroundStyle(.secondary)
                    if isVision {
                        Text("(sent to vision model with the image)")
                            .font(.caption).foregroundStyle(.tertiary)
                    } else {
                        Text("(use {{text}} for captured text)")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                TextEditor(text: $prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 140)
                    .border(Color.secondary.opacity(0.3), width: 1)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") {
                    let action = TextAction(label: label, icon: icon, prompt: prompt, supportsImage: isVision)
                    onCreate(action)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.isEmpty || prompt.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}

// MARK: - Vision Actions Settings Tab

struct VisionActionsSettingsTab: View {
    @ObservedObject private var store = ActionsStore.shared
    @State private var selectedID: UUID? = nil
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Info banner
            HStack(spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.blue)
                Text("Vision actions appear when an image is captured from clipboard (e.g. screenshot). Requires a vision-capable model set in API & Model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.blue.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 10)

            HSplitView {
                // Left: list
                VStack(spacing: 0) {
                    List(selection: $selectedID) {
                        ForEach(store.visionActions) { action in
                            ActionRow(action: action, isVision: true)
                                .tag(action.id)
                        }
                        .onDelete(perform: store.deleteVision)
                        .onMove(perform: store.moveVision)
                    }
                    .listStyle(.bordered)

                    Divider()
                    HStack(spacing: 4) {
                        Button(action: { showingAddSheet = true }) {
                            Image(systemName: "plus")
                        }.buttonStyle(.borderless)

                        Button(action: deleteSelected) {
                            Image(systemName: "minus")
                        }.buttonStyle(.borderless).disabled(selectedID == nil)

                        Spacer()
                        Button("Reset Defaults") {
                            store.resetVisionToDefaults()
                            selectedID = nil
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                }
                .frame(minWidth: 200, maxWidth: 240)

                // Right: editor
                Group {
                    if let id = selectedID,
                       let action = store.visionActions.first(where: { $0.id == id }) {
                        ActionEditor(action: action, isVision: true) { updated in
                            store.updateVision(updated)
                        }
                        .id(id)
                    } else {
                        VStack {
                            Image(systemName: "arrow.left").font(.title).foregroundStyle(.tertiary)
                            Text("Select a vision action to edit").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NewActionSheet(isVision: true) { newAction in
                store.addVision(newAction)
                selectedID = newAction.id
            }
        }
    }

    private func deleteSelected() {
        guard let id = selectedID,
              let idx = store.visionActions.firstIndex(where: { $0.id == id }) else { return }
        store.deleteVision(at: IndexSet([idx]))
        selectedID = nil
    }
}

// MARK: - API & Model Tab

struct APIAndModelTab: View {
    @AppStorage("textpick.apiKey") private var apiKey: String = ""
    @AppStorage("textpick.apiURL") private var apiURL: String = ""
    @AppStorage("textpick.model") private var model: String = "anthropic/claude-haiku-4.5"
    @AppStorage("textpick.visionModel") private var visionModel: String = ""
    @AppStorage("textpick.savedModels") private var savedModelsJSON: String = ""
    @AppStorage("textpick.reasoningEffort") private var reasoningEffort: String = ""

    @State private var fetchedModels: [TextProcessingService.ModelInfo] = []
    @State private var isLoading = false
    @State private var fetchError: String? = nil
    @State private var searchText = ""
    @State private var showVisionOnly = false
    @State private var selectedProvider = "All"
    @State private var textCustomModel = ""
    @State private var visionCustomModel = ""
    @State private var useCustomTextModel = false
    @State private var useCustomVisionModel = false
    @State private var showKey = false
    @State private var testStatus: String? = nil
    @State private var testOK: Bool = false
    @State private var isTesting = false

    private let providerAll = "All"

    private var providers: [String] {
        [providerAll] + Array(Set(fetchedModels.map(\.provider))).sorted()
    }

    private var displayedModels: [TextProcessingService.ModelInfo] {
        fetchedModels.filter { m in
            let matchesSearch = searchText.isEmpty
                || m.id.localizedCaseInsensitiveContains(searchText)
                || m.displayName.localizedCaseInsensitiveContains(searchText)
            let matchesVision = !showVisionOnly || m.supportsVision
            let matchesProvider = selectedProvider == providerAll || m.provider == selectedProvider
            return matchesSearch && matchesVision && matchesProvider
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if showKey {
                        TextField("Paste your API key…", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("Paste your API key…", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Button(action: { showKey.toggle() }) {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
                if apiKey.isEmpty {
                    Label("No key set — will use AI_GATEWAY_API_KEY env var if available", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text("Saved · \(apiKey.count) chars")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("API Base URL").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                TextField("https://ai-gateway.vercel.sh/v1  (default)", text: $apiURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            HStack(spacing: 8) {
                Button(action: runTestConnection) {
                    HStack(spacing: 4) {
                        if isTesting { ProgressView().scaleEffect(0.6) }
                        Text(isTesting ? "Testing…" : "Test Connection")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isTesting)

                if let status = testStatus {
                    Image(systemName: testOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(testOK ? .green : .red)
                        .font(.system(size: 12))
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(testOK ? .green : .red)
                        .lineLimit(2)
                }
            }

            Divider()

            // Reasoning Effort
            VStack(alignment: .leading, spacing: 4) {
                Text("Thinking / Reasoning").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Picker("Effort", selection: $reasoningEffort) {
                        Text("Default (adaptive)").tag("")
                        Text("Disabled").tag("none")
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                    }
                    .labelsHidden()
                    .frame(width: 180)

                    Text(reasoningEffort.isEmpty
                        ? "Model decides automatically"
                        : "Forces reasoningEffort = \"\(reasoningEffort)\"")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 12) {
                modelSelectionCard(
                    title: "Text Model",
                    icon: "text.cursor",
                    tint: .blue,
                    selectedModel: model,
                    customModel: $textCustomModel,
                    useCustom: $useCustomTextModel,
                    allowEmpty: false,
                    emptyLabel: nil,
                    onApplyCustom: { value in model = value },
                    onClear: nil
                )

                modelSelectionCard(
                    title: "Vision Model",
                    icon: "eye",
                    tint: .purple,
                    selectedModel: visionModel,
                    customModel: $visionCustomModel,
                    useCustom: $useCustomVisionModel,
                    allowEmpty: true,
                    emptyLabel: "Same as text model",
                    onApplyCustom: { value in visionModel = value },
                    onClear: { visionModel = ""; useCustomVisionModel = false; visionCustomModel = "" }
                )
            }

            Divider()

            HStack {
                Text("Model List").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.65)
                } else {
                    Button(action: fetchModels) {
                        Label(fetchedModels.isEmpty ? "Load" : "Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let err = fetchError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !fetchedModels.isEmpty {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                        TextField("Filter by id or name…", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(providers, id: \.self) { provider in
                            Text(provider.capitalized).tag(provider)
                        }
                    }
                    .frame(width: 150)

                    Toggle("Vision only", isOn: $showVisionOnly)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(displayedModels) { m in
                            ModelRow(
                                id: m.id,
                                label: m.displayName,
                                note: m.provider,
                                isSelected: model == m.id || visionModel == m.id,
                                isTextSelected: model == m.id,
                                isVisionSelected: visionModel == m.id,
                                onSelectText: {
                                    useCustomTextModel = false
                                    textCustomModel = ""
                                    model = m.id
                                },
                                onSelectVision: {
                                    useCustomVisionModel = false
                                    visionCustomModel = ""
                                    visionModel = m.id
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            } else if !isLoading {
                Text("Click \"Load\" to fetch available models.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(4)
        .onAppear {
            loadCachedModels()
            syncCustomModelState()
            if fetchedModels.isEmpty { fetchModels() }
        }
    }

    private func runTestConnection() {
        isTesting = true
        testStatus = nil
        Task {
            let result = await TextProcessingService.shared.testConnection()
            await MainActor.run {
                testOK = result.ok
                testStatus = result.message
                isTesting = false
            }
        }
    }

    @ViewBuilder
    private func modelSelectionCard(
        title: String,
        icon: String,
        tint: Color,
        selectedModel: String,
        customModel: Binding<String>,
        useCustom: Binding<Bool>,
        allowEmpty: Bool,
        emptyLabel: String?,
        onApplyCustom: @escaping (String) -> Void,
        onClear: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(selectedModel.isEmpty ? (emptyLabel ?? "Not set") : selectedModel)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !selectedModel.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(selectedModel, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copy model id")
                }
                if allowEmpty, !selectedModel.isEmpty, let onClear {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Use text model")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
                Toggle("Custom ID", isOn: useCustom)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                TextField("provider/model-name", text: customModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .disabled(!useCustom.wrappedValue)
                    .onSubmit {
                        let value = customModel.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty { onApplyCustom(value) }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func syncCustomModelState() {
        let known = Set(fetchedModels.map(\.id))
        if !model.isEmpty && !known.isEmpty && !known.contains(model) {
            useCustomTextModel = true
            textCustomModel = model
        }
        if !visionModel.isEmpty && !known.isEmpty && !known.contains(visionModel) {
            useCustomVisionModel = true
            visionCustomModel = visionModel
        }
    }

    private func loadCachedModels() {
        guard !savedModelsJSON.isEmpty,
              let data = savedModelsJSON.data(using: .utf8),
              let models = try? JSONDecoder().decode([TextProcessingService.ModelInfo].self, from: data)
        else { return }
        fetchedModels = models
    }

    private func fetchModels() {
        isLoading = true; fetchError = nil
        Task {
            do {
                let models = try await TextProcessingService.shared.fetchModels()
                await MainActor.run {
                    fetchedModels = models
                    isLoading = false
                    syncCustomModelState()
                    if let data = try? JSONEncoder().encode(models),
                       let json = String(data: data, encoding: .utf8) {
                        savedModelsJSON = json
                    }
                }
            } catch {
                await MainActor.run { fetchError = error.localizedDescription; isLoading = false }
            }
        }
    }
}

// old ModelSettingsTab removed

// MARK: - Hotkey Tab

/// Supported modifier combinations for the trigger hotkey
struct HotkeyConfig: Codable, Equatable {
    var modifiers: [String]   // e.g. ["command", "shift"]
    var key: String           // e.g. "space", "p"

    static let `default` = HotkeyConfig(modifiers: ["command", "shift"], key: "space")

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains("control") { parts.append("⌃") }
        if modifiers.contains("option")  { parts.append("⌥") }
        if modifiers.contains("shift")   { parts.append("⇧") }
        if modifiers.contains("command") { parts.append("⌘") }
        parts.append(key == "space" ? "Space" : key.uppercased())
        return parts.joined()
    }
}

struct HotkeySettingsTab: View {
    @State private var config: HotkeyConfig = HotkeySettingsTab.loadConfig()
    @State private var isRecording = false
    @State private var pendingConfig: HotkeyConfig? = nil
    @State private var keyMonitor: Any? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Trigger Hotkey")
                    .font(.subheadline.weight(.medium))
                Text("Press this combination anywhere to open TextPick")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Current hotkey + record on one row
            HStack(spacing: 10) {
                hotkeyBadge(isRecording ? (pendingConfig?.displayString ?? "…") : config.displayString,
                            highlighted: !isRecording)

                Button(action: isRecording ? stopRecording : startRecording) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isRecording ? Color.red : Color.clear)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .strokeBorder(isRecording ? Color.red : Color.secondary, lineWidth: 1.5)
                            )
                        Text(isRecording ? "Listening…" : "Record")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isRecording ? Color.red.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isRecording ? Color.red.opacity(0.35) : Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isRecording)

                if isRecording {
                    Text("Esc to cancel")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }

            if let pending = pendingConfig, !isRecording {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    hotkeyBadge(pending.displayString, highlighted: true)
                    Text("recorded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Discard") { pendingConfig = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Apply") {
                        applyConfig(pending)
                        pendingConfig = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.05))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.spring(duration: 0.2), value: pendingConfig != nil)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Hold ⌃ ⌥ ⇧ ⌘ + any key. At least one modifier required.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("If the hotkey doesn't work, it may conflict with another app's shortcut.")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.8))
            }

            Spacer()

            HStack {
                Button {
                    applyConfig(HotkeyConfig.default)
                    pendingConfig = nil
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                        Text("Reset to \(HotkeyConfig.default.displayString)")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(config == HotkeyConfig.default)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Takes effect immediately")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .onDisappear { stopRecording() }
    }

    @ViewBuilder
    private func hotkeyBadge(_ label: String, highlighted: Bool) -> some View {
        Text(label)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .tracking(0.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(highlighted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(highlighted ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            )
            .foregroundColor(highlighted ? .accentColor : .primary)
    }

    // MARK: - Recording

    private func startRecording() {
        isRecording = true
        pendingConfig = nil
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels
            if event.keyCode == 53 {
                self.stopRecording()
                return nil
            }
            guard let key = Self.keyCodeToString(event.keyCode) else {
                return nil  // ignore unknown keys
            }
            var mods: [String] = []
            if event.modifierFlags.contains(.command) { mods.append("command") }
            if event.modifierFlags.contains(.shift)   { mods.append("shift") }
            if event.modifierFlags.contains(.option)  { mods.append("option") }
            if event.modifierFlags.contains(.control) { mods.append("control") }
            guard !mods.isEmpty else { return nil }  // require at least one modifier
            self.pendingConfig = HotkeyConfig(modifiers: mods, key: key)
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    // MARK: - Apply & Persist

    private func applyConfig(_ newConfig: HotkeyConfig) {
        config = newConfig
        Self.saveConfig(newConfig)
        // Notify AppDelegate to re-register
        NotificationCenter.default.post(name: .hotkeyConfigChanged, object: newConfig)
    }

    // MARK: - Persistence

    static func loadConfig() -> HotkeyConfig {
        guard let data = UserDefaults.standard.data(forKey: "textpick.hotkey"),
              let cfg = try? JSONDecoder().decode(HotkeyConfig.self, from: data)
        else { return .default }
        return cfg
    }

    static func saveConfig(_ cfg: HotkeyConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: "textpick.hotkey")
        }
    }

    // MARK: - Key code → string

    static func keyCodeToString(_ keyCode: UInt16) -> String? {
        let map: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 37: "l", 38: "j",
            40: "k", 45: "n", 46: "m", 49: "space",
        ]
        return map[keyCode]
    }
}

extension Notification.Name {
    static let hotkeyConfigChanged = Notification.Name("textpick.hotkeyConfigChanged")
}

// MARK: - Model Row

struct ModelRow: View {
    let id: String
    let label: String
    let note: String
    let isSelected: Bool
    let isTextSelected: Bool
    let isVisionSelected: Bool
    let onSelectText: () -> Void
    let onSelectVision: () -> Void

    private var metadata: TextProcessingService.ModelMetadata? {
        TextProcessingService.metadata(for: id)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(label).fontWeight(isSelected ? .medium : .regular)
                    if metadata?.supportsVision == true {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.purple)
                            .help("Supports vision/image input")
                    }
                    if metadata?.notes == "thinking" {
                        Image(systemName: "brain")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .help("Supports extended thinking")
                    }
                }

                Text(id)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Label(note.capitalized, systemImage: "shippingbox")
                    if let meta = metadata,
                       let inP = meta.inputPricePerMillion,
                       let outP = meta.outputPricePerMillion {
                        Label("$\(String(format: "%.2f", inP)) / $\(String(format: "%.2f", outP))", systemImage: "dollarsign.circle")
                    }
                    if let ctx = metadata?.contextWindowTokens {
                        Label("ctx \(formatTokens(ctx))", systemImage: "rectangle.stack")
                    }
                    if let out = metadata?.maxOutputTokens {
                        Label("out \(formatTokens(out))", systemImage: "arrow.up.right.text.horizontal")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Button(isTextSelected ? "Text ✓" : "Set Text") {
                    onSelectText()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(isVisionSelected ? "Vision ✓" : "Set Vision") {
                    onSelectVision()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(metadata?.supportsVision == false)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(id, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy model id")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return "\(value / 1_000_000)M" }
        if value >= 1_000 { return "\(value / 1_000)K" }
        return "\(value)"
    }
}

// MARK: - API Settings Tab

struct APISettingsTab: View {
    @AppStorage("textpick.apiKey") private var apiKey: String = ""
    @AppStorage("textpick.apiURL") private var apiURL: String = ""

    @State private var showKey = false
    @State private var testStatus: TestStatus = .idle

    enum TestStatus {
        case idle, testing, ok(String), fail(String)
    }

    private var effectiveURL: String {
        apiURL.isEmpty ? "https://ai-gateway.vercel.sh/v1" : apiURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("API Configuration").font(.headline)

            // API Key
            VStack(alignment: .leading, spacing: 6) {
                Label("API Key", systemImage: "key")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    TextField("Paste your API key…", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(showKey ? .primary : .clear)
                        .overlay(
                            Group {
                                if !showKey && !apiKey.isEmpty {
                                    Text(String(repeating: "•", count: min(apiKey.count, 40)))
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .allowsHitTesting(false)
                                }
                            }
                        )

                    Button(action: { showKey.toggle() }) {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text("Stored in UserDefaults (not in .env). Leave empty to use AI_GATEWAY_API_KEY env var.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Divider()

            // Base URL
            VStack(alignment: .leading, spacing: 6) {
                Label("API Base URL", systemImage: "network")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("https://ai-gateway.vercel.sh/v1", text: $apiURL)
                    .textFieldStyle(.roundedBorder)
                Text("Leave empty to use TEXTPICK_API_URL env var or default Vercel AI Gateway.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Divider()

            // Test connection
            HStack(spacing: 12) {
                Button(action: testConnection) {
                    Label("Test Connection", systemImage: "network.badge.shield.half.filled")
                }
                .buttonStyle(.bordered)
                .disabled(testStatus == .testing)

                switch testStatus {
                case .idle:
                    EmptyView()
                case .testing:
                    ProgressView().scaleEffect(0.7)
                    Text("Connecting…").font(.caption).foregroundStyle(.secondary)
                case .ok(let models):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(models).font(.caption).foregroundStyle(.secondary)
                case .fail(let msg):
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(4)
    }

    private var isTestingBinding: Bool { testStatus == .testing }

    private func testConnection() {
        testStatus = .testing
        Task {
            do {
                let models = try await TextProcessingService.shared.fetchModels()
                await MainActor.run {
                    testStatus = .ok("✓ \(models.count) models available")
                }
            } catch {
                await MainActor.run {
                    testStatus = .fail(error.localizedDescription)
                }
            }
        }
    }
}

extension APISettingsTab.TestStatus: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.testing, .testing): return true
        case (.ok(let a), .ok(let b)): return a == b
        case (.fail(let a), .fail(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - History Tab

struct HistorySettingsTab: View {
    var body: some View {
        HistoryListView()
    }
}
