import AppKit

/// Shows the floating bar when the user presses ⌘C twice in quick succession.
///
/// Works WITHOUT the Accessibility permission: it never reads keyboard events.
/// It only polls `NSPasteboard.changeCount` (no permission needed) and treats two
/// clipboard updates with the same text within `window` seconds as a "double copy".
@MainActor
final class DoubleCopyTrigger {
    /// Called with the copied text.
    var onTrigger: ((String) -> Void)?

    /// Max time between the two copies.
    private let window: TimeInterval = 0.7
    private let pollInterval: TimeInterval = 0.05

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var firstCopy: (time: Date, text: String)?

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        firstCopy = nil
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        firstCopy = nil
    }

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        // Several writes between two polls (some apps write twice per copy) count as ONE copy.
        lastChangeCount = count

        // Ignore clipboard changes KuaiPop made itself (⌘C fallback, paste, restore, copy button).
        if ClipboardBridge.isOwnChange(count) {
            firstCopy = nil
            return
        }
        // Text only; ignore files, images, etc.
        if pb.types?.contains(.fileURL) == true {
            firstCopy = nil
            return
        }
        guard let text = pb.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            firstCopy = nil
            return
        }

        let now = Date()
        if let first = firstCopy, now.timeIntervalSince(first.time) <= window, first.text == text {
            firstCopy = nil
            onTrigger?(text)
        } else {
            firstCopy = (now, text)
        }
    }
}
