import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum AIConfig {
    static var isConfigured: Bool {
        switch Prefs.aiProvider {
        case .azure:
            return !Prefs.azureEndpoint.isEmpty && !Prefs.azureDeployment.isEmpty
                && !Keychain.get(AIProvider.azure.keychainAccount).isEmpty
        case .deepseek:
            return !Keychain.get(AIProvider.deepseek.keychainAccount).isEmpty
        case .apple:
            return AppleOnDevice.isAvailable
        case .local:
            return !Prefs.localModel.isEmpty
        case .openai:
            return !Prefs.openaiModel.isEmpty
        }
    }
}

/// Apple Intelligence on-device model (FoundationModels, macOS 26+). No network, no API key.
enum AppleOnDevice {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var statusText: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return L("利用できます（オンデバイスで処理。データは外部に送信されません）")
            case .unavailable(let reason):
                return L("利用できません: %@（Apple Intelligence を「システム設定」でオンにしてください）", "\(reason)")
            }
        }
        return L("macOS 26 以降が必要です")
        #else
        return L("このビルドは FoundationModels 非対応の SDK で作成されています（Xcode 26 以降でビルドしてください）")
        #endif
    }

    static func respond(system: String, user: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard isAvailable else { throw AIError(message: statusText) }
            let session = LanguageModelSession(instructions: system)
            let response = try await session.respond(to: user)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw AIError(message: statusText)
    }
}

/// Minimal Chat Completions client.
/// - Azure OpenAI: {endpoint}/openai/deployments/{deployment}/chat/completions?api-version=…  (header: api-key)
/// - DeepSeek:     https://api.deepseek.com/chat/completions                                (Bearer)
/// - Ollama 等:     http://localhost:11434/v1/chat/completions                              (no key)
/// - OpenAI 互換:   {baseURL}/chat/completions                                               (Bearer)
/// - Apple:        FoundationModels (on-device)
enum AIClient {
    static func chat(system: String, user: String) async throws -> String {
        if Prefs.aiProvider == .apple || BuildVariant.localOnly {
            let r = try await AppleOnDevice.respond(system: system, user: user)
            guard !r.isEmpty else { throw AIError(message: L("空の応答が返されました")) }
            return r
        }
        #if LOCAL_ONLY
        throw AIError(message: L("内部エラー"))
        #else
        let request = try makeRequest(system: system, user: user)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError(message: L("サーバーから応答がありません"))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError(message: "HTTP \(http.statusCode): \(errorMessage(from: data))")
        }
        struct Resp: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String? }
                let message: Msg
            }
            let choices: [Choice]
        }
        let decoded: Resp
        do {
            decoded = try JSONDecoder().decode(Resp.self, from: data)
        } catch {
            throw AIError(message: L("応答を解析できません") + ": " + String(String(data: data, encoding: .utf8)?.prefix(200) ?? ""))
        }
        let content = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw AIError(message: L("空の応答が返されました")) }
        return stripThinking(content)
        #endif
    }

    private static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
            if let msg = obj["message"] as? String { return msg }
        }
        return String(String(data: data, encoding: .utf8)?.prefix(300) ?? "")
    }

    /// Some local reasoning models (DeepSeek R1, Qwen3 …) wrap their reasoning in <think>…</think>.
    private static func stripThinking(_ s: String) -> String {
        guard let end = s.range(of: "</think>") else { return s }
        return String(s[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimSlash(_ s: String) -> String {
        var s = s
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    #if !LOCAL_ONLY
    static func makeRequest(system: String, user: String) throws -> URLRequest {
        let messages: [[String: String]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ]
        var body: [String: Any] = ["messages": messages]
        var urlString: String
        var headers: [String: String] = ["Content-Type": "application/json"]
        var timeoutSeconds = 60

        switch Prefs.aiProvider {
        case .azure:
            let endpoint = trimSlash(Prefs.azureEndpoint)
            let deployment = Prefs.azureDeployment
            let key = Keychain.get(AIProvider.azure.keychainAccount)
            guard !endpoint.isEmpty, !key.isEmpty else {
                throw AIError(message: L("Azure OpenAI のエンドポイントと API キーを設定してください"))
            }
            if endpoint.contains("/chat/completions") {
                // A full URL was pasted.
                urlString = endpoint
                if !endpoint.contains("api-version") {
                    urlString += (endpoint.contains("?") ? "&" : "?") + "api-version=\(Prefs.azureAPIVersion)"
                }
                if endpoint.contains("/openai/v1/") && !deployment.isEmpty { body["model"] = deployment }
            } else {
                guard !deployment.isEmpty else { throw AIError(message: L("Azure のデプロイ名を設定してください")) }
                let dep = deployment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deployment
                urlString = "\(endpoint)/openai/deployments/\(dep)/chat/completions?api-version=\(Prefs.azureAPIVersion)"
            }
            headers["api-key"] = key

        case .deepseek:
            let key = Keychain.get(AIProvider.deepseek.keychainAccount)
            guard !key.isEmpty else { throw AIError(message: L("DeepSeek の API キーを設定してください")) }
            urlString = "\(trimSlash(Prefs.deepseekBaseURL))/chat/completions"
            body["model"] = Prefs.deepseekModel
            body["stream"] = false
            headers["Authorization"] = "Bearer \(key)"

        case .local, .openai:
            let isLocal = Prefs.aiProvider == .local
            let base = trimSlash(isLocal ? Prefs.localBaseURL : Prefs.openaiBaseURL)
            let model = isLocal ? Prefs.localModel : Prefs.openaiModel
            guard !base.isEmpty, !model.isEmpty else {
                throw AIError(message: L("ベース URL とモデル名を設定してください"))
            }
            urlString = base.hasSuffix("/chat/completions") ? base : "\(base)/chat/completions"
            body["model"] = model
            body["stream"] = false
            let key = Keychain.get(Prefs.aiProvider.keychainAccount)
            if !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }
            if isLocal { timeoutSeconds = 180 }

        case .apple:
            throw AIError(message: L("内部エラー"))
        }

        guard let url = URL(string: urlString) else { throw AIError(message: L("URL が不正です") + ": " + urlString) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = TimeInterval(timeoutSeconds)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
    #endif
}
