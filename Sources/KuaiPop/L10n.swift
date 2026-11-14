import Foundation

/// UI language. Strings in the source are written in Japanese and used as lookup keys.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ja, zh, en
    var id: String { rawValue }

    /// Shown in the picker in its own language.
    var label: String {
        switch self {
        case .system: return L("システムに合わせる")
        case .ja: return "日本語"
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }

    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: PrefKey.uiLanguage) ?? ""
        let chosen = AppLanguage(rawValue: raw) ?? .system
        guard chosen == .system else { return chosen }
        let first = Locale.preferredLanguages.first?.lowercased() ?? "ja"
        if first.hasPrefix("zh") { return .zh }
        if first.hasPrefix("ja") { return .ja }
        return .en
    }

    var localeIdentifier: String {
        switch self {
        case .zh: return "zh_CN"
        case .en: return "en_US"
        default: return "ja_JP"
        }
    }
}

/// Localized string for a Japanese source string. Unknown keys fall back to Japanese.
func L(_ ja: String) -> String {
    let lang = AppLanguage.current
    guard lang != .ja, let entry = Strings.table[ja] else { return ja }
    return lang == .zh ? entry.zh : entry.en
}

/// Localized format string (`%@`, `%d`) with arguments.
func L(_ ja: String, _ args: CVarArg...) -> String {
    String(format: L(ja), arguments: args)
}

enum Strings {
    // swiftlint:disable line_length
    static let table: [String: (zh: String, en: String)] = [
        // MARK: General / menu
        "システムに合わせる": ("跟随系统", "Match System"),
        "選択アシスト（KuaiPop）": ("选择助手（KuaiPop）", "Selection Assistant (KuaiPop)"),
        "選択アシスト 設定": ("选择助手 设置", "Selection Assistant Settings"),
        "ToDo リスト": ("ToDo 列表", "ToDo List"),
        "設定…": ("设置…", "Settings…"),
        "KuaiPop を終了": ("退出 KuaiPop", "Quit KuaiPop"),

        // MARK: Floating bar / result
        "選択したキーワードを Teams で検索": ("在 Teams 中搜索所选关键词", "Search selection in Teams"),
        "選択したキーワードを Web で検索": ("在网页中搜索所选关键词", "Search selection on the web"),
        "翻訳（日本語・英語 → %@）": ("翻译（日语・英语 → %@）", "Translate (Japanese/English → %@)"),
        "ビジネス日本語に推敲": ("润色为商务日语", "Polish into business Japanese"),
        "ToDo に追加": ("加入 ToDo", "Add to ToDo"),
        "ToDo リストを開く": ("打开 ToDo 列表", "Open ToDo list"),
        "設定": ("设置", "Settings"),
        "このままでビジネス日本語として適切です": ("原文已是得体的商务日语，无需修改", "Already appropriate business Japanese"),
        "推敲": ("润色", "Polish"),
        "置き換え": ("替换", "Replace"),
        "コピー": ("复制", "Copy"),
        "閉じる": ("关闭", "Close"),
        "翻訳中…": ("翻译中…", "Translating…"),
        "推敲中…": ("润色中…", "Polishing…"),
        "%@に翻訳": ("翻译成%@", "Translate into %@"),

        // MARK: Prefs labels
        "Mac 本体の AI（Apple Intelligence・オンデバイス）・デフォルト": ("Mac 本机 AI（Apple Intelligence・端侧）・默认", "On-device Mac AI (Apple Intelligence) · Default"),
        "Mac のローカルモデル（Ollama / LM Studio）": ("Mac 本地模型（Ollama / LM Studio）", "Local model on this Mac (Ollama / LM Studio)"),
        "OpenAI / その他の OpenAI 互換 API": ("OpenAI / 其他 OpenAI 兼容 API", "OpenAI / other OpenAI-compatible API"),
        "社外（尊敬語・謙譲語）": ("对外（尊敬语・谦让语）", "External (honorific)"),
        "社内（丁寧語）・デフォルト": ("对内（礼貌语）・默认", "Internal (polite) · Default"),
        "簡潔（チャット向け）": ("简洁（聊天用）", "Concise (for chat)"),
        "アプリ内のリスト": ("应用内列表", "In-app list"),
        "アプリ内のリスト ＋ macOS「リマインダー」": ("应用内列表 ＋ macOS「提醒事项」", "In-app list + macOS Reminders"),

        // MARK: Settings pages
        "一般とショートカット": ("通用与快捷键", "General & Shortcuts"),
        "表示と言語": ("外观与语言", "Appearance & Language"),
        "翻訳": ("翻译", "Translation"),
        "AI モデル": ("AI 模型", "AI Model"),
        "アクセス権": ("权限", "Permissions"),

        // MARK: Appearance
        "表示言語": ("界面语言", "Interface language"),
        "テーマカラー": ("主题颜色", "Theme color"),
        "ライト / ダークはシステムの設定に合わせて自動で切り替わります。": ("浅色 / 深色会跟随系统设置自动切换。", "Light / dark follows the system setting."),
        "モノクロ": ("黑白", "Mono"),
        "ライトブルー": ("浅蓝", "Light Blue"),
        "ライトグリーン": ("浅绿", "Light Green"),
        "ラベンダー": ("薰衣草紫", "Lavender"),
        "さくら": ("樱花粉", "Sakura"),
        "オレンジ": ("暖橙", "Orange"),
        "プレビュー": ("预览", "Preview"),
        "これは翻訳結果の表示例です。": ("这是翻译结果的显示示例。", "This is how a translation result looks."),

        // MARK: General page
        "テキスト選択後のバーの出し方": ("选中文字后图标条的出现方式", "How the bar appears after selecting text"),
        "選択すると自動でバーを表示（おすすめ）": ("选中后自动显示图标条（推荐）", "Show the bar automatically on selection (recommended)"),
        "選択を外すか Esc で消える": ("取消选择或按 Esc 即消失", "Disappears when you deselect or press Esc"),
        "ショートカット（⌥Space）を押したときだけ表示": ("仅在按下快捷键（⌥Space）时显示", "Show only when pressing the shortcut (⌥Space)"),
        "自動表示が邪魔なアプリ向け": ("适合自动弹出会打扰的场景", "For when automatic popups get in the way"),
        "右クリックメニューの「サービス」からのみ": ("仅通过右键菜单「服务」", "Only from the right-click Services menu"),
        "⌘C を 2 回押してもバーを表示": ("连按两次 ⌘C 也显示图标条", "Also show the bar when ⌘C is pressed twice"),
        "テキストを選んで ⌘C をすばやく 2 回押すと、マウスの位置にバーを表示します。アクセシビリティの権限がなくても使えます。": ("选中文字后快速按两次 ⌘C，会在鼠标位置显示图标条。没有辅助功能权限也能使用。", "Select text and quickly press ⌘C twice to show the bar at the mouse. Works without the Accessibility permission."),
        "ショートカット": ("快捷键", "Shortcuts"),
        "フローティングバーを表示": ("显示浮动图标条", "Show floating bar"),
        "すぐに翻訳": ("直接翻译", "Translate immediately"),
        "すぐに推敲して置き換え": ("直接润色并替换", "Polish and replace immediately"),
        "すぐに ToDo に追加": ("直接加入 ToDo", "Add to ToDo immediately"),
        "「サービスからのみ」を選ぶとショートカットも無効になります。": ("选择「仅通过服务」时快捷键也会停用。", "Choosing “Services only” also disables the shortcuts."),
        "選択テキストの取得": ("获取选中文字", "Reading the selection"),
        "アクセシビリティで取得できないアプリでは ⌘C で取得する": ("无法通过辅助功能获取时，用 ⌘C 获取", "Use ⌘C in apps that don’t expose the selection via Accessibility"),
        "取得後すぐにクリップボードを元に戻します。": ("获取后会立即还原剪贴板。", "The clipboard is restored right after."),
        "自動表示しないアプリ（バンドル ID、1 行に 1 つ）": ("不自动显示的应用（Bundle ID，每行一个）", "Apps without automatic bar (bundle IDs, one per line)"),
        "実行中のアプリから追加": ("从正在运行的应用中添加", "Add from running apps"),
        "検索ボタン": ("搜索按钮", "Search button"),
        "Microsoft Teams で検索": ("在 Microsoft Teams 中搜索", "Search in Microsoft Teams"),
        "Web（URL テンプレート）で検索": ("网页搜索（URL 模板）", "Search the web (URL template)"),
        "Teams がない場合は URL テンプレートで検索します。{q} が選択テキストに置き換わります。": ("未安装 Teams 时使用 URL 模板搜索。{q} 会替换为选中的文字。", "Without Teams, the URL template is used. {q} is replaced with the selection."),
        "ログイン時に起動": ("登录时启动", "Launch at login"),
        "「アクセシビリティ」の権限あり。他のアプリで選択したテキストを読み取り・置き換えできます": ("已获得「辅助功能」权限，可以读取和替换其他应用中选中的文字", "Accessibility permission granted. Selected text in other apps can be read and replaced"),
        "「アクセシビリティ」の権限がありません。選択テキストを読み取れません": ("没有「辅助功能」权限，无法读取选中的文字", "No Accessibility permission. Selected text can’t be read"),
        "「アクセシビリティ」の権限がありません。⌘C を 2 回押すとバーを表示できます": ("没有「辅助功能」权限。可以连按两次 ⌘C 显示图标条", "No Accessibility permission. Press ⌘C twice to show the bar"),
        "システム設定…": ("系统设置…", "System Settings…"),

        // MARK: Translate page
        "翻訳先の言語（日本語・英語などの原文はこの言語に翻訳）": ("翻译目标语言（日语、英语等原文会翻译成此语言）", "Target language (Japanese, English, etc. are translated into this)"),
        "原文がすでに翻訳先の言語のとき": ("原文已经是目标语言时", "When the text is already in the target language"),
        "例：翻訳先が中国語のとき、日本語・英語の文章は中国語に、中国語の文章は日本語に翻訳します。": ("例：目标语言为中文时，日语・英语翻译成中文，中文翻译成日语。", "Example: with Chinese as the target, Japanese/English go to Chinese and Chinese goes to Japanese."),
        "翻訳結果は原文のすぐ下に表示されます。結果の右側の「中 / 日 / EN」を押すと、その言語に翻訳し直します。": ("翻译结果显示在原文正下方。点结果上方的「中 / 日 / EN」可改译成该语言。", "Results appear right under the original. Click 中 / 日 / EN to re-translate into that language."),

        // MARK: Polish page
        "推敲のデフォルト語調": ("润色的默认语气", "Default polishing tone"),
        "推敲結果は原文の下に表示されます。入力欄の文章なら「置き換え」で差し替えられます。⌥2 を押すと推敲してすぐに置き換えます。": ("润色结果显示在原文下方。输入框中的文字可点「替换」直接替换。按 ⌥2 会润色并立即替换。", "Results appear under the original. In text fields, click Replace to swap it in. ⌥2 polishes and replaces immediately."),

        // MARK: ToDo page
        "ToDo の保存先": ("ToDo 保存位置", "Where to save ToDos"),
        "「リマインダー」を選ぶと、初回にアクセス許可を求めます。期限は AI が原文から読み取ります。": ("选择「提醒事项」时，首次会请求访问权限。期限由 AI 从原文中读取。", "Choosing Reminders asks for access the first time. Due dates are read from the text by AI."),
        "データ": ("数据", "Data"),
        "未完了 %d 件 / 全 %d 件": ("未完成 %d 项 / 共 %d 项", "%d open / %d total"),
        "Finder で表示": ("在 Finder 中显示", "Show in Finder"),
        "完了済みを削除": ("删除已完成", "Delete completed"),
        "ToDo に追加しても通知やトーストは出ません。メニューバーのリストのアイコンを押したときだけ ToDo ウインドウを開きます。ブラウザで選択した内容には出典としてページタイトルと URL を記録します。": ("加入 ToDo 时不会弹出任何通知。只有点击菜单栏的列表图标时才打开 ToDo 窗口。从浏览器选中的内容会记录页面标题和 URL 作为出处。", "Adding a ToDo shows no notification. The ToDo window opens only from the menu bar icon. Items from a browser keep the page title and URL as their source."),

        // MARK: AI page
        "プロバイダー": ("提供方", "Provider"),
        "テスト中…": ("测试中…", "Testing…"),
        "接続テスト": ("连接测试", "Test connection"),
        "API キー": ("API 密钥", "API key"),
        "キーはキーチェーンに保存されます。": ("密钥保存在钥匙串中。", "Keys are stored in the Keychain."),
        "エンドポイント": ("终结点（Endpoint）", "Endpoint"),
        "https://<リソース名>.openai.azure.com": ("https://<资源名>.openai.azure.com", "https://<resource>.openai.azure.com"),
        "Azure ポータル › Azure OpenAI リソース › 「キーとエンドポイント」。…/chat/completions?api-version=… の完全な URL を貼り付けても構いません。": ("Azure 门户 › Azure OpenAI 资源 ›「密钥和终结点」。也可以直接粘贴 …/chat/completions?api-version=… 的完整 URL。", "Azure portal › Azure OpenAI resource › Keys and Endpoint. You can also paste the full …/chat/completions?api-version=… URL."),
        "デプロイ名": ("部署名", "Deployment"),
        "gpt-4o-mini など": ("例如 gpt-4o-mini", "e.g. gpt-4o-mini"),
        "API バージョン": ("API 版本", "API version"),
        "ベース URL": ("Base URL", "Base URL"),
        "モデル": ("模型", "Model"),
        "deepseek-chat（速い・おすすめ）": ("deepseek-chat（快・推荐）", "deepseek-chat (fast, recommended)"),
        "deepseek-reasoner（推論）": ("deepseek-reasoner（推理）", "deepseek-reasoner (reasoning)"),
        "API キーは platform.deepseek.com で発行できます。": ("API 密钥可在 platform.deepseek.com 创建。", "Create an API key at platform.deepseek.com."),
        "Apple Intelligence のオンデバイスモデル（Foundation Models）を使います。API キー不要・オフラインで動作し、テキストは Mac の外に送信されません。macOS 26 以降と Apple Intelligence 対応 Mac が必要です。長文や専門的な翻訳は大きなモデルより精度が落ちることがあります。": ("使用 Apple Intelligence 端侧模型（Foundation Models）。无需 API 密钥，可离线运行，文字不会发送到 Mac 之外。需要 macOS 26 及以上且支持 Apple Intelligence 的 Mac。长文或专业翻译的准确度可能不如大型模型。", "Uses the Apple Intelligence on-device model (Foundation Models). No API key, works offline, and text never leaves your Mac. Requires macOS 26+ on an Apple Intelligence Mac. Long or specialized translations may be less accurate than larger models."),
        "サーバー URL": ("服务器 URL", "Server URL"),
        "qwen3:32b など": ("例如 qwen3:32b", "e.g. qwen3:32b"),
        "選択": ("选择", "Choose"),
        "モデル一覧を取得": ("获取模型列表", "Fetch models"),
        "Mac 上で動くローカルモデルを使います。データは Mac の外に送信されません。推論モデルの <think> 部分は自動で取り除きます。": ("使用在本机运行的本地模型，数据不会发送到 Mac 之外。推理模型的 <think> 部分会自动去除。", "Uses a local model running on this Mac. Data never leaves your Mac. <think> blocks from reasoning models are removed automatically."),
        "接続 OK（応答: %@）": ("连接成功（响应：%@）", "Connected (reply: %@)"),
        "モデルが見つかりません": ("未找到模型", "No models found"),
        "サーバーに接続できません: %@": ("无法连接服务器：%@", "Can’t reach the server: %@"),

        // MARK: Access page
        "アクセシビリティ（必須）": ("辅助功能（必需）", "Accessibility (required)"),
        "許可されています": ("已允许", "Allowed"),
        "未許可です。「システム設定 › プライバシーとセキュリティ › アクセシビリティ」で KuaiPop をオンにしてください": ("未允许。请在「系统设置 › 隐私与安全性 › 辅助功能」中打开 KuaiPop", "Not allowed. Turn on KuaiPop in System Settings › Privacy & Security › Accessibility"),
        "システム設定を開く": ("打开系统设置", "Open System Settings"),
        "許可を求める": ("请求权限", "Request access"),
        "選択テキストと位置の取得、Esc の検知、置き換え（⌘V の送信）に使います。アプリを再ビルドした場合は、一覧から KuaiPop を削除して追加し直してください。": ("用于获取选中文字及位置、检测 Esc、替换（发送 ⌘V）。重新编译应用后，请从列表中删除 KuaiPop 再重新添加。", "Used to read the selection and its position, detect Esc, and replace text (sending ⌘V). After rebuilding the app, remove KuaiPop from the list and add it again."),
        "権限がなくても、テキストを選んで ⌘C を 2 回押せばバーを表示できます（会社の Mac など）。その場合、バーはマウスの位置に表示され、「置き換え」の代わりに「コピー」を使います。": ("即使没有权限，选中文字后连按两次 ⌘C 也能显示图标条（例如公司电脑）。此时图标条显示在鼠标位置，用「复制」代替「替换」。", "Even without the permission, select text and press ⌘C twice to show the bar (e.g. on a work Mac). The bar then appears at the mouse, and Copy is used instead of Replace."),
        "オートメーション（任意）": ("自动化（可选）", "Automation (optional)"),
        "ブラウザで選択した内容を ToDo にするとき、Safari / Chrome / Edge / Arc などにページのタイトルと URL を問い合わせます。初回に許可を求めます。": ("把浏览器中选中的内容加入 ToDo 时，会向 Safari / Chrome / Edge / Arc 等获取页面标题和 URL。首次会请求许可。", "When adding a ToDo from a browser, KuaiPop asks Safari / Chrome / Edge / Arc for the page title and URL. You’ll be asked once."),
        "リマインダー（任意）": ("提醒事项（可选）", "Reminders (optional)"),
        "ToDo の保存先に「リマインダー」を選んだときだけ使います。": ("仅在 ToDo 保存位置选择「提醒事项」时使用。", "Used only when Reminders is chosen as the ToDo destination."),

        // MARK: ToDo list
        "すべて": ("全部", "All"),
        "今日": ("今天", "Today"),
        "チャットから": ("来自聊天", "From chat"),
        "Web から": ("来自网页", "From web"),
        "期限切れ": ("已过期", "Overdue"),
        "今週": ("本周", "This week"),
        "それ以降": ("以后", "Later"),
        "期限なし": ("无期限", "No due date"),
        "明日": ("明天", "Tomorrow"),
        "完了済み %d 件": ("已完成 %d 项", "%d completed"),
        "未完了 %d 件": ("未完成 %d 项", "%d open"),
        "ToDo はありません": ("没有 ToDo", "No ToDos"),
        "どのアプリでも、テキストを選択するとバーが表示されます": ("在任何应用中选中文字，都会出现图标条", "Select text in any app to show the bar"),
        "完了：%@": ("完成：%@", "Done: %@"),
        "原文をコピー": ("复制原文", "Copy original"),
        "元のメッセージへ": ("前往原消息", "Go to source"),
        "削除": ("删除", "Delete"),
        "原文を翻訳": ("翻译原文", "Translate original"),
        "翻訳に失敗しました: %@": ("翻译失败：%@", "Translation failed: %@"),
        "Teams のメッセージ": ("Teams 消息", "Teams message"),
        "Teams のリンク": ("Teams 链接", "Teams link"),
        "リンク": ("链接", "Link"),
        "リンクを貼り付け": ("粘贴链接", "Paste link"),
        "リンクを削除": ("删除链接", "Remove link"),
        "クリップボードにリンクがありません": ("剪贴板中没有链接", "No link on the clipboard"),
        "Teams でメッセージを右クリック ›「リンクをコピー」すると、この ToDo に自動で付きます": ("在 Teams 中右键该消息 ›「复制链接」，就会自动附到这条 ToDo", "In Teams, right-click the message › Copy link to attach it here automatically"),
        "選択したキーワードを検索（Teams・WeChat はアプリ内、その他は Google）": ("搜索所选关键词（Teams・WeChat 在应用内搜索，其他用 Google）", "Search the selection (in Teams/WeChat, otherwise Google)"),
        "Teams で選んだテキストは Teams で、WeChat で選んだテキストは WeChat で検索します。それ以外は Chrome で Google 検索します（Chrome がなければ既定のブラウザ）。": ("在 Teams 中选中的文字在 Teams 中搜索，在 WeChat 中选中的在 WeChat 中搜索，其他情况用 Chrome 进行 Google 搜索（没有 Chrome 时用默认浏览器）。", "Text selected in Teams is searched in Teams, in WeChat in WeChat; everything else is searched on Google in Chrome (or the default browser)."),
        "Web 検索の URL（{q} が選択テキストに置き換わります）": ("网页搜索 URL（{q} 会替换为选中的文字）", "Web search URL ({q} is replaced with the selection)"),
        "アクセシビリティの権限がない場合（会社の Mac など）は、Teams・WeChat を前面に出してキーワードをクリップボードにコピーするだけです。続けて ⌘E（WeChat は ⌘F）→ ⌘V で検索してください。": ("没有辅助功能权限时（例如公司电脑），只会把 Teams・WeChat 切到前台，并把关键词复制到剪贴板。接着按 ⌘E（WeChat 为 ⌘F）→ ⌘V 即可搜索。", "Without the Accessibility permission (e.g. on a work Mac), Teams/WeChat is only brought to the front and the keyword is copied. Then press ⌘E (⌘F in WeChat) → ⌘V to search."),
        "ブラウザ": ("浏览器", "Browser"),
        "チャット": ("聊天", "Chat"),
        "アプリ": ("应用", "App"),

        // MARK: AI errors / status
        "利用できます（オンデバイスで処理。データは外部に送信されません）": ("可用（在本机处理，数据不会外传）", "Available (processed on device; nothing is sent out)"),
        "利用できません: %@（Apple Intelligence を「システム設定」でオンにしてください）": ("不可用：%@（请在「系统设置」中开启 Apple Intelligence）", "Unavailable: %@ (turn on Apple Intelligence in System Settings)"),
        "macOS 26 以降が必要です": ("需要 macOS 26 或更高版本", "Requires macOS 26 or later"),
        "このビルドは FoundationModels 非対応の SDK で作成されています（Xcode 26 以降でビルドしてください）": ("此版本是用不支持 FoundationModels 的 SDK 编译的（请用 Xcode 26 及以上编译）", "This build was made with an SDK without FoundationModels (build with Xcode 26 or later)"),
        "空の応答が返されました": ("返回了空响应", "Empty response"),
        "サーバーから応答がありません": ("服务器无响应", "No response from server"),
        "応答を解析できません": ("无法解析响应", "Couldn’t parse the response"),
        "Azure OpenAI のエンドポイントと API キーを設定してください": ("请设置 Azure OpenAI 的终结点和 API 密钥", "Set the Azure OpenAI endpoint and API key"),
        "Azure のデプロイ名を設定してください": ("请设置 Azure 部署名", "Set the Azure deployment name"),
        "DeepSeek の API キーを設定してください": ("请设置 DeepSeek 的 API 密钥", "Set the DeepSeek API key"),
        "ベース URL とモデル名を設定してください": ("请设置 Base URL 和模型名", "Set the base URL and model"),
        "内部エラー": ("内部错误", "Internal error"),
        "URL が不正です": ("URL 无效", "Invalid URL"),
    ]
    // swiftlint:enable line_length
}
