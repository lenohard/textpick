import Foundation
import Combine

struct HistoryItem: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date
    var sourceText: String
    var actionName: String
    var result: String
}

@MainActor
class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    
    @Published var items: [HistoryItem] = []
    
    private let fileURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let textPickDir = appSupport.appendingPathComponent("TextPick")
        
        try? FileManager.default.createDirectory(at: textPickDir, withIntermediateDirectories: true)
        self.fileURL = textPickDir.appendingPathComponent("history.json")
        
        load()
    }
    
    func add(sourceText: String, actionName: String, result: String) {
        let item = HistoryItem(date: Date(), sourceText: sourceText, actionName: actionName, result: result)
        items.insert(item, at: 0)
        
        // Keep max 100 items to avoid large JSON files
        if items.count > 100 {
            items.removeLast(items.count - 100)
        }
        
        save()
    }
    
    func clear() {
        items.removeAll()
        save()
    }
    
    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL)
        } catch {
            print("[HistoryStore] Failed to save history:", error)
        }
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            items = try JSONDecoder().decode([HistoryItem].self, from: data)
        } catch {
            print("[HistoryStore] Failed to decode history:", error)
        }
    }
}
