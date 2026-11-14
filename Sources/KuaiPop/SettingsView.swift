import AppKit
import ServiceManagement
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, appearance, translate, polish, todo, ai, access
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return L("一般とショートカット")
        case .appearance: return L("表示と言語")
        case .translate: return L("翻訳")
        case .polish: return L("推敲")
        case .todo: return "ToDo"
        case .ai: return L("AI モデル")
        case .access: return L("アクセス権")
        }
    }
}

@MainActor
final class SettingsNav: ObservableObject {
    @Published var page: SettingsPage = .general
}

struct SettingsView: View {
    @ObservedObject var nav: SettingsNav
    let store: TodoStore
    @AppStorage(PrefKey.uiLanguage) private var uiLanguage = AppLanguage.system.rawValue
    @AppStorage(PrefKey.theme) private var theme = ThemePalette.blue.rawValue

    var body: some View {
        content
            // Rebuild everything when the language or theme changes.
            .id("\(uiLanguage)-\(theme)")
    }

    private var content: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPage.allCases) { p in
                    Button {
                        nav.page = p
                    } label: {
                        Text(p.title)
                            .font(.system(size: 13, weight: nav.page == p ? .semibold : .regular))
                            .foregroundStyle(nav.page == p ? Theme.accentStrong : Theme.textSub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(nav.page == p ? Theme.navSelected : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(width: 180)
            .background(Theme.sidebar)

            Rectangle().fill(Theme.border).frame(width: 1)

            ScrollView {
                Group {
                    switch nav.page {
                    case .general: GeneralPage()
                    case .appearance: AppearancePage()
                    case .translate: TranslatePage()
                    case .polish: PolishPage()
                    case .todo: TodoPage(store: store)
                    case .ai: AIPage()
                    case .access: AccessPage()
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.text)
        .frame(width: 760, height: 580)
        .background(Theme.surface)
    }
}

// MARK: - Shared pieces

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold))
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct RadioRow: View {
    let title: String
    var subtitle: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Theme.accent : Theme.secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle { Hint(subtitle) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct LabeledInput<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .semibold))
            content
        }
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .frame(minWidth: 96, minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.footer))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.border, lineWidth: 1))
    }
}

struct StatusBanner: View {
    let ok: Bool
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark" : "exclamationmark.triangle")
                .font(.system(size: 13, weight: .bold))
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.link).font(.system(size: 12))
            }
        }
        .foregroundStyle(ok ? Theme.okText : Theme.warnText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(ok ? Theme.okBg : Theme.warnBg))
    }
}

// MARK: - 一般とショートカット

struct GeneralPage: View {
    @AppStorage(PrefKey.triggerMode) private var trigger = TriggerMode.auto.rawValue
    @AppStorage(PrefKey.clipboardFallback) private var clipboardFallback = true
    @AppStorage(PrefKey.doubleCopy) private var doubleCopy = true
    @AppStorage(PrefKey.excludedApps) private var excluded = Prefs.defaultExcluded
    @AppStorage(PrefKey.searchMode) private var searchMode = SearchMode.teams.rawValue
    @AppStorage(PrefKey.searchURL) private var searchURL = Prefs.defaultSearchURL
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = AX.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(L("テキスト選択後のバーの出し方"))
                RadioRow(title: L("選択すると自動でバーを表示（おすすめ）"), subtitle: L("選択を外すか Esc で消える"),
                         selected: trigger == TriggerMode.auto.rawValue) { trigger = TriggerMode.auto.rawValue }
                RadioRow(title: L("ショートカット（⌥Space）を押したときだけ表示"), subtitle: L("自動表示が邪魔なアプリ向け"),
                         selected: trigger == TriggerMode.hotkey.rawValue) { trigger = TriggerMode.hotkey.rawValue }
                RadioRow(title: L("右クリックメニューの「サービス」からのみ"),
                         selected: trigger == TriggerMode.services.rawValue) { trigger = TriggerMode.services.rawValue }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(L("⌘C を 2 回押してもバーを表示"), isOn: $doubleCopy)
                    .padding(.top, 4)
                Hint(L("テキストを選んで ⌘C をすばやく 2 回押すと、マウスの位置にバーを表示します。アクセシビリティの権限がなくても使えます。"))
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L("ショートカット"))
                VStack(spacing: 0) {
                    shortcutRow(L("フローティングバーを表示"), "⌥ Space")
                    Divider()
                    shortcutRow(L("すぐに翻訳"), "⌥ 1")
                    Divider()
                    shortcutRow(L("すぐに推敲して置き換え"), "⌥ 2")
                    Divider()
                    shortcutRow(L("すぐに ToDo に追加"), "⌥ 3")
                }
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                Hint(L("「サービスからのみ」を選ぶとショートカットも無効になります。"))
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L("選択テキストの取得"))
                Toggle(L("アクセシビリティで取得できないアプリでは ⌘C で取得する"), isOn: $clipboardFallback)
                Hint(L("取得後すぐにクリップボードを元に戻します。"))
                Text(L("自動表示しないアプリ（バンドル ID、1 行に 1 つ）")).font(.system(size: 12, weight: .semibold)).padding(.top, 6)
                TextEditor(text: $excluded)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                Menu(L("実行中のアプリから追加")) {
                    ForEach(runningApps, id: \.0) { app in
                        Button(app.1) { addExcluded(app.0) }
                    }
                }
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L("検索ボタン"))
                Hint(L("Teams で選んだテキストは Teams で、WeChat で選んだテキストは WeChat で検索します。それ以外は Chrome で Google 検索します（Chrome がなければ既定のブラウザ）。"))
                Text(L("Web 検索の URL（{q} が選択テキストに置き換わります）")).font(.system(size: 12, weight: .semibold)).padding(.top, 4)
                TextField("https://www.google.com/search?q={q}", text: $searchURL)
                    .textFieldStyle(.roundedBorder)
                Hint(L("アクセシビリティの権限がない場合（会社の Mac など）は、Teams・WeChat を前面に出してキーワードをクリップボードにコピーするだけです。続けて ⌘E（WeChat は ⌘F）→ ⌘V で検索してください。"))
            }

            Toggle(L("ログイン時に起動"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { value in
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            StatusBanner(
                ok: trusted,
                text: trusted
                    ? L("「アクセシビリティ」の権限あり。他のアプリで選択したテキストを読み取り・置き換えできます")
                    : L("「アクセシビリティ」の権限がありません。⌘C を 2 回押すとバーを表示できます"),
                actionTitle: L("システム設定…"),
                action: { AX.openSystemSettings() })
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            trusted = AX.isTrusted
        }
    }

    private func shortcutRow(_ title: String, _ key: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            KeyCap(text: key)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var runningApps: [(String, String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in
                guard let id = app.bundleIdentifier else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.1 < $1.1 }
    }

    private func addExcluded(_ id: String) {
        var lines = excluded.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.contains(id) else { return }
        lines.append(id)
        excluded = lines.joined(separator: "\n")
    }
}

// MARK: - 表示と言語

struct AppearancePage: View {
    @AppStorage(PrefKey.uiLanguage) private var uiLanguage = AppLanguage.system.rawValue
    @AppStorage(PrefKey.theme) private var theme = ThemePalette.blue.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            LabeledInput(label: L("表示言語")) {
                Picker("", selection: $uiLanguage) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 420)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(L("テーマカラー"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(ThemePalette.allCases) { p in
                        ThemeSwatch(palette: p, selected: theme == p.rawValue) { theme = p.rawValue }
                    }
                }
                Hint(L("ライト / ダークはシステムの設定に合わせて自動で切り替わります。"))
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L("プレビュー"))
                HStack(alignment: .top, spacing: 16) {
                    BarView { _ in }
                        .allowsHitTesting(false)
                        .padding(-OverlayMetrics.pad)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "translate").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                            Text("中").font(.system(size: 11, weight: .bold))
                                .frame(minWidth: 22, minHeight: 18)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accent))
                                .foregroundStyle(Theme.onAccent)
                            Text("日").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            Text("EN").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        Text(L("これは翻訳結果の表示例です。")).font(.system(size: 13)).foregroundStyle(Theme.resultText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.resultBg))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.18), lineWidth: 1))
                }
            }
        }
    }
}

struct ThemeSwatch: View {
    let palette: ThemePalette
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(palette.swatch).frame(width: 20, height: 20)
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                Text(palette.title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.navSelected : Theme.footer))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(palette.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - 翻訳

struct TranslatePage: View {
    @AppStorage(PrefKey.translateTarget) private var target = "简体中文"
    @AppStorage(PrefKey.translateFallback) private var fallback = "日本語"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LabeledInput(label: L("翻訳先の言語（日本語・英語などの原文はこの言語に翻訳）")) {
                Picker("", selection: $target) {
                    ForEach(Prefs.languages, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 220)
            }
            LabeledInput(label: L("原文がすでに翻訳先の言語のとき")) {
                Picker("", selection: $fallback) {
                    ForEach(Prefs.languages, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 220)
                Hint(L("例：翻訳先が中国語のとき、日本語・英語の文章は中国語に、中国語の文章は日本語に翻訳します。"))
            }
            Hint(L("翻訳結果は原文のすぐ下に表示されます。結果の右側の「中 / 日 / EN」を押すと、その言語に翻訳し直します。"))
        }
    }
}

// MARK: - 推敲

struct PolishPage: View {
    @AppStorage(PrefKey.polishTone) private var tone = PolishTone.internalTone.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(L("推敲のデフォルト語調"))
            ForEach(PolishTone.allCases) { t in
                RadioRow(title: t.label, selected: tone == t.rawValue) { tone = t.rawValue }
            }
            Hint(L("推敲結果は原文の下に表示されます。入力欄の文章なら「置き換え」で差し替えられます。⌥2 を押すと推敲してすぐに置き換えます。"))
                .padding(.top, 8)
        }
    }
}

// MARK: - ToDo

struct TodoPage: View {
    @ObservedObject var store: TodoStore
    @AppStorage(PrefKey.todoDestination) private var destination = TodoDestination.app.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LabeledInput(label: L("ToDo の保存先")) {
                Picker("", selection: $destination) {
                    ForEach(TodoDestination.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .labelsHidden()
                .frame(width: 360)
                Hint(L("「リマインダー」を選ぶと、初回にアクセス許可を求めます。期限は AI が原文から読み取ります。"))
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L("データ"))
                Hint(L("未完了 %d 件 / 全 %d 件", store.openCount, store.items.count))
                HStack(spacing: 12) {
                    Button(L("Finder で表示")) { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL]) }
                    Button(L("完了済みを削除")) { store.clearCompleted() }
                }
            }
            Hint(L("ToDo に追加しても通知やトーストは出ません。メニューバーのリストのアイコンを押したときだけ ToDo ウインドウを開きます。ブラウザで選択した内容には出典としてページタイトルと URL を記録します。"))
        }
    }
}

// MARK: - AI モデル

struct AIPage: View {
    @AppStorage(PrefKey.aiProvider) private var provider = AIProvider.apple.rawValue
    @AppStorage(PrefKey.azureEndpoint) private var azureEndpoint = ""
    @AppStorage(PrefKey.azureDeployment) private var azureDeployment = ""
    @AppStorage(PrefKey.azureAPIVersion) private var azureAPIVersion = Prefs.defaultAzureAPIVersion
    @AppStorage(PrefKey.deepseekBaseURL) private var deepseekBase = Prefs.defaultDeepSeekBase
    @AppStorage(PrefKey.deepseekModel) private var deepseekModel = Prefs.defaultDeepSeekModel
    @AppStorage(PrefKey.localBaseURL) private var localBase = Prefs.defaultLocalBase
    @AppStorage(PrefKey.localModel) private var localModel = ""
    @AppStorage(PrefKey.openaiBaseURL) private var openaiBase = Prefs.defaultOpenAIBase
    @AppStorage(PrefKey.openaiModel) private var openaiModel = ""

    @State private var keys: [String: String] = Dictionary(
        uniqueKeysWithValues: AIProvider.allCases.map { ($0.keychainAccount, Keychain.get($0.keychainAccount)) })
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?
    @State private var localModels: [String] = []

    private var current: AIProvider {
        BuildVariant.localOnly ? .apple : (AIProvider(rawValue: provider) ?? .apple)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L("プロバイダー"))
                ForEach(AIProvider.available) { p in
                    RadioRow(title: p.label, selected: current == p) {
                        provider = p.rawValue
                        testResult = nil
                    }
                }
            }

            Divider()

            switch current {
            case .azure: azureFields
            case .deepseek: deepseekFields
            case .apple: appleFields
            case .local: localFields
            case .openai: openaiFields
            }

            HStack(spacing: 12) {
                Button(testing ? L("テスト中…") : L("接続テスト")) { runTest() }
                    .disabled(testing)
                if let r = testResult {
                    Text(r.text)
                        .font(.system(size: 12))
                        .foregroundStyle(r.ok ? Theme.okText : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func keyField(_ p: AIProvider, placeholder: String = L("API キー")) -> some View {
        LabeledInput(label: L("API キー")) {
            SecureField(placeholder, text: Binding(
                get: { keys[p.keychainAccount] ?? "" },
                set: { v in
                    keys[p.keychainAccount] = v
                    Keychain.set(v, for: p.keychainAccount)
                }))
            .textFieldStyle(.roundedBorder)
            Hint(L("キーはキーチェーンに保存されます。"))
        }
    }

    private var azureFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledInput(label: L("エンドポイント")) {
                TextField(L("https://<リソース名>.openai.azure.com"), text: $azureEndpoint)
                    .textFieldStyle(.roundedBorder)
                Hint(L("Azure ポータル › Azure OpenAI リソース › 「キーとエンドポイント」。…/chat/completions?api-version=… の完全な URL を貼り付けても構いません。"))
            }
            HStack(alignment: .top, spacing: 16) {
                LabeledInput(label: L("デプロイ名")) {
                    TextField(L("gpt-4o-mini など"), text: $azureDeployment).textFieldStyle(.roundedBorder)
                }
                LabeledInput(label: L("API バージョン")) {
                    TextField(Prefs.defaultAzureAPIVersion, text: $azureAPIVersion).textFieldStyle(.roundedBorder)
                }
                .frame(width: 180)
            }
            keyField(.azure)
        }
    }

    private var deepseekFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                LabeledInput(label: L("ベース URL")) {
                    TextField(Prefs.defaultDeepSeekBase, text: $deepseekBase).textFieldStyle(.roundedBorder)
                }
                LabeledInput(label: L("モデル")) {
                    Picker("", selection: $deepseekModel) {
                        Text(L("deepseek-chat（速い・おすすめ）")).tag("deepseek-chat")
                        Text(L("deepseek-reasoner（推論）")).tag("deepseek-reasoner")
                    }
                    .labelsHidden()
                }
                .frame(width: 240)
            }
            keyField(.deepseek, placeholder: "sk-…")
            Hint(L("API キーは platform.deepseek.com で発行できます。"))
        }
    }

    private var appleFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusBanner(ok: AppleOnDevice.isAvailable, text: AppleOnDevice.statusText)
            Hint(L("Apple Intelligence のオンデバイスモデル（Foundation Models）を使います。API キー不要・オフラインで動作し、テキストは Mac の外に送信されません。macOS 26 以降と Apple Intelligence 対応 Mac が必要です。長文や専門的な翻訳は大きなモデルより精度が落ちることがあります。"))
        }
    }

    private var localFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledInput(label: L("サーバー URL")) {
                TextField(Prefs.defaultLocalBase, text: $localBase).textFieldStyle(.roundedBorder)
                Hint("Ollama: http://localhost:11434/v1　LM Studio: http://localhost:1234/v1")
            }
            LabeledInput(label: L("モデル")) {
                HStack {
                    TextField(L("qwen3:32b など"), text: $localModel).textFieldStyle(.roundedBorder)
                    if !localModels.isEmpty {
                        Menu(L("選択")) {
                            ForEach(localModels, id: \.self) { m in Button(m) { localModel = m } }
                        }
                        .fixedSize()
                    }
                    Button(L("モデル一覧を取得")) { fetchLocalModels() }
                }
            }
            Hint(L("Mac 上で動くローカルモデルを使います。データは Mac の外に送信されません。推論モデルの <think> 部分は自動で取り除きます。"))
        }
    }

    private var openaiFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                LabeledInput(label: L("ベース URL")) {
                    TextField(Prefs.defaultOpenAIBase, text: $openaiBase).textFieldStyle(.roundedBorder)
                }
                LabeledInput(label: L("モデル")) {
                    TextField(L("gpt-4o-mini など"), text: $openaiModel).textFieldStyle(.roundedBorder)
                }
                .frame(width: 220)
            }
            keyField(.openai)
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        Task { @MainActor in
            do {
                let r = try await AIClient.chat(system: "Reply with the single word OK.", user: "ping")
                testResult = (true, L("接続 OK（応答: %@）", String(r.prefix(40))))
            } catch {
                testResult = (false, error.localizedDescription)
            }
            testing = false
        }
    }

    private func fetchLocalModels() {
        var base = localBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/models") else { return }
        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let list = (obj?["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
                localModels = list.sorted()
                testResult = list.isEmpty ? (false, L("モデルが見つかりません")) : nil
            } catch {
                testResult = (false, L("サーバーに接続できません: %@", error.localizedDescription))
            }
        }
    }
}

// MARK: - アクセス権

struct AccessPage: View {
    @State private var trusted = AX.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L("アクセシビリティ（必須）"))
                StatusBanner(ok: trusted,
                             text: trusted ? L("許可されています") : L("未許可です。「システム設定 › プライバシーとセキュリティ › アクセシビリティ」で KuaiPop をオンにしてください"),
                             actionTitle: L("システム設定を開く"),
                             action: { AX.openSystemSettings() })
                if !trusted {
                    Button(L("許可を求める")) { AX.prompt() }
                    Hint(L("権限がなくても、テキストを選んで ⌘C を 2 回押せばバーを表示できます（会社の Mac など）。その場合、バーはマウスの位置に表示され、「置き換え」の代わりに「コピー」を使います。"))
                }
                Hint(L("選択テキストと位置の取得、Esc の検知、置き換え（⌘V の送信）に使います。アプリを再ビルドした場合は、一覧から KuaiPop を削除して追加し直してください。"))
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L("オートメーション（任意）"))
                Hint(L("ブラウザで選択した内容を ToDo にするとき、Safari / Chrome / Edge / Arc などにページのタイトルと URL を問い合わせます。初回に許可を求めます。"))
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L("リマインダー（任意）"))
                Hint(L("ToDo の保存先に「リマインダー」を選んだときだけ使います。"))
            }
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            trusted = AX.isTrusted
        }
    }
}
