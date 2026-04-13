import SwiftUI

// MARK: - Settings Root

struct SettingsView: View {
    var body: some View {
        TabView {
            ActionsSettingsTab()
                .tabItem { Label("Actions", systemImage: "bolt.fill") }

            APIAndModelTab()
                .tabItem { Label("API & Model", systemImage: "cpu") }

            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }

            HistorySettingsTab()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 680, height: 520)
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
            NewActionSheet { newAction in
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

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { action.isEnabled },
                set: { val in
                    var a = action; a.isEnabled = val; store.update(a)
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: action.icon)
                .frame(width: 18)
                .foregroundStyle(.blue)

            Text(action.label)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Action Editor (right pane)

struct ActionEditor: View {
    let action: TextAction
    let onSave: (TextAction) -> Void

    @State private var label: String
    @State private var icon: String
    @State private var prompt: String
    @State private var isEnabled: Bool

    // Common SF Symbols for text actions
    private let iconOptions = [
        "wand.and.stars", "text.magnifyingglass", "checkmark.circle",
        "questionmark.bubble", "globe", "doc.on.doc", "pencil",
        "lightbulb", "brain", "sparkles", "quote.bubble",
        "arrow.triangle.2.circlepath", "scissors", "list.bullet",
    ]

    init(action: TextAction, onSave: @escaping (TextAction) -> Void) {
        self.action = action
        self.onSave = onSave
        _label   = State(initialValue: action.label)
        _icon    = State(initialValue: action.icon)
        _prompt  = State(initialValue: action.prompt)
        _isEnabled = State(initialValue: action.isEnabled)
    }

    var isDirty: Bool {
        label != action.label || icon != action.icon
            || prompt != action.prompt || isEnabled != action.isEnabled
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
            }

            // Prompt editor
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Prompt").font(.caption).foregroundStyle(.secondary)
                    Text("(use {{text}} as placeholder for captured text)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                TextEditor(text: $prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .border(Color.secondary.opacity(0.3), width: 1)
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
        }
    }
}

// MARK: - New Action Sheet

struct NewActionSheet: View {
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
                    Text("(use {{text}} for captured text)")
                        .font(.caption).foregroundStyle(.tertiary)
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
                    let action = TextAction(label: label, icon: icon, prompt: prompt)
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

// MARK: - API & Model Tab

struct APIAndModelTab: View {
    @AppStorage("textpick.apiKey")  private var apiKey:  String = ""
    @AppStorage("textpick.apiURL")  private var apiURL:  String = ""
    @AppStorage("textpick.model")   private var model:   String = "anthropic/claude-haiku-4.5"
    @AppStorage("textpick.savedModels") private var savedModelsJSON: String = ""

    @State private var fetchedModels: [TextProcessingService.ModelInfo] = []
    @State private var isLoading    = false
    @State private var fetchError:  String? = nil
    @State private var searchText   = ""
    @State private var customModel  = ""
    @State private var useCustom    = false
    @State private var showKey      = false
    @State private var testStatus: String? = nil
    @State private var testOK: Bool = false
    @State private var isTesting = false

    private var displayedModels: [TextProcessingService.ModelInfo] {
        guard !searchText.isEmpty else { return fetchedModels }
        return fetchedModels.filter { $0.id.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── API Key ──────────────────────────────────────
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
                            .foregroundStyle(.secondary).font(.system(size: 12))
                    }.buttonStyle(.plain)
                }
                if apiKey.isEmpty {
                    Label("No key set — will use AI_GATEWAY_API_KEY env var if available", systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                } else {
                    Text("Saved · \(apiKey.count) chars · prefix: \(apiKey.prefix(6))…")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            // ── Base URL ─────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("API Base URL").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                TextField("https://ai-gateway.vercel.sh/v1  (default)", text: $apiURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            // ── Test Connection ───────────────────────────────
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

            // ── Model ────────────────────────────────────────
            HStack {
                Text("Model").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.65)
                } else {
                    Button(action: fetchModels) {
                        Label(fetchedModels.isEmpty ? "Load" : "Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }.buttonStyle(.bordered).controlSize(.small)
                }
            }

            if let err = fetchError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            if !fetchedModels.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                    TextField("Filter…", text: $searchText).textFieldStyle(.plain).font(.system(size: 12))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let grouped = Dictionary(grouping: displayedModels, by: \.provider)
                        ForEach(grouped.keys.sorted(), id: \.self) { provider in
                            Section {
                                ForEach(grouped[provider] ?? []) { m in
                                    ModelRow(
                                        id: m.id, label: m.displayName, note: m.provider,
                                        isSelected: !useCustom && model == m.id
                                    ) { useCustom = false; model = m.id }
                                    Divider().padding(.leading, 44)
                                }
                            } header: {
                                Text(provider.capitalized)
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                }
            } else if !isLoading {
                Text("Click \"Load\" to fetch available models.")
                    .font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
            }

            // Custom model override
            HStack(spacing: 8) {
                Toggle("Custom ID:", isOn: $useCustom)
                    .toggleStyle(.checkbox).fixedSize()
                    .font(.system(size: 12))
                TextField("e.g. anthropic/claude-3-haiku", text: $customModel)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    .disabled(!useCustom)
                    .onSubmit { if !customModel.isEmpty { model = customModel } }
            }

            Text("Active: \(model)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(4)
        .onAppear { loadCachedModels(); if fetchedModels.isEmpty { fetchModels() } }
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
                    // Persist to UserDefaults
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

// ── old ModelSettingsTab stub kept for compilation safety ──
private struct ModelSettingsTab: View {
    @AppStorage("textpick.model") private var model: String = "anthropic/claude-haiku-4.5"

    @State private var fetchedModels: [TextProcessingService.ModelInfo] = []
    @State private var isLoading = false
    @State private var fetchError: String? = nil
    @State private var searchText: String = ""
    @State private var customModel: String = ""
    @State private var useCustom: Bool = false

    private var displayedModels: [TextProcessingService.ModelInfo] {
        guard !searchText.isEmpty else { return fetchedModels }
        return fetchedModels.filter {
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Language Model").font(.headline)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button(action: fetchModels) {
                        Label(fetchedModels.isEmpty ? "Load Models" : "Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let err = fetchError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(err).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if !fetchedModels.isEmpty {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter models…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

                // Group by provider
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let grouped = Dictionary(grouping: displayedModels, by: \.provider)
                        let providers = grouped.keys.sorted()
                        ForEach(providers, id: \.self) { provider in
                            Section {
                                ForEach(grouped[provider] ?? []) { m in
                                    ModelRow(
                                        id: m.id,
                                        label: m.displayName,
                                        note: m.provider,
                                        isSelected: !useCustom && model == m.id
                                    ) {
                                        useCustom = false
                                        model = m.id
                                    }
                                    Divider().padding(.leading, 44)
                                }
                            } header: {
                                Text(provider.capitalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                }
            } else if !isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "cpu").font(.title2).foregroundStyle(.tertiary)
                    Text("Click \"Load Models\" to fetch available models from your API endpoint.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Custom model ID override
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Use custom model ID", isOn: $useCustom)
                if useCustom {
                    HStack {
                        TextField("e.g. anthropic/claude-3-haiku", text: $customModel)
                            .textFieldStyle(.roundedBorder)
                        Button("Apply") {
                            if !customModel.isEmpty { model = customModel }
                        }
                        .buttonStyle(.bordered)
                        .disabled(customModel.isEmpty)
                    }
                    Text("Any OpenAI-compatible model ID (provider/model-name)")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            HStack {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("Selected: \(model)")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(4)
        .onAppear {
            if !fetchedModels.isEmpty { return }
            // Auto-fetch on first open
            fetchModels()
            if !TextProcessingService.ModelInfo(id: model).provider.isEmpty {
                let knownProviders = ["anthropic", "openai", "google", "deepseek", "xiaomi"]
                if !knownProviders.contains(where: { model.hasPrefix($0) }) {
                    useCustom = true
                    customModel = model
                }
            }
        }
    }

    private func fetchModels() {
        isLoading = true
        fetchError = nil
        Task {
            do {
                let models = try await TextProcessingService.shared.fetchModels()
                await MainActor.run {
                    fetchedModels = models
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    fetchError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

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
        VStack(spacing: 0) {

            // ── Hero badge ──────────────────────────────────────────────
            VStack(spacing: 8) {
                Text("Trigger Hotkey")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(config.displayString)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .tracking(3)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.accentColor.opacity(0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                            )
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)

            Divider()

            // ── Record zone ─────────────────────────────────────────────
            VStack(spacing: 16) {

                Button(action: isRecording ? stopRecording : startRecording) {
                    HStack(spacing: 10) {
                        if isRecording {
                            ProgressView().scaleEffect(0.75)
                            Text("Listening… hold modifiers + press key")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red)
                        } else if let pending = pendingConfig {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(pending.displayString)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                            Text("— tap Apply to save")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "record.circle")
                            Text("Click to record new hotkey")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .red : nil)
                .controlSize(.large)

                if let pending = pendingConfig, !isRecording {
                    HStack(spacing: 10) {
                        Button("Apply  " + pending.displayString) {
                            applyConfig(pending)
                            pendingConfig = nil
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Discard") { pendingConfig = nil }
                            .buttonStyle(.bordered)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.2), value: pendingConfig != nil)
                }

                Text(isRecording
                     ? "Press Escape to cancel."
                     : "Hold ⌃ ⌥ ⇧ ⌘ + any key. At least one modifier required.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)

            Spacer()
            Divider()

            // ── Footer ──────────────────────────────────────────────────
            HStack {
                Button("Reset to Default  \(HotkeyConfig.default.displayString)") {
                    applyConfig(HotkeyConfig.default)
                    pendingConfig = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(config == HotkeyConfig.default)

                Spacer()

                Text("Takes effect immediately")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .onDisappear { stopRecording() }
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
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label).fontWeight(isSelected ? .medium : .regular)
                    Text(id).font(.caption).foregroundStyle(.tertiary)
                }

                Spacer()

                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    @ObservedObject private var store = HistoryStore.shared

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        VStack(spacing: 0) {
            if store.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No history yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Your requests and results will appear here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.items) { item in
                        HistoryRowView(item: item, formatter: dateFormatter)
                    }
                    .onDelete(perform: store.delete)
                }
                .listStyle(.inset)

                Divider()

                HStack {
                    Text("\(store.items.count) items")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Clear All", role: .destructive) {
                        store.clear()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}

struct HistoryRowView: View {
    let item: HistoryItem
    let formatter: DateFormatter
    @State private var promptExpanded = false
    @State private var resultExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // ── Header: action · model · time ──────────────
            HStack(spacing: 6) {
                Label(item.actionName, systemImage: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                if !item.modelName.isEmpty {
                    Text("·").foregroundStyle(.tertiary).font(.system(size: 10))
                    Text(item.modelName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(formatter.string(from: item.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // ── Prompt (collapsible, collapsed by default) ─
            VStack(alignment: .leading, spacing: 2) {
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { promptExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: promptExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Prompt")
                            .font(.system(size: 10, weight: .semibold))
                        if !promptExpanded {
                            Text(item.fullPrompt.prefix(80).replacingOccurrences(of: "\n", with: " "))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer()
                        if promptExpanded {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.fullPrompt, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if promptExpanded {
                    Text(item.fullPrompt)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            Divider()

            // ── Result (expanded by default) ───────────────
            VStack(alignment: .leading, spacing: 2) {
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { resultExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: resultExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Result")
                            .font(.system(size: 10, weight: .semibold))
                        if !resultExpanded {
                            Text(item.result.prefix(80).replacingOccurrences(of: "\n", with: " "))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer()
                        if resultExpanded {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.result, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if resultExpanded {
                    Text(item.result)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
