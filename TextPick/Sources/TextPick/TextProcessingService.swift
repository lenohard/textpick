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

    struct StreamResult: Sendable {
        var content: String = ""
        var thinking: String = ""
    }

    typealias StreamHandler = @Sendable (StreamResult) -> Void

    /// For actions: the entire rendered prompt is passed as the system message,
    /// with an empty user turn so the model acts on it directly.
    func process(_ renderedPrompt: String) async -> String {
        do {
            return try await callAPI(system: renderedPrompt, user: "")
        } catch {
            return "⚠️ Error: \(error.localizedDescription)"
        }
    }

    /// Streaming variant — calls `onUpdate` as content/thinking arrive.
    func processStreaming(_ renderedPrompt: String, onUpdate: StreamHandler? = nil) async -> StreamResult {
        do {
            return try await callAPIStreaming(system: renderedPrompt, user: "", onUpdate: onUpdate)
        } catch {
            return StreamResult(content: "⚠️ Error: \(error.localizedDescription)")
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

    /// Streaming variant — calls `onUpdate` as content/thinking arrive.
    func processStreaming(_ instruction: String, userText: String, onUpdate: StreamHandler? = nil) async -> StreamResult {
        do {
            return try await callAPIStreaming(system: instruction, user: userText, onUpdate: onUpdate)
        } catch {
            return StreamResult(content: "⚠️ Error: \(error.localizedDescription)")
        }
    }

    /// Vision: send an image + prompt to the vision model (non-streaming).
    func processImage(imageData: Data, prompt: String) async -> String {
        do {
            return try await callVisionAPI(imageData: imageData, prompt: prompt)
        } catch {
            return "⚠️ Error: \(error.localizedDescription)"
        }
    }

    /// Vision streaming variant — calls `onUpdate` as content/thinking arrive.
    func processImageStreaming(imageData: Data, prompt: String, onUpdate: StreamHandler? = nil) async -> StreamResult {
        do {
            return try await callVisionAPIStreaming(imageData: imageData, prompt: prompt, onUpdate: onUpdate)
        } catch {
            return StreamResult(content: "⚠️ Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Vision API Call (non-streaming)

    private func callVisionAPI(imageData: Data, prompt: String) async throws -> String {
        let key = apiKey
        let url_base = baseURL
        let mdl = visionModel
        guard !key.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: "\(url_base)/chat/completions") else { throw APIError.invalidURL }

        let body: [String: Any] = visionRequestBody(imageData: imageData, prompt: prompt, model: mdl)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["Authorization": "Bearer \(key)"]
        let session = URLSession(configuration: config)
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 { throw APIError.unauthorized }
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIError.httpError(httpResponse.statusCode, body)
            }

            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            let content = decoded.choices.first?.message.content ?? ""
            if content.isEmpty { throw APIError.emptyResponse }
            return content
        } catch let error as URLError {
            throw APIError.fromURLError(error)
        }
    }

    // MARK: - Vision API Call (streaming)

    private func callVisionAPIStreaming(imageData: Data, prompt: String, onUpdate: StreamHandler?) async throws -> StreamResult {
        let key = apiKey
        let url_base = baseURL
        let mdl = visionModel
        guard !key.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: "\(url_base)/chat/completions") else { throw APIError.invalidURL }

        var body = visionRequestBody(imageData: imageData, prompt: prompt, model: mdl)
        body["stream"] = true

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let authHeader = "Bearer \(key)"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["Authorization": authHeader]
        let session = URLSession(configuration: config)
        do {
            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 { throw APIError.unauthorized }
                var errorBody = ""
                for try await line in bytes.lines { errorBody += line }
                throw APIError.httpError(httpResponse.statusCode, errorBody)
            }

            return try await consumeSSEStream(bytes: bytes, onUpdate: onUpdate)
        } catch let error as URLError {
            throw APIError.fromURLError(error)
        }
    }

    /// Builds the OpenAI vision-format request body (shared by streaming + non-streaming).
    private func visionRequestBody(imageData: Data, prompt: String, model mdl: String) -> [String: Any] {
        let base64 = imageData.base64EncodedString()
        let imageURL = "data:image/png;base64,\(base64)"
        let userContent: [[String: Any]] = [
            ["type": "image_url", "image_url": ["url": imageURL]],
            ["type": "text", "text": prompt]
        ]
        return [
            "model": mdl,
            "messages": [["role": "user", "content": userContent]],
            "max_tokens": 2048,
        ]
    }

    // MARK: - API Call (OpenAI-compatible)

    private func callAPI(system: String, user: String) async throws -> String {
        let key = apiKey
        let url_base = baseURL
        guard !key.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: "\(url_base)/chat/completions") else { throw APIError.invalidURL }

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

        // Use ephemeral session with auth in config to prevent header stripping
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["Authorization": authHeader]
        let session = URLSession(configuration: config)
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 { throw APIError.unauthorized }
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIError.httpError(httpResponse.statusCode, body)
            }

            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            let content = decoded.choices.first?.message.content ?? ""
            if content.isEmpty { throw APIError.emptyResponse }
            return content
        } catch let error as URLError {
            throw APIError.fromURLError(error)
        }
    }

    // MARK: - Streaming API Call

    private func callAPIStreaming(
        system: String,
        user: String,
        model overrideModel: String? = nil,
        onUpdate: StreamHandler?
    ) async throws -> StreamResult {
        let key = apiKey
        let url_base = baseURL
        let mdl = overrideModel ?? model
        guard !key.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: "\(url_base)/chat/completions") else { throw APIError.invalidURL }

        var messages: [[String: String]] = []
        if !system.isEmpty { messages.append(["role": "system", "content": system]) }
        if !user.isEmpty   { messages.append(["role": "user",   "content": user]) }
        if messages.isEmpty { throw APIError.emptyInput }

        let body: [String: Any] = [
            "model": mdl,
            "messages": messages,
            "max_tokens": 2048,
            "temperature": 0.3,
            "stream": true,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let authHeader = "Bearer \(key)"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["Authorization": authHeader]
        let session = URLSession(configuration: config)
        do {
            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 { throw APIError.unauthorized }
                var errorBody = ""
                for try await line in bytes.lines { errorBody += line }
                throw APIError.httpError(httpResponse.statusCode, errorBody)
            }

            return try await consumeSSEStream(bytes: bytes, onUpdate: onUpdate)
        } catch let error as URLError {
            throw APIError.fromURLError(error)
        }
    }

    /// Shared SSE consumption for text + vision streaming.
    private func consumeSSEStream(bytes: URLSession.AsyncBytes, onUpdate: StreamHandler?) async throws -> StreamResult {
        var result = StreamResult()
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { continue }

            var updated = false
            if let content = delta["content"] as? String, !content.isEmpty {
                result.content += content
                updated = true
            }
            let reasoning = (delta["reasoning_content"] as? String)
                ?? (delta["reasoning"] as? String)
            if let reasoning, !reasoning.isEmpty {
                result.thinking += reasoning
                updated = true
            }
            if updated { onUpdate?(result) }
        }
        if result.content.isEmpty && result.thinking.isEmpty {
            throw APIError.emptyResponse
        }
        return result
    }

    // MARK: - Model Metadata

    struct ModelMetadata: Sendable {
        let supportsVision: Bool
        let inputPricePerMillion: Double?   // USD per 1M input tokens
        let outputPricePerMillion: Double?  // USD per 1M output tokens
        let contextWindowTokens: Int?
        let maxOutputTokens: Int?
        let notes: String?
    }

    /// Hardcoded metadata for known models. Vision capability and pricing.
    static let modelMetadataTable: [String: ModelMetadata] = [
        // Anthropic
        "anthropic/claude-haiku-4-5":          ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.80,  outputPricePerMillion: 4.00,   contextWindowTokens: 200_000, maxOutputTokens: 8_192,  notes: nil),
        "anthropic/claude-haiku-4.5":          ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.80,  outputPricePerMillion: 4.00,   contextWindowTokens: 200_000, maxOutputTokens: 8_192,  notes: nil),
        "anthropic/claude-sonnet-4-5":         ModelMetadata(supportsVision: true,  inputPricePerMillion: 3.00,  outputPricePerMillion: 15.00,  contextWindowTokens: 200_000, maxOutputTokens: 8_192,  notes: nil),
        "anthropic/claude-sonnet-4.5":         ModelMetadata(supportsVision: true,  inputPricePerMillion: 3.00,  outputPricePerMillion: 15.00,  contextWindowTokens: 200_000, maxOutputTokens: 8_192,  notes: nil),
        "anthropic/claude-sonnet-4-6":         ModelMetadata(supportsVision: true,  inputPricePerMillion: 3.00,  outputPricePerMillion: 15.00,  contextWindowTokens: 200_000, maxOutputTokens: 8_192,  notes: nil),
        "anthropic/claude-opus-4-5":           ModelMetadata(supportsVision: true,  inputPricePerMillion: 15.00, outputPricePerMillion: 75.00,  contextWindowTokens: 200_000, maxOutputTokens: 32_000, notes: nil),
        "anthropic/claude-3-5-haiku-20241022": ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.80,  outputPricePerMillion: 4.00,   contextWindowTokens: 200_000, maxOutputTokens: 8_192,  notes: nil),
        "anthropic/claude-3-5-sonnet-20241022":ModelMetadata(supportsVision: true,  inputPricePerMillion: 3.00,  outputPricePerMillion: 15.00,  contextWindowTokens: 200_000, maxOutputTokens: 8_192,  notes: nil),
        // OpenAI
        "openai/gpt-4o":                       ModelMetadata(supportsVision: true,  inputPricePerMillion: 2.50,  outputPricePerMillion: 10.00,  contextWindowTokens: 128_000, maxOutputTokens: 16_384, notes: nil),
        "openai/gpt-4o-mini":                  ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.15,  outputPricePerMillion: 0.60,   contextWindowTokens: 128_000, maxOutputTokens: 16_384, notes: nil),
        "openai/gpt-4.1":                      ModelMetadata(supportsVision: true,  inputPricePerMillion: 2.00,  outputPricePerMillion: 8.00,   contextWindowTokens: 1_000_000, maxOutputTokens: 32_768, notes: nil),
        "openai/gpt-4.1-mini":                 ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.40,  outputPricePerMillion: 1.60,   contextWindowTokens: 1_000_000, maxOutputTokens: 32_768, notes: nil),
        "openai/gpt-4.1-nano":                 ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.10,  outputPricePerMillion: 0.40,   contextWindowTokens: 1_000_000, maxOutputTokens: 32_768, notes: nil),
        "openai/gpt-5-nano":                   ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.10,  outputPricePerMillion: 0.40,   contextWindowTokens: 400_000, maxOutputTokens: 128_000, notes: nil),
        "openai/o4-mini":                      ModelMetadata(supportsVision: true,  inputPricePerMillion: 1.10,  outputPricePerMillion: 4.40,   contextWindowTokens: 200_000, maxOutputTokens: 100_000, notes: "thinking"),
        "openai/o3":                           ModelMetadata(supportsVision: true,  inputPricePerMillion: 10.00, outputPricePerMillion: 40.00,  contextWindowTokens: 200_000, maxOutputTokens: 100_000, notes: "thinking"),
        // Google
        "google/gemini-2.0-flash":             ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.10,  outputPricePerMillion: 0.40,   contextWindowTokens: 1_000_000, maxOutputTokens: 8_192,  notes: nil),
        "google/gemini-2.0-flash-lite":        ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.075, outputPricePerMillion: 0.30,   contextWindowTokens: 1_000_000, maxOutputTokens: 8_192,  notes: nil),
        "google/gemini-2.5-flash":             ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.15,  outputPricePerMillion: 0.60,   contextWindowTokens: 1_000_000, maxOutputTokens: 65_536, notes: nil),
        "google/gemini-2.5-pro":               ModelMetadata(supportsVision: true,  inputPricePerMillion: 1.25,  outputPricePerMillion: 10.00,  contextWindowTokens: 1_000_000, maxOutputTokens: 65_536, notes: "thinking"),
        "google/gemini-3-flash":               ModelMetadata(supportsVision: true,  inputPricePerMillion: 0.15,  outputPricePerMillion: 0.60,   contextWindowTokens: 1_000_000, maxOutputTokens: 65_536, notes: nil),
        // DeepSeek
        "deepseek/deepseek-chat":              ModelMetadata(supportsVision: false, inputPricePerMillion: 0.27,  outputPricePerMillion: 1.10,   contextWindowTokens: 64_000,  maxOutputTokens: 8_192,  notes: nil),
        "deepseek/deepseek-r1":                ModelMetadata(supportsVision: false, inputPricePerMillion: 0.55,  outputPricePerMillion: 2.19,   contextWindowTokens: 64_000,  maxOutputTokens: 8_192,  notes: "thinking"),
    ]

    static func metadata(for modelID: String) -> ModelMetadata? {
        modelMetadataTable[modelID]
    }

    /// Rough token estimate: ~4 chars/token for English, ~2 for CJK. Use 3 as middle ground.
    static func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 3)
    }

    /// Estimate cost in USD for a request given input/output text.
    static func estimateCost(modelID: String, inputText: String, outputText: String) -> Double? {
        guard let meta = metadata(for: modelID),
              let inputPrice = meta.inputPricePerMillion,
              let outputPrice = meta.outputPricePerMillion else { return nil }
        let inputTokens = Double(estimateTokens(inputText))
        let outputTokens = Double(estimateTokens(outputText))
        return (inputTokens * inputPrice + outputTokens * outputPrice) / 1_000_000
    }

    /// Formatted cost string, e.g. "≈ $0.0012"
    static func formatCost(_ cost: Double) -> String {
        if cost < 0.0001 { return "< $0.0001" }
        if cost < 0.01   { return String(format: "≈ $%.4f", cost) }
        return String(format: "≈ $%.3f", cost)
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
            return (true, "✓ Connected — \(models.count) models available")
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
        case emptyResponse
        case missingAPIKey
        case unauthorized
        case httpError(Int, String)
        case timeout
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:            return "Invalid API URL — check Settings → API & Model"
            case .invalidResponse:       return "Invalid response from server — the gateway may be down"
            case .emptyInput:            return "No input provided"
            case .emptyResponse:         return "The model returned an empty response — try again or switch models"
            case .missingAPIKey:          return "API key not set — open Settings → API & Model and paste your key"
            case .unauthorized:          return "API key invalid or unauthorized (401) — check your key in Settings"
            case .httpError(let c, let b): return "HTTP \(c): \(b.prefix(300))"
            case .timeout:               return "Request timed out — check your network or try a faster model"
            case .networkError(let m):   return "Network error: \(m)"
            }
        }

        /// Map a URLError to a clear category (timeout vs offline vs generic).
        static func fromURLError(_ e: URLError) -> APIError {
            switch e.code {
            case .timedOut:            return .timeout
            case .notConnectedToInternet, .networkConnectionLost,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .networkError(e.localizedDescription)
            default:                   return .networkError(e.localizedDescription)
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
