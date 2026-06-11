import Foundation

/// Catalog of AI model providers Kelid can connect to. Cloud providers
/// authenticate with an API key; local runtimes (LM Studio, Ollama) take a
/// base URL instead.
enum AIProvider: String, CaseIterable, Identifiable, Hashable {
    case openRouter
    case openAI
    case anthropic
    case awsBedrock
    case lmStudio
    case ollama

    var id: String { rawValue }

    enum Auth {
        case apiKey
        case localEndpoint
    }

    var name: String {
        switch self {
        case .openRouter: "OpenRouter"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .awsBedrock: "AWS Bedrock"
        case .lmStudio: "LM Studio"
        case .ollama: "Ollama"
        }
    }

    /// Official brand mark in Assets (template-rendered, single color).
    var logoAsset: String {
        switch self {
        case .openRouter: "OpenRouterLogo"
        case .openAI: "OpenAILogo"
        case .anthropic: "AnthropicLogo"
        case .awsBedrock: "AWSLogo"
        case .lmStudio: "LMStudioLogo"
        case .ollama: "OllamaLogo"
        }
    }

    /// SF Symbol fallback if the asset is ever missing.
    var icon: String {
        switch self {
        case .openRouter: "arrow.triangle.branch"
        case .openAI: "brain"
        case .anthropic: "sparkle"
        case .awsBedrock: "cloud"
        case .lmStudio: "desktopcomputer"
        case .ollama: "server.rack"
        }
    }

    var auth: Auth {
        switch self {
        case .lmStudio, .ollama: .localEndpoint
        default: .apiKey
        }
    }

    /// Placeholder / hint shown in the credential field.
    var keyHint: String {
        switch self {
        case .openRouter: "sk-or-\u{2026}"
        case .openAI: "sk-\u{2026}"
        case .anthropic: "sk-ant-\u{2026}"
        case .awsBedrock: "AWS access key \u{2014} secret stored together"
        case .lmStudio, .ollama: ""
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .lmStudio: "http://localhost:1234/v1"
        case .ollama: "http://localhost:11434"
        default: ""
        }
    }

    var summary: String {
        switch self {
        case .openRouter: "One key, hundreds of models routed across providers."
        case .openAI: "GPT models directly from OpenAI."
        case .anthropic: "Claude models directly from Anthropic."
        case .awsBedrock: "Foundation models hosted on AWS Bedrock."
        case .lmStudio: "Local models served by LM Studio on this Mac."
        case .ollama: "Local models served by Ollama on this Mac."
        }
    }

    /// Keychain account under which this provider's secret is stored.
    var keychainAccount: String { "ai_provider.\(rawValue)" }
}
