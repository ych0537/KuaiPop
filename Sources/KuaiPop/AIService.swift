import Foundation
import NaturalLanguage

/// Prompts for the three features (翻訳 / 推敲 / ToDo).
enum AIService {
    /// Languages offered as one-click switches in the translation result (中 / 日 / EN).
    struct QuickLang: Identifiable, Equatable {
        let name: String   // name used in the prompt and in Prefs
        let short: String  // chip label
        var id: String { name }
    }
    static let quickLangs = [
        QuickLang(name: "简体中文", short: "中"),
        QuickLang(name: "日本語", short: "日"),
        QuickLang(name: "English", short: "EN"),
    ]

    /// Best-effort language of the text, as a Prefs language name ("简体中文" / "日本語" / "English" / "한국어").
    static func detectLanguage(_ text: String) -> String? {
        // Any kana → Japanese (NLLanguageRecognizer often mistakes kanji-heavy Japanese for Chinese).
        if text.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) || (0x31F0...0x31FF).contains($0.value) }) {
            return "日本語"
        }
        let r = NLLanguageRecognizer()
        r.processString(text)
        switch r.dominantLanguage {
        case .simplifiedChinese?, .traditionalChinese?: return "简体中文"
        case .japanese?: return "日本語"
        case .english?: return "English"
        case .korean?: return "한국어"
        default: return nil
        }
    }

    private static func sameLanguage(_ a: String, _ b: String) -> Bool {
        let zh: Set<String> = ["简体中文", "繁體中文"]
        return a == b || (zh.contains(a) && zh.contains(b))
    }

    /// Default rule: Japanese / English / others → 翻訳先 (中文 by default); text already in that language → fallback (日本語).
    static func defaultTarget(for text: String) -> String {
        let target = Prefs.translateTarget
        if let src = detectLanguage(text), sameLanguage(src, target) {
            return Prefs.translateFallback
        }
        return target
    }

    static func translate(_ text: String, to explicitTarget: String? = nil) async throws -> String {
        let target = explicitTarget ?? defaultTarget(for: text)
        let system = """
        You are a professional translator for business communication.
        Translate the user's text into \(target).
        Keep personal names, numbers, URLs and code unchanged. Preserve line breaks.
        Output only the translation — no explanations, notes, romanization or quotation marks.
        """
        return try await AIClient.chat(system: system, user: text)
    }

    static let noChangeMarker = "__NO_CHANGE__"

    /// Returns nil when the text is already appropriate.
    static func polish(_ text: String) async throws -> String? {
        let tone = Prefs.polishTone.instruction
        let system = """
        あなたはビジネス日本語の校正者です。ユーザーの文章を「\(tone)」に推敲してください。
        - 意味・事実・日付・数値・固有名詞は変えないこと。
        - 原文が日本語以外の場合は、自然なビジネス日本語に訳した上で推敲すること。
        - 推敲後の文章のみを出力し、説明・前置き・引用符は付けないこと。
        - すでに適切で直す必要がない場合は、\(noChangeMarker) とだけ出力すること。
        """
        let result = try await AIClient.chat(system: system, user: text)
        if result.contains(noChangeMarker) { return nil }
        if normalize(result) == normalize(text) { return nil }
        return result
    }

    private static func normalize(_ s: String) -> String {
        s.filter { !$0.isWhitespace }
    }

    struct TodoExtraction {
        var title: String
        var due: Date?
        var hasTime: Bool
    }

    static func extractTodo(_ text: String) async -> TodoExtraction? {
        guard AIConfig.isConfigured else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyy-MM-dd（EEEE）HH:mm"
        let now = df.string(from: Date())
        let system = """
        以下のテキストから ToDo を 1 件だけ抽出し、JSON のみを出力してください（コードブロック不要）。
        形式: {"title": "タスク名", "due": "yyyy-MM-ddTHH:mm" | "yyyy-MM-dd" | null}
        - title: 原文と同じ言語で、30 文字以内の簡潔な体言止め（例:「見積書の修正版を共有」）。
        - due: 期限や日時が書かれている場合のみ。時刻がなければ日付のみ。なければ null。
        - 現在日時は \(now) です。「来週水曜日」「明日」などの相対表現はこれを基準に計算すること。
        """
        guard let raw = try? await AIClient.chat(system: system, user: text),
              let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }

        var due: Date?
        var hasTime = false
        if let s = (obj["due"] as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty, s != "null" {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            let normalized = s.replacingOccurrences(of: " ", with: "T")
            for fmt in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss"] {
                f.dateFormat = fmt
                if let d = f.date(from: normalized) { due = d; hasTime = true; break }
            }
            if due == nil {
                f.dateFormat = "yyyy-MM-dd"
                due = f.date(from: String(normalized.prefix(10)))
            }
        }
        return TodoExtraction(title: String(title.prefix(60)), due: due, hasTime: hasTime)
    }
}
