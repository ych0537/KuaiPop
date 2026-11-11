import Foundation

enum TriggerMode: String, CaseIterable, Identifiable {
    case auto, hotkey, services
    var id: String { rawValue }
}

/// Compile-time build variant.
/// `KuaiPop Local` is built with `-DLOCAL_ONLY`: only the on-device Apple Intelligence model
/// is available and no network AI code path is compiled in (for company Macs).
enum BuildVariant {
    #if LOCAL_ONLY
    static let localOnly = true
    #else
    static let localOnly = false
    #endif
}

enum AIProvider: String, CaseIterable, Identifiable {
    case apple, azure, deepseek, local, openai
    var id: String { rawValue }
    var label: String {
        switch self {
        case .azure: return "Azure OpenAI"
        case .deepseek: return "DeepSeek"
        case .apple: return L("Mac 本体の AI（Apple Intelligence・オンデバイス）・デフォルト")
        case .local: return L("Mac のローカルモデル（Ollama / LM Studio）")
        case .openai: return L("OpenAI / その他の OpenAI 互換 API")
        }
    }
    /// Providers offered in this build.
    static var available: [AIProvider] { BuildVariant.localOnly ? [.apple] : allCases }

    /// Keychain account name for this provider's API key.
    var keychainAccount: String { rawValue }
}

enum PolishTone: String, CaseIterable, Identifiable {
    case external, internalTone, concise
    var id: String { rawValue }
    var label: String {
        switch self {
        case .external: return L("社外（尊敬語・謙譲語）")
        case .internalTone: return L("社内（丁寧語）・デフォルト")
        case .concise: return L("簡潔（チャット向け）")
        }
    }
    var instruction: String {
        switch self {
        case .external: return "社外の取引先に送る、適切な尊敬語・謙譲語を使ったビジネス日本語"
        case .internalTone: return "社内の同僚に送る、丁寧語（です・ます調）のビジネス日本語"
        case .concise: return "チャット向けの、簡潔で失礼のないビジネス日本語"
        }
    }
}

enum TodoDestination: String, CaseIterable, Identifiable {
    case app, reminders
    var id: String { rawValue }
    var label: String {
        switch self {
        case .app: return L("アプリ内のリスト")
        case .reminders: return L("アプリ内のリスト ＋ macOS「リマインダー」")
        }
    }
}

enum SearchMode: String, CaseIterable, Identifiable {
    case teams, url
    var id: String { rawValue }
}

enum PrefKey {
    static let triggerMode = "triggerMode"
    static let uiLanguage = "uiLanguage"
    static let theme = "theme"
    static let clipboardFallback = "clipboardFallback"
    static let doubleCopy = "doubleCopy"
    static let excludedApps = "excludedApps"
    static let searchMode = "searchMode"
    static let searchURL = "searchURL"
    static let translateTarget = "translateTarget"
    static let translateFallback = "translateFallback"
    static let polishTone = "polishTone"
    static let todoDestination = "todoDestination"
    static let aiProvider = "aiProvider"
    static let azureEndpoint = "azureEndpoint"
    static let azureDeployment = "azureDeployment"
    static let azureAPIVersion = "azureAPIVersion"
    static let deepseekBaseURL = "deepseekBaseURL"
    static let deepseekModel = "deepseekModel"
    static let localBaseURL = "localBaseURL"
    static let localModel = "localModel"
    static let openaiBaseURL = "openaiBaseURL"
    static let openaiModel = "openaiModel"
}

enum Prefs {
    static let defaultExcluded = "com.apple.Terminal\ncom.googlecode.iterm2\ncom.apple.finder"
    static let defaultSearchURL = "https://www.google.com/search?q={q}"
    static let defaultAzureAPIVersion = "2024-10-21"
    static let defaultDeepSeekBase = "https://api.deepseek.com"
    static let defaultDeepSeekModel = "deepseek-chat"
    static let defaultLocalBase = "http://localhost:11434/v1"
    static let defaultOpenAIBase = "https://api.openai.com/v1"
    static let languages = ["简体中文", "繁體中文", "日本語", "English", "한국어"]

    static func register() {
        UserDefaults.standard.register(defaults: [
            PrefKey.triggerMode: TriggerMode.auto.rawValue,
            PrefKey.uiLanguage: AppLanguage.system.rawValue,
            PrefKey.theme: ThemePalette.blue.rawValue,
            PrefKey.clipboardFallback: true,
            PrefKey.doubleCopy: true,
            PrefKey.excludedApps: defaultExcluded,
            PrefKey.searchMode: SearchMode.teams.rawValue,
            PrefKey.searchURL: defaultSearchURL,
            PrefKey.translateTarget: "简体中文",
            PrefKey.translateFallback: "日本語",
            PrefKey.polishTone: PolishTone.internalTone.rawValue,
            PrefKey.todoDestination: TodoDestination.app.rawValue,
            PrefKey.aiProvider: AIProvider.apple.rawValue,
            PrefKey.azureEndpoint: "",
            PrefKey.azureDeployment: "",
            PrefKey.azureAPIVersion: defaultAzureAPIVersion,
            PrefKey.deepseekBaseURL: defaultDeepSeekBase,
            PrefKey.deepseekModel: defaultDeepSeekModel,
            PrefKey.localBaseURL: defaultLocalBase,
            PrefKey.localModel: "",
            PrefKey.openaiBaseURL: defaultOpenAIBase,
            PrefKey.openaiModel: "",
        ])
    }

    private static var d: UserDefaults { .standard }
    private static func str(_ k: String) -> String {
        (d.string(forKey: k) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var triggerMode: TriggerMode { TriggerMode(rawValue: str(PrefKey.triggerMode)) ?? .auto }
    static var clipboardFallback: Bool { d.bool(forKey: PrefKey.clipboardFallback) }
    static var doubleCopy: Bool { d.bool(forKey: PrefKey.doubleCopy) }
    static var excludedBundleIDs: Set<String> {
        let parts = str(PrefKey.excludedApps).components(separatedBy: CharacterSet(charactersIn: ",\n "))
        return Set(parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
    static var searchMode: SearchMode { SearchMode(rawValue: str(PrefKey.searchMode)) ?? .teams }
    static var searchURL: String { str(PrefKey.searchURL).isEmpty ? defaultSearchURL : str(PrefKey.searchURL) }
    static var translateTarget: String { str(PrefKey.translateTarget).isEmpty ? "简体中文" : str(PrefKey.translateTarget) }
    static var translateFallback: String { str(PrefKey.translateFallback).isEmpty ? "日本語" : str(PrefKey.translateFallback) }
    static var polishTone: PolishTone { PolishTone(rawValue: str(PrefKey.polishTone)) ?? .internalTone }
    static var todoDestination: TodoDestination { TodoDestination(rawValue: str(PrefKey.todoDestination)) ?? .app }
    static var aiProvider: AIProvider {
        if BuildVariant.localOnly { return .apple }
        return AIProvider(rawValue: str(PrefKey.aiProvider)) ?? .apple
    }
    static var azureEndpoint: String { str(PrefKey.azureEndpoint) }
    static var azureDeployment: String { str(PrefKey.azureDeployment) }
    static var azureAPIVersion: String { str(PrefKey.azureAPIVersion).isEmpty ? defaultAzureAPIVersion : str(PrefKey.azureAPIVersion) }
    static var deepseekBaseURL: String { str(PrefKey.deepseekBaseURL).isEmpty ? defaultDeepSeekBase : str(PrefKey.deepseekBaseURL) }
    static var deepseekModel: String { str(PrefKey.deepseekModel).isEmpty ? defaultDeepSeekModel : str(PrefKey.deepseekModel) }
    static var localBaseURL: String { str(PrefKey.localBaseURL).isEmpty ? defaultLocalBase : str(PrefKey.localBaseURL) }
    static var localModel: String { str(PrefKey.localModel) }
    static var openaiBaseURL: String { str(PrefKey.openaiBaseURL).isEmpty ? defaultOpenAIBase : str(PrefKey.openaiBaseURL) }
    static var openaiModel: String { str(PrefKey.openaiModel) }
}
