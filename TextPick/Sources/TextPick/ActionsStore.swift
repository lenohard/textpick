import Foundation
import AppKit

// MARK: - Model

enum FilenameFormat: String, Codable, CaseIterable {
    case descriptionOnly      = "description"
    case timestampOnly        = "timestamp"
    case timestampDescription = "timestamp-description"

    var displayName: String {
        switch self {
        case .descriptionOnly:      return "Description only"
        case .timestampOnly:        return "Timestamp only"
        case .timestampDescription: return "Timestamp + description"
        }
    }
}

struct TextAction: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var icon: String          // SF Symbol name
    var prompt: String        // May contain {{text}} placeholder
    var isEnabled: Bool = true
    /// When true, this action appears in image mode (vision tasks)
    var supportsImage: Bool = false

    // MARK: - Save-to-file (vision actions)
    /// When true, result is saved to disk after processing
    var saveToFile: Bool = false
    /// Directory to save results (default: ~/Pictures/TextPick)
    var saveDirectory: String = ""
    /// How to name the saved file
    var filenameFormat: FilenameFormat = .timestampDescription

    /// Renders the final prompt by substituting `{{text}}`.
    /// If the prompt contains no `{{text}}` placeholder, captured text is appended.
    func renderPrompt(with text: String) -> String {
        var result = prompt.replacingOccurrences(of: "{{text}}", with: text)
        if !prompt.contains("{{text}}"), !text.isEmpty {
            result += "\n\n" + text
        }
        return result
    }
}

// MARK: - Backward-compatible Decodable

extension TextAction {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decodeIfPresent(UUID.self,           forKey: .id)             ?? UUID()
        label          = try c.decode(String.self,                  forKey: .label)
        icon           = try c.decode(String.self,                  forKey: .icon)
        prompt         = try c.decode(String.self,                  forKey: .prompt)
        isEnabled      = try c.decodeIfPresent(Bool.self,           forKey: .isEnabled)      ?? true
        supportsImage  = try c.decodeIfPresent(Bool.self,           forKey: .supportsImage)  ?? false
        saveToFile     = try c.decodeIfPresent(Bool.self,           forKey: .saveToFile)     ?? false
        saveDirectory  = try c.decodeIfPresent(String.self,        forKey: .saveDirectory)  ?? ""
        filenameFormat = try c.decodeIfPresent(FilenameFormat.self, forKey: .filenameFormat) ?? .timestampDescription
    }
}

// MARK: - Default Actions

extension TextAction {
    /// Default vision actions shown when an image is captured
    static let visionDefaults: [TextAction] = [
        TextAction(
            label: "OCR",
            icon: "doc.text.viewfinder",
            prompt: "Extract all text from this image. Return only the extracted text, preserving original formatting and line breaks. If no text is found, say 'No text found'.",
            supportsImage: true
        ),
        TextAction(
            label: "Describe",
            icon: "eye",
            prompt: "Describe this image in detail. What do you see? Include objects, people, text, colors, layout, and any notable details.",
            supportsImage: true,
            saveToFile: false,
            saveDirectory: "",
            filenameFormat: .timestampDescription
        ),
        TextAction(
            label: "Ask",
            icon: "questionmark.bubble",
            prompt: "Look at this image and answer: what is shown here? Provide a comprehensive analysis.",
            supportsImage: true
        ),
        TextAction(
            label: "Translate",
            icon: "globe",
            prompt: "Extract all text from this image and translate it to Chinese. Show the original text and translation side by side.",
            supportsImage: true
        ),
        TextAction(
            label: "Summarize",
            icon: "list.bullet.rectangle",
            prompt: "Summarize the key information or content shown in this image.",
            supportsImage: true
        ),
    ]

    static let defaults: [TextAction] = [
        TextAction(
            label: "Format",
            icon: "wand.and.stars",
            prompt: """
Transform the string {{text}} as follows:
- If multi-line text, remove all line breaks to make a single line;
- If a JSON string, fix syntax errors and prettify (add line breaks, indentation, alignment);
- If code, fix formatting and line breaks;
- If a word or sentence, fix spelling/grammar errors or lightly paraphrase.
Return only the transformed text, nothing else, as it will directly replace the original text.
"""
        ),
        TextAction(
            label: "Explain",
            icon: "text.magnifyingglass",
            prompt: """
Explain uncommon terms, words, concepts, or allusions in the following text, using the full sentence as context. Do not explain overly simple things — only the least common ones, no more than 3.
If it's just a phrase or single word, explain that word directly with more background; you can be more detailed.
If it's code, explain how the code works and its details, especially non-obvious parts and usage.

{{text}}
"""
        ),
        TextAction(
            label: "Fix",
            icon: "checkmark.circle",
            prompt: """
Fix the following sentence or word — spelling errors, typos, grammar issues, or inappropriate word choices.

{{text}}

Return only the corrected result with no extra explanation. The result will directly replace the original text.
"""
        ),
        TextAction(
            label: "Answer",
            icon: "questionmark.bubble",
            prompt: "Answer the following question:\n\n{{text}}"
        ),
        TextAction(
            label: "Translate",
            icon: "globe",
            prompt: """
You are a translation expert. Your only task is to translate the text enclosed in <translate_input>.
Provide the translation result directly without any explanation if it's a sentence or paragraph. Keep original format.
If the text is a word or phrase, provide additional explanation — several common meanings of the word, not just a translation.

Translate into Chinese if the input is English; translate into English if the input is Chinese. If neither, translate into Chinese by default.

<translate_input>
{{text}}
</translate_input>
"""
        ),
    ]
}

// MARK: - Store

@MainActor
class ActionsStore: ObservableObject {
    static let shared = ActionsStore()

    @Published var actions: [TextAction] = []
    @Published var visionActions: [TextAction] = []

    private let defaultsKey = "textpick.actions"
    private let visionDefaultsKey = "textpick.visionActions"
    private let defaultsVersionKey = "textpick.actions.version"
    private static let defaultsVersion = 2
    private static let defaultLabels = Set(TextAction.defaults.map(\.label))

    private init() {
        load()
        loadVision()
    }

    // MARK: - Persistence

    func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([TextAction].self, from: data) {
            actions = decoded
            migratePromptsIfNeeded()
        } else {
            actions = TextAction.defaults
            UserDefaults.standard.set(Self.defaultsVersion, forKey: defaultsVersionKey)
            save()
        }
    }

    /// One-time migration: replace Chinese default prompts with English equivalents.
    private func migratePromptsIfNeeded() {
        let savedVersion = UserDefaults.standard.integer(forKey: defaultsVersionKey)
        guard savedVersion < Self.defaultsVersion else { return }

        let englishByLabel = Dictionary(uniqueKeysWithValues: TextAction.defaults.map { ($0.label, $0.prompt) })
        var changed = false
        for i in actions.indices {
            let action = actions[i]
            guard Self.defaultLabels.contains(action.label),
                  let englishPrompt = englishByLabel[action.label],
                  action.prompt.range(of: "\\p{Han}", options: .regularExpression) != nil else { continue }
            actions[i].prompt = englishPrompt
            changed = true
        }
        if changed { save() }
        UserDefaults.standard.set(Self.defaultsVersion, forKey: defaultsVersionKey)
    }

    func save() {
        if let data = try? JSONEncoder().encode(actions) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func loadVision() {
        if let data = UserDefaults.standard.data(forKey: visionDefaultsKey),
           let decoded = try? JSONDecoder().decode([TextAction].self, from: data) {
            visionActions = decoded
        } else {
            visionActions = TextAction.visionDefaults
            saveVision()
        }
    }

    func saveVision() {
        if let data = try? JSONEncoder().encode(visionActions) {
            UserDefaults.standard.set(data, forKey: visionDefaultsKey)
        }
    }

    func resetToDefaults() {
        actions = TextAction.defaults
        save()
    }

    func resetVisionToDefaults() {
        visionActions = TextAction.visionDefaults
        saveVision()
    }

    // MARK: - CRUD (text actions)

    func add(_ action: TextAction) {
        actions.append(action)
        save()
    }

    func update(_ action: TextAction) {
        if let idx = actions.firstIndex(where: { $0.id == action.id }) {
            actions[idx] = action
            save()
        }
    }

    func delete(at offsets: IndexSet) {
        actions.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        actions.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - CRUD (vision actions)

    func addVision(_ action: TextAction) {
        visionActions.append(action)
        saveVision()
    }

    func updateVision(_ action: TextAction) {
        if let idx = visionActions.firstIndex(where: { $0.id == action.id }) {
            visionActions[idx] = action
            saveVision()
        }
    }

    func deleteVision(at offsets: IndexSet) {
        visionActions.remove(atOffsets: offsets)
        saveVision()
    }

    func moveVision(from source: IndexSet, to destination: Int) {
        visionActions.move(fromOffsets: source, toOffset: destination)
        saveVision()
    }
}
