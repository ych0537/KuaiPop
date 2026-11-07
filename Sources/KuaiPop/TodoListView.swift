import AppKit
import SwiftUI

enum TodoFilter: String, CaseIterable, Identifiable {
    case all, today, chat, web
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return L("すべて")
        case .today: return L("今日")
        case .chat: return L("チャットから")
        case .web: return L("Web から")
        }
    }
}

enum DueGroup: Int, CaseIterable, Identifiable {
    case overdue, today, thisWeek, later, none
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .overdue: return L("期限切れ")
        case .today: return L("今日")
        case .thisWeek: return L("今週")
        case .later: return L("それ以降")
        case .none: return L("期限なし")
        }
    }

    static func of(_ item: TodoItem, now: Date = Date()) -> DueGroup {
        guard let due = item.due else { return .none }
        let cal = Calendar.current
        if cal.isDateInToday(due) { return .today }
        let startToday = cal.startOfDay(for: now)
        if due < startToday { return .overdue }
        if let limit = cal.date(byAdding: .day, value: 8, to: startToday), due < limit { return .thisWeek }
        return .later
    }
}

enum DueFormat {
    static func label(_ item: TodoItem) -> String {
        guard let due = item.due else { return L("期限なし") }
        let lang = AppLanguage.current
        let cal = Calendar.current
        let time = DateFormatter()
        time.locale = Locale(identifier: lang.localeIdentifier)
        time.dateFormat = "H:mm"
        let t = item.dueHasTime ? " " + time.string(from: due) : ""
        if cal.isDateInToday(due) { return L("今日") + t }
        if cal.isDateInTomorrow(due) { return L("明日") + t }
        let f = DateFormatter()
        f.locale = Locale(identifier: lang.localeIdentifier)
        switch lang {
        case .en: f.dateFormat = "MMM d (EEE)"
        case .zh: f.dateFormat = "M月d日（EEE）"
        default: f.dateFormat = "M月d日（E）"
        }
        return f.string(from: due) + t
    }
}

struct TodoListView: View {
    @ObservedObject var store: TodoStore
    var openSettings: () -> Void
    var openSource: (TodoItem) -> Void

    @AppStorage(PrefKey.uiLanguage) private var uiLanguage = AppLanguage.system.rawValue
    @AppStorage(PrefKey.theme) private var theme = ThemePalette.blue.rawValue
    @State private var filter: TodoFilter = .all
    @State private var expanded: UUID?
    @State private var showDone = false

    private var filtered: [TodoItem] {
        store.items.filter { item in
            switch filter {
            case .all: return true
            case .today:
                let g = DueGroup.of(item)
                return g == .today || g == .overdue
            case .chat: return item.kind == .chat
            case .web: return item.kind == .web
            }
        }
    }

    private var open: [TodoItem] { filtered.filter { !$0.done } }
    private var done: [TodoItem] {
        filtered.filter { $0.done }.sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            chips
            Rectangle().fill(Theme.divider).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if open.isEmpty && done.isEmpty {
                        emptyState
                    }
                    ForEach(DueGroup.allCases) { group in
                        let rows = open.filter { DueGroup.of($0) == group }.sorted(by: sortRule)
                        if !rows.isEmpty {
                            Text(group.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(group == .overdue ? Theme.todayDue : Theme.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                            ForEach(rows) { row($0) }
                        }
                    }
                    if !done.isEmpty {
                        HStack {
                            Button {
                                showDone.toggle()
                            } label: {
                                Text((showDone ? "⌄ " : "› ") + L("完了済み %d 件", done.count))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.secondary)
                                    .frame(height: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            if showDone {
                                Button(L("完了済みを削除")) { store.clearCompleted() }
                                    .buttonStyle(.link)
                                    .font(.system(size: 12))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        if showDone {
                            ForEach(done) { row($0) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            Rectangle().fill(Theme.divider).frame(height: 1)
            footer
        }
        .frame(width: 376, height: 560)
        .background(Theme.surface)
        .id("\(uiLanguage)-\(theme)")
    }

    private func sortRule(_ a: TodoItem, _ b: TodoItem) -> Bool {
        switch (a.due, b.due) {
        case let (x?, y?) where x != y: return x < y
        default: return a.createdAt > b.createdAt
        }
    }

    private func row(_ item: TodoItem) -> some View {
        TodoRow(
            item: item,
            expanded: expanded == item.id,
            onToggle: { store.toggle(item.id) },
            onTap: { expanded = expanded == item.id ? nil : item.id },
            onOpenSource: { openSource(item) },
            onDelete: { store.delete(item.id) })
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("ToDo").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            Text(L("未完了 %d 件", store.openCount)).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondary)
            .help(L("設定"))
            .accessibilityLabel(L("設定"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var chips: some View {
        HStack(spacing: 4) {
            ForEach(TodoFilter.allCases) { f in
                Button {
                    filter = f
                } label: {
                    Text(f.title)
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(filter == f ? Theme.chipSelected : Theme.chip))
                        .foregroundStyle(filter == f ? Theme.chipSelectedText : Theme.textSub)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist").font(.system(size: 28)).foregroundStyle(Theme.secondary)
            Text(L("ToDo はありません")).font(.system(size: 13)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var footer: some View {
        HStack {
            Text(L("どのアプリでも、テキストを選択するとバーが表示されます"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.footer)
    }
}

struct TodoRow: View {
    let item: TodoItem
    let expanded: Bool
    let onToggle: () -> Void
    let onTap: () -> Void
    let onOpenSource: () -> Void
    let onDelete: () -> Void

    @State private var translation: String?
    @State private var translating = false

    private var isToday: Bool {
        let g = DueGroup.of(item)
        return g == .today || g == .overdue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { item.done }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(L("完了：%@", item.title))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 14))
                        .strikethrough(item.done)
                        .foregroundStyle(item.done ? Theme.secondary : Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.pending {
                        ProgressView().controlSize(.mini)
                    }
                }
                meta
                if expanded { detail }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(expanded ? Theme.resultBg : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(L("原文をコピー")) { ClipboardBridge.setString(item.sourceText) }
            Button(L("元のメッセージへ"), action: onOpenSource)
            Divider()
            Button(L("削除"), action: onDelete)
        }
    }

    private var meta: some View {
        HStack(spacing: 8) {
            if item.due != nil {
                Text(DueFormat.label(item))
                    .fontWeight(isToday ? .semibold : .regular)
                    .foregroundStyle(isToday ? Theme.todayDue : Theme.accentStrong)
            } else {
                Text(L("期限なし"))
            }
            HStack(spacing: 4) {
                if item.kind == .web {
                    Image(systemName: "globe").font(.system(size: 10))
                }
                Text(item.sourceLabel).lineLimit(1)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.secondary)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("「\(item.sourceText)」")
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(Theme.textSub)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
            if let t = translation {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "translate").font(.system(size: 11)).foregroundStyle(Theme.accent)
                    Text(t).font(.system(size: 12)).foregroundStyle(Theme.resultText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 12) {
                Button(L("元のメッセージへ"), action: onOpenSource)
                Button(translating ? L("翻訳中…") : L("原文を翻訳")) { translate() }
                    .disabled(translating)
                Spacer()
                Button(L("削除"), action: onDelete)
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .padding(.top, 2)
    }

    private func translate() {
        translating = true
        let text = item.sourceText
        Task { @MainActor in
            do {
                translation = try await AIService.translate(text)
            } catch {
                translation = L("翻訳に失敗しました: %@", error.localizedDescription)
            }
            translating = false
        }
    }
}
