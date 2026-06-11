import Foundation

/// Lightweight connectivity check for an AI provider — a cheap authenticated
/// GET that proves the key (or local endpoint) actually works.
enum AIProviderClient {
    enum TestResult {
        case ok(String)
        case failed(String)
        case unsupported(String)
    }

    static func test(_ provider: AIProvider, key: String, baseURL: String) async -> TestResult {
        switch provider {
        case .openRouter:
            return await get("https://openrouter.ai/api/v1/key", bearer: key)
        case .openAI:
            return await get("https://api.openai.com/v1/models", bearer: key)
        case .anthropic:
            return await get(
                "https://api.anthropic.com/v1/models",
                headers: ["x-api-key": key, "anthropic-version": "2023-06-01"]
            )
        case .awsBedrock:
            return .unsupported("AWS Bedrock uses SigV4 signing — connectivity test arrives with the request engine.")
        case .lmStudio:
            return await get(endpoint(baseURL, "/models"))
        case .ollama:
            return await get(endpoint(baseURL, "/api/tags"))
        }
    }

    // MARK: - HTTP

    private static func endpoint(_ base: String, _ path: String) -> String {
        var b = base.trimmingCharacters(in: .whitespaces)
        if b.hasSuffix("/") { b.removeLast() }
        return b + path
    }

    /// Ephemeral session: no disk cache, no cookies — nothing about an
    /// authenticated request is ever written to disk.
    private static let session = URLSession(configuration: .ephemeral)

    private static func get(_ urlString: String, bearer: String? = nil, headers: [String: String] = [:]) async -> TestResult {
        guard let url = URL(string: urlString) else { return .failed("Invalid endpoint URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed("No response.") }
            switch http.statusCode {
            case 200...299: return .ok("Connection verified.")
            case 401, 403: return .failed("Key rejected (HTTP \(http.statusCode)).")
            default: return .failed("HTTP \(http.statusCode).")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
