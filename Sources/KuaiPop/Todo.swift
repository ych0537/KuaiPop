import AppKit
import Combine
import EventKit

enum SourceKind: String, Codable {
    case chat, web, app

    static let chatApps: Set<String> = [
        "com.microsoft.teams2", "com.microsoft.teams", "com.tinyspeck.slackmacgap",
        "jp.naver.line.mac", "com.apple.MobileSMS", "com.tencent.xinWeChat", "com.hnc.Discord",
        "com.microsoft.Outlook", "com.apple.mail", "us.zoom.xos", "com.chatwork.chatwork",
    ]

    static func classify(_ bundleID: String?) -> SourceKind {
        guard let id = bundleID else { return .app }
        if chatApps.contains(id) { return .chat }
        if BrowserInfo.isBrowser(id) { return .web }
        return .app
    }
}

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var sourceText: String
    var due: Date?
    var dueHasTime = false
    var createdAt = Date()
    var done = false
    var doneAt: Date?
    var kind: SourceKind
    var appName: String?
    var bundleID: String?
    var windowTitle: String?
    var url: String?
    var pageTitle: String?
    /// Deep link to the exact message (e.g. Teams「リンクをコピー」). Long; never shown raw in the UI.
    var messageLink: String?
    var pending = false

    var isTeams: Bool { TeamsLink.bundleIDs.contains(bundleID ?? "") }

    static func fallbackTitle(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? text
        return line.count > 40 ? String(line.prefix(40)) + "…" : line
    }

    static let fixedNames: [String: String] = [
        "com.tencent.xinWeChat": "WeChat",
        "com.microsoft.teams2": "Teams",
        "com.microsoft.teams": "Teams",
    ]

    /// Short app name only: "WeChat", "Teams", "Chrome", "Xcode" …
    var sourceLabel: String {
        // Fixed names for some apps (WeChat shows as「微信」on a Chinese system)
        if let id = bundleID, let fixed = Self.fixedNames[id] { return fixed }
        var name = (appName ?? "").trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            switch kind {
            case .web: return L("ブラウザ")
            case .chat: return L("チャット")
            case .app: return L("アプリ")
            }
        }
        // "Microsoft Teams" → "Teams", "Google Chrome" → "Chrome", "Microsoft Outlook" → "Outlook"
        for prefix in ["Microsoft ", "Google "] where name.hasPrefix(prefix) && name.count > prefix.count {
            name = String(name.dropFirst(prefix.count))
        }
        if name.hasSuffix(" (work or school)") { name = String(name.dropLast(" (work or school)".count)) }
        return name.count > 20 ? String(name.prefix(20)) + "…" : name
    }
}

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("KuaiPop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("todos.json")
        load()
    }

    var openCount: Int { items.filter { !$0.done }.count }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        items = ((try? dec.decode([TodoItem].self, from: data)) ?? []).map {
            var i = $0
            i.pending = false
            return i
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Silent add: no toast, no window. The title/due date are refined by AI in the background.
    func add(from ctx: SelectionContext) {
        let kind = SourceKind.classify(ctx.bundleID)
        let item = TodoItem(
            title: TodoItem.fallbackTitle(ctx.text), sourceText: ctx.text, kind: kind,
            appName: ctx.appName, bundleID: ctx.bundleID, windowTitle: ctx.windowTitle, pending: true)
        items.insert(item, at: 0)
        save()

        let id = item.id
        let text = ctx.text
        let bundleID = ctx.bundleID
        Task { @MainActor in
            var page: BrowserInfo.Page?
            if kind == .web, let bid = bundleID {
                page = await BrowserInfo.fetch(bundleID: bid)
            }
            let ex = await AIService.extractTodo(text)
            self.update(id) { t in
                if let ex {
                    t.title = ex.title
                    t.due = ex.due
                    t.dueHasTime = ex.hasTime
                }
                if let page {
                    t.url = page.url
                    t.pageTitle = page.title
                }
                t.pending = false
            }
            if Prefs.todoDestination == .reminders, let saved = self.items.first(where: { $0.id == id }) {
                await RemindersBridge.shared.add(saved)
            }
        }
    }

    func update(_ id: UUID, _ change: (inout TodoItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        save()
    }

    func setLink(_ id: UUID, _ link: String?) {
        update(id) { $0.messageLink = link }
    }

    /// Called for every clipboard change. If a Teams message link is copied, attach it to the
    /// most recently added ToDo — but only when that ToDo came from Teams and has no link yet.
    /// No time limit; once another ToDo has been added after it, it is never auto-linked again.
    /// (Teams' ⌘C carries no message ID — checked: only `data-teams="true"` and `/v2/` — so
    /// 「リンクをコピー」is the only way to get the exact message.)
    @discardableResult
    func attachCopiedTeamsLink(_ text: String) -> Bool {
        guard let link = TeamsLink.extract(from: text),
              let latest = items.max(by: { $0.createdAt < $1.createdAt }),
              latest.isTeams, latest.messageLink == nil, !latest.done
        else { return false }
        setLink(latest.id, link)
        return true
    }

    func toggle(_ id: UUID) {
        update(id) { t in
            t.done.toggle()
            t.doneAt = t.done ? Date() : nil
        }
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clearCompleted() {
        items.removeAll { $0.done }
        save()
    }
}

// MARK: - Message links (Teams etc.)

enum TeamsLink {
    static let bundleIDs: Set<String> = ["com.microsoft.teams2", "com.microsoft.teams"]
    private static let pattern = try! NSRegularExpression(
        pattern: #"https://teams\.(?:microsoft\.com|cloud\.microsoft)/l/[^\s"'<>]+"#)
    private static let anyURL = try! NSRegularExpression(pattern: #"https?://[^\s"'<>]+"#)

    /// First Teams deep link (https://teams.microsoft.com/l/…) in the text.
    static func extract(from text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = pattern.firstMatch(in: text, range: range), let r = Range(m.range, in: text) else { return nil }
        return String(text[r])
    }

    /// Teams link, or any http(s) URL as a fallback (for pasting a link manually).
    static func extractAnyLink(from text: String) -> String? {
        if let t = extract(from: text) { return t }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = anyURL.firstMatch(in: text, range: range), let r = Range(m.range, in: text) else { return nil }
        return String(text[r])
    }

    static func isTeams(_ link: String) -> Bool { extract(from: link) != nil }

    /// Short label for the UI instead of the very long URL.
    static func label(_ link: String) -> String {
        if isTeams(link) {
            if link.contains("/l/message/") { return L("Teams のメッセージ") }
            return L("Teams のリンク")
        }
        return URL(string: link)?.host ?? L("リンク")
    }

    /// Opens Teams links directly in the desktop app (msteams:), falling back to the browser.
    @MainActor
    static func open(_ link: String) {
        if isTeams(link), let r = link.range(of: "/l/") {
            let app = "msteams:" + link[r.lowerBound...]
            if let u = URL(string: app), NSWorkspace.shared.urlForApplication(toOpen: u) != nil,
               NSWorkspace.shared.open(u) {
                return
            }
        }
        if let u = URL(string: link) { NSWorkspace.shared.open(u) }
    }
}

// MARK: - Browser page info (for "Web から" ToDos)

enum BrowserInfo {
    struct Page {
        let url: String
        let title: String
    }

    static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.microsoft.edgemac",
        "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]
    static let others: Set<String> = ["org.mozilla.firefox"]

    static func isBrowser(_ id: String) -> Bool {
        safari.contains(id) || chromium.contains(id) || others.contains(id)
    }

    /// Asks the browser for the front tab's URL and title (prompts once for Automation permission).
    static func fetch(bundleID: String) async -> Page? {
        let script: String
        if safari.contains(bundleID) {
            script = "tell application id \"\(bundleID)\" to return (URL of current tab of front window) & linefeed & (name of current tab of front window)"
        } else if chromium.contains(bundleID) {
            script = "tell application id \"\(bundleID)\" to return (URL of active tab of front window) & linefeed & (title of active tab of front window)"
        } else {
            return nil
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<Page?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", script]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = Pipe()
                do { try p.run() } catch {
                    cont.resume(returning: nil)
                    return
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                guard p.terminationStatus == 0,
                      let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                else {
                    cont.resume(returning: nil)
                    return
                }
                let lines = s.components(separatedBy: "\n")
                guard let u = lines.first, !u.isEmpty else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: Page(url: u, title: lines.dropFirst().joined(separator: " ")))
            }
        }
    }
}

// MARK: - macOS Reminders

@MainActor
final class RemindersBridge {
    static let shared = RemindersBridge()
    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                store.requestAccess(to: .reminder) { granted, _ in cont.resume(returning: granted) }
            }
        }
    }

    func add(_ item: TodoItem) async {
        guard await requestAccess() else { return }
        let r = EKReminder(eventStore: store)
        r.title = item.title
        var notes = item.sourceText
        if let u = item.url { notes += "\n\n\(u)" }
        r.notes = notes
        r.calendar = store.defaultCalendarForNewReminders()
        if let due = item.due {
            let comps: Set<Calendar.Component> = item.dueHasTime
                ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            r.dueDateComponents = Calendar.current.dateComponents(comps, from: due)
        }
        try? store.save(r, commit: true)
    }
}
