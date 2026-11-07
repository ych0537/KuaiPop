import AppKit
import Combine
import SwiftUI

enum BarAction {
    case search, translate, polish, addTodo, openList, settings
}

enum OverlayMetrics {
    /// Transparent margin around SwiftUI content so the drop shadow isn't clipped.
    static let pad: CGFloat = 14
}

/// Borderless panel that floats above everything and never steals focus from the source app.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a non-key panel trigger buttons immediately.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Placement

enum Placement {
    static func visibleFrame(near p: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Reference rect: the selection, or a small rect at the mouse when the selection is unknown / huge.
    static func reference(anchor: CGRect?, mouse: NSPoint) -> CGRect {
        if let a = anchor, a.height < 240 { return a }
        return CGRect(x: mouse.x - 12, y: mouse.y - 10, width: 24, height: 20)
    }

    /// Origin for a panel of `size` (incl. shadow padding) below the selection, or above if no room.
    static func origin(size: NSSize, ref: CGRect, gap: CGFloat) -> NSPoint {
        let vf = visibleFrame(near: NSPoint(x: ref.midX, y: ref.midY))
        let pad = OverlayMetrics.pad
        var x = ref.minX - pad
        var y = ref.minY - gap - size.height + pad
        if y < vf.minY { y = ref.maxY + gap - pad }
        x = min(max(x, vf.minX), vf.maxX - size.width)
        y = min(max(y, vf.minY), vf.maxY - size.height)
        return NSPoint(x: x, y: y)
    }
}

// MARK: - Floating bar

struct BarView: View {
    let onAction: (BarAction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            BarButton(symbol: "magnifyingglass",
                      label: Prefs.searchMode == .teams ? L("選択したキーワードを Teams で検索") : L("選択したキーワードを Web で検索")) {
                onAction(.search)
            }
            BarButton(symbol: "translate", label: L("翻訳（日本語・英語 → %@）", Prefs.translateTarget)) { onAction(.translate) }
            BarButton(symbol: "sparkles", label: L("ビジネス日本語に推敲")) { onAction(.polish) }
            BarButton(symbol: "checkmark.square", label: L("ToDo に追加"), plusBadge: true) { onAction(.addTodo) }
            BarButton(symbol: "list.bullet", label: L("ToDo リストを開く")) { onAction(.openList) }
            BarButton(symbol: "gearshape", label: L("設定")) { onAction(.settings) }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 5)
        .padding(OverlayMetrics.pad)
        .fixedSize()
    }
}

struct BarButton: View {
    let symbol: String
    let label: String
    var plusBadge = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 1) {
                if plusBadge {
                    Image(systemName: "plus").font(.system(size: 8, weight: .bold))
                }
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
            }
            .frame(width: 40, height: 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Theme.chipHover : Theme.chip))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hover = $0 }
    }
}

// MARK: - Result (shown right under the original text)

@MainActor
final class ResultModel: ObservableObject {
    enum Kind { case translate, polish }
    enum Phase: Equatable {
        case loading
        case done(String)
        case noChange
        case failed(String)
    }

    let kind: Kind
    let canReplace: Bool
    @Published var phase: Phase = .loading
    @Published var copied = false
    /// Translation only: current target language and detected source language.
    @Published var target: String?
    var source: String?
    var onSwitchLanguage: (String) -> Void = { _ in }
    var onReplace: (String) -> Void = { _ in }
    var onClose: () -> Void = {}

    init(kind: Kind, canReplace: Bool) {
        self.kind = kind
        self.canReplace = canReplace
    }

    func copy(_ text: String) {
        ClipboardBridge.setString(text)
        copied = true
    }
}

/// Width rules for the result card: as narrow as the text allows, wrapping only when needed.
enum ResultLayout {
    static let font = NSFont.systemFont(ofSize: 13)
    static let hPad: CGFloat = 12          // inner horizontal padding
    static let minWidth: CGFloat = 236     // fits the toolbar (icon + 中/日/EN + copy + close)
    static let loadingWidth: CGFloat = 236

    /// Widest line of `text` when laid out without wrapping.
    static func naturalWidth(_ text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return text.components(separatedBy: .newlines)
            .map { ceil(($0 as NSString).size(withAttributes: attrs).width) }
            .max() ?? 0
    }

    /// Longer texts get a wider card so they don't turn into a tall, narrow column.
    static func maxWidth(for text: String, screenWidth: CGFloat) -> CGFloat {
        let cap: CGFloat
        switch text.count {
        case ..<120: cap = 420
        case ..<400: cap = 540
        default: cap = 680
        }
        return min(cap, screenWidth - 48)
    }

    static func cardWidth(for phase: ResultModel.Phase, screenWidth: CGFloat) -> CGFloat {
        let text: String
        switch phase {
        case .loading: return loadingWidth
        case .done(let t): text = t
        case .noChange: text = L("このままでビジネス日本語として適切です")
        case .failed(let m): text = m
        }
        let natural = naturalWidth(text) + hPad * 2 + 2
        return min(max(natural, minWidth), maxWidth(for: text, screenWidth: screenWidth))
    }
}

struct ResultView: View {
    @ObservedObject var model: ResultModel
    let screenWidth: CGFloat

    private var width: CGFloat { ResultLayout.cardWidth(for: model.phase, screenWidth: screenWidth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            toolbar
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 5)
        .padding(.bottom, 9)
        .padding(.horizontal, ResultLayout.hPad)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.resultBg))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.accent.opacity(0.18), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
        .padding(OverlayMetrics.pad)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Compact one-line header: kind icon + language switch on the left, actions on the right.
    private var toolbar: some View {
        HStack(spacing: 6) {
            Image(systemName: model.kind == .translate ? "translate" : "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            if model.kind == .translate {
                languageChips
            } else {
                Text(L("推敲")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 4)
            if case .done(let text) = model.phase {
                if model.kind == .polish && model.canReplace {
                    Button(L("置き換え")) { model.onReplace(text) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentStrong)
                        .padding(.horizontal, 4)
                        .frame(height: 20)
                }
                SmallIconButton(symbol: model.copied ? "checkmark" : "doc.on.doc", label: L("コピー")) {
                    model.copy(text)
                }
            }
            SmallIconButton(symbol: "xmark", label: L("閉じる")) { model.onClose() }
        }
        .frame(height: 22)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(model.kind == .translate ? L("翻訳中…") : L("推敲中…"))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
        case .done(let text):
            if text.count > 900 {
                ScrollView {
                    resultText(text)
                }
                .frame(height: 380)
            } else {
                resultText(text)
            }
        case .noChange:
            Text(L("このままでビジネス日本語として適切です"))
                .font(.system(size: 13)).foregroundStyle(Theme.resultText)
        case .failed(let message):
            Text(message)
                .font(.system(size: 12)).foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resultText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(3)
            .foregroundStyle(Theme.resultText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 中 / 日 / EN — re-translate the same text into another language.
    private var languageChips: some View {
        HStack(spacing: 1) {
            ForEach(AIService.quickLangs) { lang in
                let selected = model.target == lang.name
                Button {
                    if !selected { model.onSwitchLanguage(lang.name) }
                } label: {
                    Text(lang.short)
                        .font(.system(size: 11, weight: selected ? .bold : .medium))
                        .frame(minWidth: 22, minHeight: 18)
                        .padding(.horizontal, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Theme.accent : Color.clear))
                        .foregroundStyle(selected ? Theme.onAccent : Theme.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("%@に翻訳", lang.name))
                .accessibilityLabel(L("%@に翻訳", lang.name))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

struct SmallIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondary)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Controller

@MainActor
final class OverlayController {
    var onAction: ((BarAction, SelectionContext) -> Void)?

    private var barPanel: OverlayPanel?
    private var barContext: SelectionContext?

    private var resultPanel: OverlayPanel?
    private var resultHost: NSView?
    private var resultRef: CGRect = .zero
    private var resultCancellable: AnyCancellable?
    var resultTask: Task<Void, Never>?

    var isShowingAnything: Bool { barPanel != nil || resultPanel != nil }

    func showBar(for ctx: SelectionContext) {
        hideAll()
        barContext = ctx
        let view = BarView { [weak self] action in
            guard let self, let ctx = self.barContext else { return }
            self.onAction?(action, ctx)
        }
        let host = FirstMouseHostingView(rootView: view)
        let size = host.fittingSize
        let panel = OverlayPanel()
        panel.contentView = host
        let ref = Placement.reference(anchor: ctx.anchor, mouse: ctx.mouse)
        panel.setFrame(NSRect(origin: Placement.origin(size: size, ref: ref, gap: 8), size: size), display: true)
        panel.orderFrontRegardless()
        barPanel = panel
    }

    func hideBar() {
        barPanel?.orderOut(nil)
        barPanel = nil
        barContext = nil
    }

    @discardableResult
    func showResult(kind: ResultModel.Kind, ctx: SelectionContext) -> ResultModel {
        hideAll()
        let model = ResultModel(kind: kind, canReplace: ctx.isEditable)
        model.onClose = { [weak self] in self?.hideResult() }

        resultRef = Placement.reference(anchor: ctx.anchor, mouse: ctx.mouse)
        let screenWidth = Placement.visibleFrame(near: NSPoint(x: resultRef.midX, y: resultRef.midY)).width
        let host = FirstMouseHostingView(rootView: ResultView(model: model, screenWidth: screenWidth))
        let panel = OverlayPanel()
        panel.contentView = host
        resultPanel = panel
        resultHost = host
        layoutResult()
        panel.orderFrontRegardless()

        resultCancellable = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.layoutResult() }
        }
        return model
    }

    private func layoutResult() {
        guard let panel = resultPanel, let host = resultHost else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setFrame(NSRect(origin: Placement.origin(size: size, ref: resultRef, gap: 4), size: size), display: true)
    }

    func hideResult() {
        resultTask?.cancel()
        resultTask = nil
        resultCancellable = nil
        resultPanel?.orderOut(nil)
        resultPanel = nil
        resultHost = nil
    }

    func hideAll() {
        hideBar()
        hideResult()
    }
}
