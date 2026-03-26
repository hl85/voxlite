import Foundation

public enum RemoteProvider: String, Codable, CaseIterable, Sendable {
    case deepseek
    case groq
    case siliconFlow
    case custom
}

public extension RemoteProvider {
    var displayName: String {
        switch self {
        case .deepseek: "Deepseek 深度求索"
        case .groq: "Groq"
        case .siliconFlow: "硅基流动 SiliconFlow"
        case .custom: "自定义 OpenAI 兼容"
        }
    }

    var defaultEndpoint: URL {
        switch self {
        case .deepseek:
            URL(string: "https://api.deepseek.com/v1") ?? URL(string: "about:blank")!
        case .groq:
            URL(string: "https://api.groq.com/openai/v1") ?? URL(string: "about:blank")!
        case .siliconFlow:
            URL(string: "https://api.siliconflow.cn/v1") ?? URL(string: "about:blank")!
        case .custom:
            URL(string: "https://example.com/v1") ?? URL(string: "about:blank")!
        }
    }

    var apiKeyHelpURL: URL? {
        switch self {
        case .deepseek: URL(string: "https://api-docs.deepseek.com/")
        case .groq: URL(string: "https://console.groq.com/docs/api-reference")
        case .siliconFlow: URL(string: "https://docs.siliconflow.cn/")
        case .custom: nil
        }
    }

    var supportsSTT: Bool {
        switch self {
        case .deepseek: false
        case .groq, .siliconFlow, .custom: true
        }
    }

    var supportsLLM: Bool {
        true
    }

    var sttModelPresets: [String] {
        switch self {
        case .deepseek: []
        case .groq: ["whisper-large-v3", "whisper-large-v3-turbo"]
        case .siliconFlow: ["FunAudioLLM/SenseVoiceSmall"]
        case .custom: []
        }
    }

    var llmModelPresets: [String] {
        switch self {
        case .deepseek: ["deepseek-chat", "deepseek-reasoner"]
        case .groq: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"]
        case .siliconFlow: ["deepseek-ai/DeepSeek-V3", "Qwen/Qwen2.5-72B-Instruct"]
        case .custom: []
        }
    }

    var sttModels: [String] {
        sttModelPresets
    }

    var llmModels: [String] {
        llmModelPresets
    }

    static var localOption: String {
        "Apple (内置模型)"
    }

    /// 仅返回支持 STT 的供应商（排除 Deepseek 等仅 LLM 供应商）
    static var sttSupportedProviders: [RemoteProvider] {
        allCases.filter { $0.supportsSTT }
    }
}
