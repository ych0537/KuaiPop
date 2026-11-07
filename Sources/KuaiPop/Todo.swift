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
    var pending = false

    static func fallbackTitle(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? text
        return line.count > 40 ? String(line.prefix(40)) + "…" : line
    }

    /// "チャット · 佐藤 健" / "Web · docs.aws.amazon.com" / "Xcode"
    var sourceLabel: String {
        switch kind {
        case .web:
            if let u = url, let host = URL(string: u)?.host { return "Web · \(host)" }
            return "Web · " + (appName ?? L("ブラウザ"))
        case .chat:
            var name = windowTitle?.trimmingCharacters(in: .whitespaces) ?? ""
            if let app = appName {
                for sep in [" | \(app)", " - \(app)", " — \(app)"] {
                    name = name.replacingOccurrences(of: sep, with: "")
                }
            }
            if name.isEmpty { name = appName ?? "" }
            if name.count > 28 { name = String(name.prefix(28)) + "…" }
            return L("チャット") + " · \(name)"
        case .app:
            return appName ?? L("アプリ")
        }
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
