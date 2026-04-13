import Foundation

/// Sends text to an LLM API for processing via Vercel AI Gateway.
/// Uses OpenAI-compatible /v1/chat/completions endpoint.
///
/// Configuration (env vars / .env):
///   AI_GATEWAY_API_KEY  — required
///   TEXTPICK_API_URL    — default: https://ai-gateway.vercel.sh/v1
///   TEXTPICK_MODEL      — default: anthropic/claude-haiku-4.5
actor TextProcessingService {
    static let shared = TextProcessingService()
    private init() {}

    // MARK: - Configuration

    var apiKey: String {
        // UserDefaults takes priority; fall back to env var
        // Strip whitespace from pasted keys
        let key = UserDefaults.standard.string(forKey: "textpick.apiKey")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? ProcessInfo.processInfo.environment["AI_GATEWAY_API_KEY"]
            ?? ""
        return key
    }
    var baseURL: String {
        let url = UserDefaults.standard.string(forKey: "textpick.apiURL")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? ProcessInfo.processInfo.environment["TEXTPICK_API_URL"]
            ?? "https://ai-gateway.vercel.sh/v1"
        return url.hasSuffix("/") ? String(url.dropLast()) : url  // remove trailing slash
    }
    var model: String {
        // UserDefaults (Settings UI) takes priority over env var
        UserDefaults.standard.string(forKey: "textpick.model")?.nilIfEmpty
            ?? ProcessInfo.processInfo.environment["TEXTPICK_MODEL"]
            ?? "anthropic/claude-haiku-4.5"
    }

    var visionModel: String {
        UserDefaults.standard.string(forKey: "textpick.visionModel")?.nilIfEmpty
            ?? model  // fall back to text model if it supports vision
    }

    // MARK: - Public API

    /// For actions: the entire rendered prompt is passed as the system message,
    /// with an empty user turn so the model acts on it directly.
    func process(_ renderedPrompt: String) async -> String {
        do {
            return try await callAPI(system: renderedPrompt, user: "")
        } catch {
            return "⚠️ Error: \(error.localizedDescription)"
        }
    }

    /// For custom prompts: system = instruction, user = captured text.
    func process(_ instruction: String, userText: String) async -> String {
        do {
            return try await callAPI(system: instruction, user: userText)
        } catch {
            return "⚠️ Error: \(error.localizedDescription)"
        }
    }

    /// Vision: send an image + prompt to the vision model.
    func processImage(imageData: Data, prompt: String) async -> String {
        do {
            return try await callVisionAPI(imageData: imageData, prompt: prompt)
        } catch {
            return "⚠️ Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Vision API Call

    private func callVisionAPI(imageData: Data, prompt: String) async throws -> String {
        let key = apiKey
        let url_base = baseURL
        let mdl = visionModel
        guard !key.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: "\(url_base)/chat/completions") else { throw APIError.invalidURL }

        let base64 = imageData.base64EncodedString()
        let imageURL = "data:image/png;base64,\(base64)"

        // OpenAI vision format
        let userContent: [[String: Any]] = [
            ["type": "image_url", "image_url": ["url": imageURL]],
            ["type": "text", "text": prompt]
        ]
        let messages: [[String: Any]] = [
            ["role": "user", "content": userContent]
        ]
        let body: [String: Any] = [
            "model": mdl,
            "messages": messages,
            "max_tokens": 2048,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["Authorization": "Bearer \(key)"]
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        return decoded.choices.first?.message.content ?? "(empty response)"
    }

    // MARK: - API Call (OpenAI-compatible)

    private func callAPI(system: String, user: String) async throws -> String {
        let key = apiKey
        let url_base = baseURL
        let mdl = model
        print("[TextPick] API key length=\(key.count) prefix='\(key.prefix(6))...' url=\(url_base) model=\(mdl)")
        guard !key.isEmpty else {
            throw APIError.missingAPIKey
        }
        guard let url = URL(string: "\(url_base)/chat/completions") else {
            throw APIError.invalidURL
        }

        var messages: [[String: String]] = []
        if !system.isEmpty { messages.append(["role": "system", "content": system]) }
        if !user.isEmpty   { messages.append(["role": "user",   "content": user]) }
        if messages.isEmpty { throw APIError.emptyInput }

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": 2048,
            "temperature": 0.3,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let authHeader = "Bearer \(key)"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        print("[TextPick] Auth header set: Bearer \(key.prefix(6))... (total \(authHeader.count) chars)")
        print("[TextPick] Request headers: \(request.allHTTPHeaderFields ?? [:])")
        print("[TextPick] POST \(url.absoluteString) model=\(mdl)")

        // Use ephemeral session with auth in config to prevent header stripping
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["Authorization": authHeader]
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        return decoded.choices.first?.message.content ?? "(empty response)"
    }

    // MARK: - Model Metadata

    struct ModelMetadata: Sendable {
        let supportsVision: Bool
        let inputPricePerMillion: Double?   // USD per 1M input tokens
        let outputPricePerMillion: Double?  // USD per 1M output tokens
        let notes: String?
    }

    /// Hardcoded metadata for known models. Vision capability and pricing.
    static let modelMetadataTable: [String: ModelMetadata] = [
        // Anthropic
        "anthropic/claude-haiku-4-5":         ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.80,  outputPricePerMillion: 4.00,   notes: nil),
        "anthropic/claude-haiku-4.5":         ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.80,  outputPricePerMillion: 4.00,   notes: nil),
        "anthropic/claude-sonnet-4-5":        ModelMetadata(supportsVision: true,  inputPricePerMillion: 3.00,  outputPricePerMillion: 15.00,  notes: nil),
        "anthropic/claude-sonnet-4.5":        ModelMetadata(supportsVision: true,  inputPricePerMillion: 3.00,  outputPricePerMillion: 15.00,  notes: nil),
        "anthropic/claude-sonnet-4-6":        ModelMetadata(supportsVision: true,  inputPricePerMillion: 3.00,  outputPricePerMillion: 15.00,  notes: nil),
        "anthropic/claude-opus-4-5":          ModelMetadata(supportsVision: true,  inputPricePerMillion: 15.00, outputPricePerMillion: 75.00,  notes: nil),
        "anthropic/claude-3-5-haiku-20241022":ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.80,  outputPricePerMillion: 4.00,   notes: nil),
        "anthropic/claude-3-5-sonnet-20241022":ModelMetadata(supportsVision: true, inputPricePerMillion: 3.00,  outputPricePerMillion: 15.00,  notes: nil),
        // OpenAI
        "openai/gpt-4o":                      ModelMetadata(supportsVision: true,  inputPricePerMillion: 2.50,  outputPricePerMillion: 10.00,  notes: nil),
        "openai/gpt-4o-mini":                 ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.15,  outputPricePerMillion: 0.60,   notes: nil),
        "openai/gpt-4.1":                     ModelMetadata(supportsVision: true,  inputPricePerMillion: 2.00,  outputPricePerMillion: 8.00,   notes: nil),
        "openai/gpt-4.1-mini":                ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.40,  outputPricePerMillion: 1.60,   notes: nil),
        "openai/gpt-4.1-nano":                ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.10,  outputPricePerMillion: 0.40,   notes: nil),
        "openai/gpt-5-nano":                  ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.10,  outputPricePerMillion: 0.40,   notes: nil),
        "openai/o4-mini":                     ModelMetadata(supportsVision: true,  inputPricePerMillion: 1.10,  outputPricePerMillion: 4.40,   notes: "thinking"),
        "openai/o3":                          ModelMetadata(supportsVision: true,  inputPricePerMillion: 10.00, outputPricePerMillion: 40.00,  notes: "thinking"),
        // Google
        "google/gemini-2.0-flash":            ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.10,  outputPricePerMillion: 0.40,   notes: nil),
        "google/gemini-2.0-flash-lite":       ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.075, outputPricePerMillion: 0.30,   notes: nil),
        "google/gemini-2.5-flash":            ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.15,  outputPricePerMillion: 0.60,   notes: nil),
        "google/gemini-2.5-pro":              ModelMetadata(supportsVision: true,  inputPricePerMillion: 1.25,  outputPricePerMillion: 10.00,  notes: "thinking"),
        "google/gemini-3-flash":              ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.15,  outputPricePerMillion: 0.60,   notes: nil),
        // DeepSeek
        "deepseek/deepseek-chat":             ModelMetadata(supportsVision: false, inputPricePerMillion: 0.27,  outputPricePerMillion: 1.10,   notes: nil),
        "deepseek/deepseek-r1":               ModelMetadata(supportsVision: false, inputPricePerMillion: 0.55,  outputPricePerMillion: 2.19,   notes: "thinking"),
    ]

    static func metadata(for modelID: String) -> ModelMetadata? {
        modelMetadataTable[modelID]
    }

    // MARK: - Fetch Models

    struct ModelInfo: Identifiable, Sendable, Codable {
        let id: String
        var displayName: String {
            let parts = id.split(separator: "/")
            guard parts.count >= 2 else { return id }
            let name = String(parts[1])
                .replacingOccurrences(of: "-", with: " ")
            // Capitalize each word
            return name.split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        var provider: String {
            String(id.split(separator: "/").first ?? Substring(id))
        }
        var metadata: ModelMetadata? { TextProcessingService.metadata(for: id) }
        var supportsVision: Bool { metadata?.supportsVision ?? false }
    }

    /// Lightweight test: hits /v1/models to verify key + connectivity.
    func testConnection() async -> (ok: Bool, message: String) {
        let key = apiKey
        guard !key.isEmpty else {
            return (false, "API key is empty — paste it in Settings → API & Model")
        }
        do {
            let models = try await fetchModels()
            return (true, "✓ Connected — \(models.count) models available (key prefix: \(key.prefix(6))…)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func fetchModels() async throws -> [ModelInfo] {
        guard let url = URL(string: "\(baseURL)/models") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(ModelsListResponse.self, from: data)
        return decoded.data
            .map { ModelInfo(id: $0.id) }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Errors

    enum APIError: LocalizedError {
        case invalidURL
        case invalidResponse
        case emptyInput
        case missingAPIKey
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:              return "Invalid API URL — check Settings → API & Model"
            case .invalidResponse:         return "Invalid response from server"
            case .emptyInput:              return "No input provided"
            case .missingAPIKey:           return "API key not set — open Settings → API & Model and paste your key"
            case .httpError(let c, let b): return "HTTP \(c): \(b.prefix(300))"
            }
        }
    }
}

// MARK: - Response Models

private struct ModelsListResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
