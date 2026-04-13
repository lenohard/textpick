import SwiftUI

struct HistoryListView: View {
    @ObservedObject var store = HistoryStore.shared

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
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No history yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.items) { item in
                            HistoryCard(item: item, formatter: dateFormatter)
                        }
                    }
                    .padding(12)
                }
                .frame(minHeight: 220, maxHeight: 420)

                Divider()

                HStack {
                    Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button(role: .destructive) {
                        store.clear()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }
}

// MARK: - Shared Card (used by both HistoryListView and HistorySettingsTab)

struct HistoryCard: View {
    let item: HistoryItem
    let formatter: DateFormatter
    @State private var showPrompt = false
    @State private var showResult = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // ── Header ──────────────────────────────────────
            HStack(spacing: 6) {
                Label(item.actionName, systemImage: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)

                if !item.modelName.isEmpty {
                    Text("·").foregroundStyle(.quaternary).font(.system(size: 10))
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

            // ── Prompt section ──────────────────────────────
            SectionToggle(
                title: "Prompt",
                isExpanded: $showPrompt,
                preview: item.fullPrompt,
                copyText: item.fullPrompt,
                accentColor: .secondary
            ) {
                Text(item.fullPrompt)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            // ── Result section ──────────────────────────────
            SectionToggle(
                title: "Result",
                isExpanded: $showResult,
                preview: item.result,
                copyText: item.result,
                accentColor: .blue
            ) {
                Text(item.result)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Reusable collapsible section

private struct SectionToggle<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let preview: String
    let copyText: String
    let accentColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row — whole thing is tappable
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)

                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                if !isExpanded {
                    Text(preview.prefix(120).replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accentColor)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
