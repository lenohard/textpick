import Foundation
import Combine

struct HistoryItem: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date
    var sourceText: String   // original selected text
    var actionName: String
    var fullPrompt: String   // actual prompt sent to LLM
    var result: String
    var modelName: String    // model used

    // Migration: handle old records missing fullPrompt / modelName
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(UUID.self,   forKey: .id)         ?? UUID()
        date       = try c.decode(Date.self,            forKey: .date)
        sourceText = try c.decode(String.self,          forKey: .sourceText)
        actionName = try c.decode(String.self,          forKey: .actionName)
        fullPrompt = try c.decodeIfPresent(String.self, forKey: .fullPrompt) ?? sourceText
        result     = try c.decode(String.self,          forKey: .result)
        modelName  = try c.decodeIfPresent(String.self, forKey: .modelName)  ?? ""
    }

    init(date: Date, sourceText: String, actionName: String, fullPrompt: String, result: String, modelName: String) {
        self.id = UUID()
        self.date = date
        self.sourceText = sourceText
        self.actionName = actionName
        self.fullPrompt = fullPrompt
        self.result = result
        self.modelName = modelName
    }
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
    
    func add(sourceText: String, actionName: String, fullPrompt: String, result: String, modelName: String = "") {
        let item = HistoryItem(date: Date(), sourceText: sourceText, actionName: actionName, fullPrompt: fullPrompt, result: result, modelName: modelName)
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
