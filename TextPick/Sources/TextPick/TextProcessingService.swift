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
    /// Reuse one ephemeral session so repeated requests can reuse connections
    /// while still avoiding persistent cookies/cache data.
    private let urlSession: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 4
        urlSession = URLSession(configuration: configuration)
    }

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

    var reasoningEffort: String {
        UserDefaults.standard.string(forKey: "textpick.reasoningEffort")?.nilIfEmpty ?? ""
    }

    var apiProtocol: APIProtocol {
        let raw = UserDefaults.standard.string(forKey: "textpick.apiProtocol")?.nilIfEmpty
            ?? ProcessInfo.processInfo.environment["TEXTPICK_API_PROTOCOL"]
            ?? "chat-completions"
        return APIProtocol(rawValue: raw) ?? .chatCompletions
    }

    // MARK: - API Protocol

    /// Supported API protocol formats.
    enum APIProtocol: String, CaseIterable, Codable, Sendable {
        case chatCompletions = "chat-completions"
        case messages = "messages"
        case responses = "responses"

        var path: String {
            switch self {
            case .chatCompletions: return "/chat/completions"
            case .messages:       return "/messages"
            case .responses:      return "/responses"
            }
        }

        var displayName: String {
            switch self {
            case .chatCompletions: return "Chat Completions"
            case .messages:       return "Messages (Anthropic)"
            case .responses:      return "Responses"
            }
        }
    }

    // MARK: - Public API

    struct StreamResult: Sendable {
        var content: String = ""
        var thinking: String = ""
    }

    typealias StreamHandler = @MainActor @Sendable (StreamResult) -> Void

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
        } catch is CancellationError {
            return StreamResult()
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
        } catch is CancellationError {
            return StreamResult()
        } catch {
            return StreamResult(content: "⚠️ Error: \(error.localizedDescription)")
        }
    }

    /// Multi-turn: caller builds the full messages array (system/user/assistant turns).
    /// Text content is a String; vision user content is an Array of content parts.
    /// Works for both text and vision conversations.
    func processMessagesStreaming(
        messages: [[String: Any]],
        model overrideModel: String? = nil,
        onUpdate: StreamHandler? = nil
    ) async -> StreamResult {
        do {
            return try await callAPIMessages(messages: messages, model: overrideModel, onUpdate: onUpdate)
        } catch is CancellationError {
            return StreamResult()
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
        } catch is CancellationError {
            return StreamResult()
        } catch {
            return StreamResult(content: "⚠️ Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Multi-turn API Call (streaming)

    private func callAPIMessages(
        messages: [[String: Any]],
        model overrideModel: String?,
        onUpdate: StreamHandler?
    ) async throws -> StreamResult {
        let key = apiKey
        let url_base = baseURL
        let mdl = overrideModel ?? model
        let proto = apiProtocol
        guard !key.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: "\(url_base)\(proto.path)") else { throw APIError.invalidURL }
        guard !messages.isEmpty else { throw APIError.emptyInput }

        let body = makeRequestBody(protocol: proto, model: mdl, messages: messages, stream: true, reasoningEffort: reasoningEffort)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        setAuthHeaders(on: &request, key: key, protocol: proto)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        do {
            let (bytes, response) = try await urlSession.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 { throw APIError.unauthorized }
                var errorBody = ""
                for try await line in bytes.lines { errorBody += line }
                throw APIError.httpError(httpResponse.statusCode, errorBody)
            }
            return try await consumeSSEStream(bytes: bytes, onUpdate: onUpdate, protocol: proto)
        } catch let error as URLError {
            throw APIError.fromURLError(error)
        }
    }

    // MARK: - Vision API Call (non-streaming)

    private func callVisionAPI(imageData: Data, prompt: String) async throws -> String {
        let key = apiKey
        let url_base = baseURL
        let mdl = visionModel
        let proto = apiProtocol
        guard !key.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: "\(url_base)\(proto.path)") else { throw APIError.invalidURL }

        let body: [String: Any] = visionRequestBody(imageData: imageData, prompt: prompt, model: mdl, protocol: proto)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        setAuthHeaders(on: &request, key: key, protocol: proto)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 { throw APIError.unauthorized }
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIError.httpError(httpResponse.statusCode, body)
            }

            return try extractContent(from: data, protocol: proto)
        } catch let error as URLError {
            throw APIError.fromURLError(error)
        }
    }

    // MARK: - Vision API Call (streaming)

    private func callVisionAPIStreaming(imageData: Data, prompt: String, onUpdate: StreamHandler?) async throws -> StreamResult {
        let key = apiKey
        let url_base = baseURL
        let mdl = visionModel
        let proto = apiProtocol
        guard !key.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: "\(url_base)\(proto.path)") else { throw APIError.invalidURL }

        var body = visionRequestBody(imageData: imageData, prompt: prompt, model: mdl, protocol: proto)
        body["stream"] = true

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        setAuthHeaders(on: &request, key: key, protocol: proto)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        do {
            let (bytes, response) = try await urlSession.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 { throw APIError.unauthorized }
                var errorBody = ""
                for try await line in bytes.lines { errorBody += line }
                throw APIError.httpError(httpResponse.statusCode, errorBody)
            }

            return try await consumeSSEStream(bytes: bytes, onUpdate: onUpdate, protocol: apiProtocol)
        } catch let error as URLError {
            throw APIError.fromURLError(error)
        }
    }

    /// Builds the vision-format request body (shared by streaming + non-streaming).
    private func visionRequestBody(imageData: Data, prompt: String, model mdl: String, protocol proto: APIProtocol = .chatCompletions) -> [String: Any] {
        let base64 = imageData.base64EncodedString()

        switch proto {
        case .messages:
            // Anthropic Messages API: source block for images
            let userContent: [[String: Any]] = [
                ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": base64]],
                ["type": "text", "text": prompt]
            ]
            var body: [String: Any] = [
                "model": mdl,
                "messages": [["role": "user", "content": userContent]],
                "max_tokens": 4096,
            ]
            return body

        default:
            // Chat Completions / Responses: image_url format
            let imageURL = "data:image/png;base64,\(base64)"
            let userContent: [[String: Any]] = [
                ["type": "image_url", "image_url": ["url": imageURL]],
                ["type": "text", "text": prompt]
            ]
            var body: [String: Any] = [
                "model": mdl,
                "messages": [["role": "user", "content": userContent]],
            ]
            if !reasoningEffort.isEmpty {
                body["reasoningEffort"] = reasoningEffort
            }
            return body
        }
    }

    // MARK: - API Call (protocol-aware)

    private func callAPI(system: String, user: String) async throws -> String {
        let key = apiKey
        let url_base = baseURL
        let proto = apiProtocol
        let mdl = model
        guard !key.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: "\(url_base)\(proto.path)") else { throw APIError.invalidURL }

        var messages: [[String: Any]] = []
        if !system.isEmpty { messages.append(["role": "system", "content": system]) }
        if !user.isEmpty   { messages.append(["role": "user",   "content": user]) }
        if messages.isEmpty { throw APIError.emptyInput }

        let body = makeRequestBody(protocol: proto, model: mdl, messages: messages, stream: false, reasoningEffort: reasoningEffort)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        setAuthHeaders(on: &request, key: key, protocol: proto)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 { throw APIError.unauthorized }
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIError.httpError(httpResponse.statusCode, body)
            }

            return try extractContent(from: data, protocol: proto)
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
        let proto = apiProtocol
        guard !key.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: "\(url_base)\(proto.path)") else { throw APIError.invalidURL }

        var messages: [[String: Any]] = []
        if !system.isEmpty { messages.append(["role": "system", "content": system]) }
        if !user.isEmpty   { messages.append(["role": "user",   "content": user]) }
        if messages.isEmpty { throw APIError.emptyInput }

        let body = makeRequestBody(protocol: proto, model: mdl, messages: messages, stream: true, reasoningEffort: reasoningEffort)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        setAuthHeaders(on: &request, key: key, protocol: proto)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        do {
            let (bytes, response) = try await urlSession.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 { throw APIError.unauthorized }
                var errorBody = ""
                for try await line in bytes.lines { errorBody += line }
                throw APIError.httpError(httpResponse.statusCode, errorBody)
            }

            return try await consumeSSEStream(bytes: bytes, onUpdate: onUpdate, protocol: apiProtocol)
        } catch let error as URLError {
            throw APIError.fromURLError(error)
        }
    }

    /// Shared SSE consumption for all protocol streaming formats.
    private func consumeSSEStream(bytes: URLSession.AsyncBytes, onUpdate: StreamHandler?, protocol proto: APIProtocol) async throws -> StreamResult {
        var result = StreamResult()
        var lastUpdateAt = Date.distantPast
        var hasPendingUpdate = false
        var lastEvent: String?  // for event-based protocols (Anthropic Messages, OpenAI Responses)

        for try await line in bytes.lines {
            try Task.checkCancellation()

            // Track event type for event-based protocols
            if line.hasPrefix("event: ") {
                lastEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                continue
            }

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            var updated = false

            switch proto {
            case .chatCompletions:
                guard let choices = json["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any] else { continue }
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

            case .messages:
                // Anthropic Messages API streaming
                guard let type = json["type"] as? String else { continue }
                switch type {
                case "content_block_delta":
                    if let delta = json["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        result.content += text
                        updated = true
                    }
                case "content_block_start":
                    if let block = json["content_block"] as? [String: Any],
                       let text = block["text"] as? String {
                        result.content += text
                        updated = true
                    }
                case "message_delta":
                    if let delta = json["delta"] as? [String: Any],
                       let stopReason = delta["stop_reason"] as? String {
                        // End of generation — nothing to accumulate
                    }
                default:
                    break
                }

            case .responses:
                // OpenAI Responses API streaming
                if let type = json["type"] as? String, type == "response.output_text.delta",
                   let delta = json["delta"] as? String {
                    result.content += delta
                    updated = true
                }
            }

            if updated, let onUpdate {
                hasPendingUpdate = true
                let now = Date()
                if now.timeIntervalSince(lastUpdateAt) >= 0.05 {
                    let snapshot = result
                    await MainActor.run { onUpdate(snapshot) }
                    lastUpdateAt = now
                    hasPendingUpdate = false
                }
            }
        }
        if hasPendingUpdate, let onUpdate {
            let snapshot = result
            await MainActor.run { onUpdate(snapshot) }
        }
        if result.content.isEmpty && result.thinking.isEmpty {
            throw APIError.emptyResponse
        }
        return result
    }

    // MARK: - Request Body & Response Helpers

    /// Build a protocol-specific request body.
    private func makeRequestBody(
        protocol proto: APIProtocol,
        model mdl: String,
        messages: [[String: Any]],
        stream: Bool,
        reasoningEffort: String
    ) -> [String: Any] {
        var body: [String: Any] = ["model": mdl]

        switch proto {
        case .chatCompletions:
            body["messages"] = messages
            body["temperature"] = 0.3
            if stream { body["stream"] = true }
            if !reasoningEffort.isEmpty { body["reasoningEffort"] = reasoningEffort }

        case .responses:
            // Responses API: instructions 顶层放系统提示, input 不含 system
            let systemText = messages.compactMap { m -> String? in
                guard let role = m["role"] as? String, role == "system",
                      let content = m["content"] as? String else { return nil }
                return content
            }.first
            if let systemText, !systemText.isEmpty {
                body["instructions"] = systemText
            }
            var input = messages.filter { ($0["role"] as? String) != "system" }
            // Responses API 要求 input 非空，纯 system 指令时补一条默认用户消息
            if input.isEmpty {
                input = [["role": "user", "content": "Please proceed."]]
            }
            body["input"] = input
            body["temperature"] = 0.3
            body["max_output_tokens"] = 4096
            body["store"] = false
            if stream { body["stream"] = true }
            if !reasoningEffort.isEmpty { body["reasoningEffort"] = reasoningEffort }

        case .messages:
            // Anthropic: system is top-level; messages exclude system role
            let systemText = messages.compactMap { m -> String? in
                guard let role = m["role"] as? String, role == "system",
                      let content = m["content"] as? String else { return nil }
                return content
            }.first
            if let systemText, !systemText.isEmpty {
                body["system"] = systemText
            }
            body["messages"] = messages.filter { ($0["role"] as? String) != "system" }
            body["max_tokens"] = 4096  // required by Anthropic
            if stream { body["stream"] = true }
        }

        return body
    }

    /// Set protocol-specific auth headers on the request.
    private func setAuthHeaders(on request: inout URLRequest, key: String, protocol proto: APIProtocol) {
        switch proto {
        case .messages:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        default:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }

    /// Extract content from a non-streaming response for any protocol.
    private func extractContent(from data: Data, protocol proto: APIProtocol) throws -> String {
        switch proto {
        case .chatCompletions:
            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            let content = decoded.choices.first?.message.content ?? ""
            if content.isEmpty { throw APIError.emptyResponse }
            return content

        case .messages:
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let contentArray = json["content"] as? [[String: Any]],
                  let text = contentArray.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
                  !text.isEmpty else {
                throw APIError.emptyResponse
            }
            return text

        case .responses:
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let output = json["output"] as? [[String: Any]],
                  let firstOutput = output.first,
                  let contentArray = firstOutput["content"] as? [[String: Any]],
                  let text = contentArray.first?["text"] as? String,
                  !text.isEmpty else {
                throw APIError.emptyResponse
            }
            return text
        }
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
        let (data, response) = try await urlSession.data(for: request)
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
