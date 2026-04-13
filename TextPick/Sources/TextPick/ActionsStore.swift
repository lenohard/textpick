import Foundation
import AppKit

// MARK: - Model

struct TextAction: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var icon: String          // SF Symbol name
    var prompt: String        // May contain {{text}} placeholder
    var isEnabled: Bool = true
    /// When true, this action appears in image mode (vision tasks)
    var supportsImage: Bool = false

    /// Renders the final prompt by substituting {{text}} with the captured text.
    /// If the prompt contains no placeholder, the captured text is appended.
    func renderPrompt(with text: String) -> String {
        if prompt.contains("{{text}}") {
            return prompt.replacingOccurrences(of: "{{text}}", with: text)
        }
        return prompt + "\n\n" + text
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
            supportsImage: true
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
对字符串 {{text}} 做一下变形。\
如果是多行文本就去掉所有的换行，变成一行；\
如果是JSON字符串，修复语法错误并prettify（增加换行、缩进、对齐）；\
如果是代码，修复格式和换行；\
如果是单词或句子，修复拼写/语法错误或简单paraphrase。\
只需要返回修复后的文本，其它什么都不要，因为我会直接用这个文本替换原始的文本。
"""
        ),
        TextAction(
            label: "Explain",
            icon: "text.magnifyingglass",
            prompt: """
用中文以整句话作为背景，解释下面这段文字中不常见的术语、单词、概念或典故。不要解释过于简单的东西，只解释最少见的，最多不超过3个。
如果只是一个短语或单词，就直接对这个词进行解释并提供更多背景，可以详细一点。
如果是一段代码，就解释这段代码的工作原理和细节，尤其是不那么明显的地方和使用方式。

{{text}}
"""
        ),
        TextAction(
            label: "Fix",
            icon: "checkmark.circle",
            prompt: """
请修复下面的句子或者单词，比如错别字、拼写错误、语法问题，或者用词不当的要选择更合适的单词。

{{text}}

只返回修正后的结果，不要有任何多余的解释和说明。返回结果会直接替换原文。
"""
        ),
        TextAction(
            label: "Answer",
            icon: "questionmark.bubble",
            prompt: "回答下面这个问题：\n\n{{text}}"
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

    private init() {
        load()
        loadVision()
    }

    // MARK: - Persistence

    func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([TextAction].self, from: data) {
            actions = decoded
        } else {
            actions = TextAction.defaults
            save()
        }
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
