import SwiftUI

struct HistoryListView: View {
    @ObservedObject var store = HistoryStore.shared
    @State private var selectedID: UUID?
    @State private var searchText = ""

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    private var filteredItems: [HistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return store.items }
        return store.items.filter { item in
            item.actionName.lowercased().contains(query)
                || item.sourceText.lowercased().contains(query)
                || item.fullPrompt.lowercased().contains(query)
                || item.result.lowercased().contains(query)
                || item.modelName.lowercased().contains(query)
        }
    }

    var body: some View {
        if store.items.isEmpty {
            emptyState(
                title: "No history yet",
                subtitle: "Your requests and results will appear here."
            )
        } else {
            HSplitView {
                listPane
                    .frame(minWidth: 220, maxWidth: 280)

                detailPane
            }
        }
    }

    // MARK: - List Pane

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search history…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if filteredItems.isEmpty {
                emptyState(
                    title: "No matches",
                    subtitle: "Try a different search term."
                )
            } else {
                List(selection: $selectedID) {
                    ForEach(filteredItems) { item in
                        HistoryRow(item: item, formatter: dateFormatter)
                            .tag(item.id)
                    }
                }
                .listStyle(.bordered)
            }

            Divider()

            HStack(spacing: 4) {
                Button(action: deleteSelected) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedID == nil)

                Spacer()

                Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Button("Clear All", role: .destructive) {
                    store.clear()
                    selectedID = nil
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .onAppear { ensureSelection() }
        .onChange(of: store.items.count) { _ in ensureSelection() }
        .onChange(of: searchText) { _ in ensureSelection() }
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if let id = selectedID,
           let item = filteredItems.first(where: { $0.id == id }) {
            HistoryDetailView(item: item, formatter: dateFormatter)
                .id(id)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                Text("Select a history item")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Helpers

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ensureSelection() {
        if let id = selectedID, filteredItems.contains(where: { $0.id == id }) { return }
        selectedID = filteredItems.first?.id
    }

    private func deleteSelected() {
        guard let id = selectedID else { return }
        store.delete(id: id)
        selectedID = filteredItems.first?.id
    }
}

// MARK: - List Row

struct HistoryRow: View {
    let item: HistoryItem
    let formatter: DateFormatter

    private var isImage: Bool { item.sourceText == "[Image]" }

    private var preview: String {
        item.result
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: isImage ? "photo" : "text.alignleft")
                    .font(.system(size: 10))
                    .foregroundStyle(isImage ? .purple : .blue)
                    .frame(width: 14)

                Text(item.actionName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(HistoryFormatting.relativeDate(item.date, formatter: formatter))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !item.modelName.isEmpty {
                Text(HistoryFormatting.shortModelName(item.modelName))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail Pane

struct HistoryDetailView: View {
    let item: HistoryItem
    let formatter: DateFormatter

    private var isImage: Bool { item.sourceText == "[Image]" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label(item.actionName, systemImage: isImage ? "photo" : "bolt.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isImage ? .purple : .blue)

                    if !item.modelName.isEmpty {
                        Text(HistoryFormatting.shortModelName(item.modelName))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer()

                    Text(formatter.string(from: item.date))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                if !isImage, !item.sourceText.isEmpty {
                    HistoryDetailSection(
                        title: "Source",
                        text: item.sourceText,
                        monospaced: true
                    )
                }

                HistoryDetailSection(
                    title: "Prompt",
                    text: item.fullPrompt,
                    monospaced: true
                )

                HistoryDetailSection(
                    title: "Result",
                    text: item.result,
                    monospaced: false
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Detail Section

private struct HistoryDetailSection: View {
    let title: String
    let text: String
    let monospaced: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Text(text)
                .font(.system(size: monospaced ? 11 : 13, design: monospaced ? .monospaced : .default))
                .foregroundStyle(monospaced ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Formatting Helpers

enum HistoryFormatting {
    static func shortModelName(_ name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    static func relativeDate(_ date: Date, formatter: DateFormatter) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 172800 { return "yesterday" }
        return formatter.string(from: date)
    }
}
