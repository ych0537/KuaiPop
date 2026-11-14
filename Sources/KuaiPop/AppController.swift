import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Wires everything together: status item, selection monitor, floating bar, results, ToDo, settings.
@MainActor
final class AppController: NSObject {
    let store = TodoStore()
    private let overlay = OverlayController()
    private let monitor = SelectionMonitor()
    private let doubleCopy = DoubleCopyTrigger()
    private let services = ServiceProvider()
    private let settingsNav = SettingsNav()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var lastMode: TriggerMode?
    private var wasTrusted = false
    private var trustTimer: Timer?

    func start() {
        Prefs.register()
        setupStatusItem()
        setupPopover()

        overlay.onAction = { [weak self] action, ctx in self?.handle(action, ctx) }
        monitor.onSelection = { [weak self] ctx in self?.overlay.showBar(for: ctx) }
        monitor.onMouseDown = { [weak self] in self?.overlay.hideAll() }
        monitor.onScroll = { [weak self] in
            guard let self, self.overlay.isShowingAnything else { return }
            self.overlay.hideAll()
        }
        monitor.onKeyDown = { [weak self] code in
            guard let self else { return }
            if code == KeyCode.escape { self.overlay.hideAll() } else { self.overlay.hideBar() }
        }
        monitor.start()

        // ⌘C ×2 → floating bar. Uses only the clipboard, so it works without Accessibility.
        doubleCopy.onTrigger = { [weak self] text in self?.showBarForCopiedText(text) }
        // Teams「リンクをコピー」right after adding a Teams ToDo → attach the message link.
        doubleCopy.onCopy = { [weak self] text in self?.store.attachCopiedTeamsLink(text) }
        doubleCopy.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor in
                if pid != ProcessInfo.processInfo.processIdentifier { self?.overlay.hideAll() }
            }
        }

        services.controller = self
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()

        applyPrefs()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyPrefs() }
        }

        wasTrusted = AX.isTrusted
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkTrust() }
        }

        // Don't nag for Accessibility: without it, ⌘C ×2 and the Services menu still work
        // (e.g. on a company Mac). Show the permissions page only on the very first launch.
        let firstLaunchKey = "didShowWelcome"
        if !AX.isTrusted && !UserDefaults.standard.bool(forKey: firstLaunchKey) {
            UserDefaults.standard.set(true, forKey: firstLaunchKey)
            openSettings(page: .access)
        } else if !AIConfig.isConfigured {
            openSettings(page: .ai)
        }
    }

    // MARK: Permissions & prefs

    private func checkTrust() {
        let now = AX.isTrusted
        if now && !wasTrusted {
            // Global key monitors need re-registering once Accessibility is granted.
            monitor.start()
        }
        wasTrusted = now
    }

    private func applyPrefs() {
        doubleCopy.doubleCopyEnabled = Prefs.doubleCopy
        settingsWindow?.title = L("選択アシスト 設定")
        statusItem?.button?.toolTip = L("選択アシスト（KuaiPop）")
        let mode = Prefs.triggerMode
        guard mode != lastMode else { return }
        lastMode = mode
        let hk = HotKeyCenter.shared
        hk.unregisterAll()
        overlay.hideAll()
        guard mode != .services else { return }
        let opt = optionKey
        hk.register(keyCode: kVK_Space, modifiers: opt) { [weak self] in self?.hotkeyShowBar() }
        hk.register(keyCode: kVK_ANSI_1, modifiers: opt) { [weak self] in self?.hotkeyDirect(.translate) }
        hk.register(keyCode: kVK_ANSI_2, modifiers: opt) { [weak self] in self?.hotkeyDirect(.polish) }
        hk.register(keyCode: kVK_ANSI_3, modifiers: opt) { [weak self] in self?.hotkeyDirect(.addTodo) }
    }

    // MARK: Status item & ToDo popover

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            let img = NSImage(systemSymbolName: "checklist", accessibilityDescription: L("ToDo リストを開く"))
            img?.isTemplate = true
            b.image = img
            b.imagePosition = .imageLeading
            b.target = self
            b.action = #selector(statusClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.toolTip = L("選択アシスト（KuaiPop）")
        }
        store.$items
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateStatusTitle() }
            }
            .store(in: &cancellables)
        updateStatusTitle()
    }

    private func updateStatusTitle() {
        guard let b = statusItem?.button else { return }
        let n = store.openCount
        b.attributedTitle = NSAttributedString(
            string: n > 0 ? " \(n)" : "",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)])
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 376, height: 560)
        let view = TodoListView(
            store: store,
            openSettings: { [weak self] in
                self?.popover.performClose(nil)
                self?.openSettings()
            },
            openSource: { [weak self] item in
                self?.popover.performClose(nil)
                self?.openSource(item)
            })
        popover.contentViewController = NSHostingController(rootView: view)
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            toggleTodoList()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L("ToDo リスト"), action: #selector(menuOpenList), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("設定…"), action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("KuaiPop を終了"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpenList() { showTodoList() }
    @objc private func menuSettings() { openSettings() }

    func toggleTodoList() {
        if popover.isShown { popover.performClose(nil) } else { showTodoList() }
    }

    func showTodoList() {
        guard let b = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
    }

    func openSettings(page: SettingsPage? = nil) {
        if let page { settingsNav.page = page }
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(nav: settingsNav, store: store))
            let w = NSWindow(contentViewController: host)
            w.title = L("選択アシスト 設定")
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 760, height: 580))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func openSource(_ item: TodoItem) {
        if let link = item.messageLink {
            TeamsLink.open(link)
        } else if let u = item.url, let url = URL(string: u) {
            NSWorkspace.shared.open(url)
        } else if let bid = item.bundleID, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Actions

    func handle(_ action: BarAction, _ ctx: SelectionContext) {
        switch action {
        case .search:
            overlay.hideAll()
            Searcher.search(ctx.text, source: ctx.bundleID)
        case .translate:
            runTranslate(ctx)
        case .polish:
            runPolish(ctx, replaceImmediately: false)
        case .addTodo:
            overlay.hideBar()   // silent: no toast, no window
            store.add(from: ctx)
        case .openList:
            overlay.hideAll()
            showTodoList()
        case .settings:
            overlay.hideAll()
            openSettings()
        }
    }

    private func runTranslate(_ ctx: SelectionContext) {
        let model = overlay.showResult(kind: .translate, ctx: ctx)
        model.source = AIService.detectLanguage(ctx.text)
        let text = ctx.text
        model.onSwitchLanguage = { [weak self, weak model] lang in
            guard let self, let model else { return }
            self.startTranslation(model, text: text, to: lang)
        }
        startTranslation(model, text: text, to: AIService.defaultTarget(for: text))
    }

    private func startTranslation(_ model: ResultModel, text: String, to target: String) {
        overlay.resultTask?.cancel()
        model.target = target
        model.copied = false
        model.phase = .loading
        overlay.resultTask = Task { @MainActor in
            do {
                let r = try await AIService.translate(text, to: target)
                guard !Task.isCancelled else { return }
                model.phase = .done(r)
            } catch {
                guard !Task.isCancelled else { return }
                model.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func runPolish(_ ctx: SelectionContext, replaceImmediately: Bool) {
        let model = overlay.showResult(kind: .polish, ctx: ctx)
        model.onReplace = { [weak self] text in self?.replace(ctx, with: text) }
        let text = ctx.text
        overlay.resultTask = Task { @MainActor [weak self] in
            do {
                let r = try await AIService.polish(text)
                guard !Task.isCancelled else { return }
                if let r {
                    if replaceImmediately && ctx.isEditable {
                        self?.replace(ctx, with: r)
                    } else {
                        model.phase = .done(r)
                    }
                } else {
                    model.phase = .noChange
                }
            } catch {
                guard !Task.isCancelled else { return }
                model.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Replaces the selection in the source app by pasting (works in native, web and Electron apps).
    private func replace(_ ctx: SelectionContext, with text: String) {
        overlay.hideAll()
        let app = NSRunningApplication(processIdentifier: ctx.pid)
        Task { @MainActor in
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != ctx.pid {
                app?.activate(options: [])
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            await ClipboardBridge.paste(text)
        }
    }

    // MARK: Hotkeys

    /// Double ⌘C: show the bar for the copied text. With Accessibility granted we also try to
    /// locate the selection (bar under the text, 置き換え enabled); otherwise the bar opens at the mouse.
    private func showBarForCopiedText(_ text: String) {
        Task { @MainActor in
            var ctx: SelectionContext?
            if AX.isTrusted, let sel = await SelectionReader.read(allowClipboard: false),
               sel.text.trimmingCharacters(in: .whitespacesAndNewlines) == text.trimmingCharacters(in: .whitespacesAndNewlines) {
                ctx = sel
            }
            if ctx == nil {
                let app = NSWorkspace.shared.frontmostApplication
                ctx = SelectionContext(
                    text: text, anchor: nil, element: nil, isEditable: false,
                    pid: app?.processIdentifier ?? 0, appName: app?.localizedName,
                    bundleID: app?.bundleIdentifier, windowTitle: nil, mouse: NSEvent.mouseLocation)
            }
            guard let ctx else { return }
            overlay.showBar(for: ctx)
        }
    }

    private func hotkeyShowBar() {
        Task { @MainActor in
            if let ctx = await SelectionReader.read(allowClipboard: true) {
                overlay.showBar(for: ctx)
            } else {
                NSSound.beep()
            }
        }
    }

    private func hotkeyDirect(_ action: BarAction) {
        Task { @MainActor in
            guard let ctx = await SelectionReader.read(allowClipboard: true) else {
                NSSound.beep()
                return
            }
            switch action {
            case .translate: runTranslate(ctx)
            case .polish: runPolish(ctx, replaceImmediately: true)
            case .addTodo: store.add(from: ctx)
            default: break
            }
        }
    }

    // MARK: Services menu

    func handleService(_ action: BarAction, text: String) {
        Task { @MainActor in
            var ctx = await SelectionReader.read(allowClipboard: false)
            if ctx == nil || ctx?.text != text {
                let app = NSWorkspace.shared.frontmostApplication
                ctx = SelectionContext(
                    text: text, anchor: nil, element: nil, isEditable: false,
                    pid: app?.processIdentifier ?? 0, appName: app?.localizedName,
                    bundleID: app?.bundleIdentifier, windowTitle: nil, mouse: NSEvent.mouseLocation)
            }
            guard let ctx else { return }
            handle(action, ctx)
        }
    }
}

// MARK: - Services provider (右クリック › サービス)

@MainActor
final class ServiceProvider: NSObject {
    weak var controller: AppController?

    @objc func translateService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        run(.translate, pboard)
    }

    @objc func polishService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        run(.polish, pboard)
    }

    @objc func todoService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        run(.addTodo, pboard)
    }

    private func run(_ action: BarAction, _ pboard: NSPasteboard) {
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        controller?.handleService(action, text: text)
    }
}

// MARK: - Search

/// Search where the text came from:
///   Teams → Teams search (⌘E), WeChat → WeChat search (⌘F), everything else → Google in Chrome.
/// Typing into another app needs the Accessibility permission. Without it (e.g. a company Mac) the
/// app is brought to the front and the keyword is put on the clipboard (no popup; explained in Settings).
@MainActor
enum Searcher {
    static let teamsIDs: Set<String> = ["com.microsoft.teams2", "com.microsoft.teams"]
    static let wechatIDs: Set<String> = ["com.tencent.xinWeChat"]
    static let chromeIDs = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary"]
    private static let keyF: CGKeyCode = 3

    static func search(_ raw: String, source bundleID: String?) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if let id = bundleID, teamsIDs.contains(id) {
            searchInApp(id, q, key: KeyCode.e, pressReturn: true)
        } else if let id = bundleID, wechatIDs.contains(id) {
            searchInApp(id, q, key: keyF, pressReturn: false)
        } else {
            searchWeb(q)
        }
    }

    private static func searchInApp(_ bundleID: String, _ q: String, key: CGKeyCode, pressReturn: Bool) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            searchWeb(q)
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { _, _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                if AX.isTrusted {
                    KeySender.press(key, flags: .maskCommand)
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    await ClipboardBridge.paste(q)
                    if pressReturn { KeySender.press(KeyCode.returnKey, flags: []) }
                } else {
                    // No permission to type into other apps: leave the keyword on the clipboard.
                    ClipboardBridge.setString(q)
                }
            }
        }
    }

    /// Google (or the URL template in Settings) in Chrome; default browser if Chrome is not installed.
    private static func searchWeb(_ q: String) {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let encoded = q.addingPercentEncoding(withAllowedCharacters: allowed) ?? q
        guard let url = URL(string: Prefs.searchURL.replacingOccurrences(of: "{q}", with: encoded)) else { return }
        if let chrome = chromeIDs.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: cfg)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
