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
        UserDefaults.standard.string(forKey: "textpick.apiKey")?.nilIfEmpty
            ?? ProcessInfo.processInfo.environment["AI_GATEWAY_API_KEY"]
            ?? ""
    }
    var baseURL: String {
        UserDefaults.standard.string(forKey: "textpick.apiURL")?.nilIfEmpty
            ?? ProcessInfo.processInfo.environment["TEXTPICK_API_URL"]
            ?? "https://ai-gateway.vercel.sh/v1"
    }
    var model: String {
        // UserDefaults (Settings UI) takes priority over env var
        UserDefaults.standard.string(forKey: "textpick.model")?.nilIfEmpty
            ?? ProcessInfo.processInfo.environment["TEXTPICK_MODEL"]
            ?? "anthropic/claude-haiku-4.5"
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

    // MARK: - API Call (OpenAI-compatible)

    private func callAPI(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw APIError.missingAPIKey
        }
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

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
