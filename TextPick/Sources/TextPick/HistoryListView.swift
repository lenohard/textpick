import SwiftUI

struct HistoryListView: View {
    @ObservedObject var store = HistoryStore.shared
    
    // For date formatting
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
                List {
                    ForEach(store.items) { item in
                        HistoryRow(item: item, formatter: dateFormatter)
                            .padding(.vertical, 4)
                    }
                    .onDelete(perform: store.delete)
                }
                .listStyle(.plain)
                .frame(minHeight: 200, maxHeight: 400)
                
                Divider()
                
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        store.clear()
                    } label: {
                        Text("Clear History")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(8)
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }
}

struct HistoryRow: View {
    let item: HistoryItem
    let formatter: DateFormatter
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.actionName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                Spacer()
                Text(formatter.string(from: item.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            Text(item.sourceText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            
            if isExpanded {
                Text(item.result)
                    .font(.system(size: 13, design: .default))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
            } else {
                Text(item.result)
                    .font(.system(size: 13, design: .default))
                    .lineLimit(3)
                    .truncationMode(.tail)
            }
            
            HStack {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.result, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Result")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.blue)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Text(isExpanded ? "Show Less" : "Show More")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
