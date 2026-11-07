import AppKit
import ApplicationServices

/// Everything we know about the text the user just selected.
struct SelectionContext {
    var text: String
    /// Selection rect in Cocoa global coordinates (nil when the app does not expose it).
    var anchor: CGRect?
    var element: AXUIElement?
    var isEditable: Bool
    var pid: pid_t
    var appName: String?
    var bundleID: String?
    var windowTitle: String?
    var mouse: NSPoint
}

enum KeyCode {
    static let c: CGKeyCode = 8
    static let v: CGKeyCode = 9
    static let e: CGKeyCode = 14
    static let returnKey: CGKeyCode = 36
    static let escape: UInt16 = 53
}

enum KeySender {
    static func press(_ key: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Reads/writes the selection through the pasteboard, always restoring the user's clipboard.
@MainActor
enum ClipboardBridge {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]
    /// Tells clipboard managers (nspasteboard.org convention) to ignore our temporary content.
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static func snapshot() -> Snapshot {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types {
                if let d = item.data(forType: t) { dict[t] = d }
            }
            return dict
        }
    }

    static func restore(_ snap: Snapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let items: [NSPasteboardItem] = snap.map { dict in
            let item = NSPasteboardItem()
            for (t, d) in dict { item.setData(d, forType: t) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    /// Simulates ⌘C and returns the copied string.
    static func copySelection() async -> String? {
        let pb = NSPasteboard.general
        let snap = snapshot()
        let before = pb.changeCount
        KeySender.press(KeyCode.c, flags: .maskCommand)
        var changed = false
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pb.changeCount != before { changed = true; break }
        }
        guard changed else { return nil }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let isFiles = pb.types?.contains(.fileURL) ?? false
        let text = isFiles ? nil : pb.string(forType: .string)
        restore(snap)
        return text
    }

    static func setString(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Pastes text into the frontmost app (replacing its selection) and restores the clipboard.
    static func paste(_ text: String) async {
        let snap = snapshot()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        pb.setData(Data(), forType: transient)
        try? await Task.sleep(nanoseconds: 40_000_000)
        KeySender.press(KeyCode.v, flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 450_000_000)
        restore(snap)
    }
}

@MainActor
enum SelectionReader {
    private static var touchedPIDs = Set<pid_t>()
    private static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// - Parameters:
    ///   - allowClipboard: fall back to ⌘C when the app doesn't expose AXSelectedText.
    ///   - near: if non-empty, the focused element must contain one of these points (mouse gesture sanity check).
    static func read(allowClipboard: Bool, near points: [NSPoint] = []) async -> SelectionContext? {
        guard AX.isTrusted, let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        if pid == ProcessInfo.processInfo.processIdentifier { return nil }

        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.6)
        if !touchedPIDs.contains(pid) {
            touchedPIDs.insert(pid)
            // Electron / Chromium-based apps (Teams, Slack, VS Code…) only build their AX tree on request.
            AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        var ctx = SelectionContext(
            text: "", anchor: nil, element: nil, isEditable: false, pid: pid,
            appName: app.localizedName, bundleID: app.bundleIdentifier, windowTitle: nil,
            mouse: NSEvent.mouseLocation)

        if let win = AX.element(appEl, kAXFocusedWindowAttribute) {
            ctx.windowTitle = AX.string(win, kAXTitleAttribute)
        }

        if let focused = AX.element(appEl, kAXFocusedUIElementAttribute) {
            if AX.string(focused, kAXSubroleAttribute) == kAXSecureTextFieldSubrole { return nil }
            ctx.element = focused
            let role = AX.string(focused, kAXRoleAttribute) ?? ""
            ctx.isEditable = editableRoles.contains(role) || AX.isSettable(focused, kAXValueAttribute)

            if let t = AX.string(focused, kAXSelectedTextAttribute),
               !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !points.isEmpty, let f = AX.frame(of: focused) {
                    let area = AX.toCocoa(f).insetBy(dx: -24, dy: -24)
                    if !points.contains(where: { area.contains($0) }) { return nil }
                }
                ctx.text = t
                if let r = AX.selectedRange(focused), r.length > 0,
                   let b = AX.bounds(for: r, in: focused), b.width > 1, b.height > 1 {
                    let cocoa = AX.toCocoa(b)
                    if NSScreen.screens.contains(where: { $0.frame.intersects(cocoa) }) {
                        ctx.anchor = cocoa
                    }
                }
                return ctx
            }
        }

        guard allowClipboard else { return nil }
        guard let t = await ClipboardBridge.copySelection(),
              !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        ctx.text = t
        return ctx
    }
}
