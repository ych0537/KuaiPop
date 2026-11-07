import AppKit

/// Watches global mouse/keyboard events and reports a new text selection.
@MainActor
final class SelectionMonitor {
    var onSelection: ((SelectionContext) -> Void)?
    var onMouseDown: (() -> Void)?
    var onKeyDown: ((UInt16) -> Void)?
    var onScroll: (() -> Void)?

    private var monitors: [Any] = []
    private var downPoint = NSPoint.zero
    private var task: Task<Void, Never>?

    func start() {
        stop()
        add(.leftMouseDown) { [weak self] _ in
            let p = NSEvent.mouseLocation
            Task { @MainActor in self?.mouseDown(at: p) }
        }
        add(.leftMouseUp) { [weak self] e in
            let p = NSEvent.mouseLocation
            let clicks = e.clickCount
            let shift = e.modifierFlags.contains(.shift)
            Task { @MainActor in self?.mouseUp(at: p, clicks: clicks, shift: shift) }
        }
        add(.keyDown) { [weak self] e in
            let code = e.keyCode
            Task { @MainActor in self?.onKeyDown?(code) }
        }
        add(.scrollWheel) { [weak self] _ in
            Task { @MainActor in self?.onScroll?() }
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(m)
        }
    }

    private func mouseDown(at p: NSPoint) {
        downPoint = p
        task?.cancel()
        onMouseDown?()
    }

    private func mouseUp(at p: NSPoint, clicks: Int, shift: Bool) {
        guard Prefs.triggerMode == .auto, AX.isTrusted else { return }
        let dragged = hypot(p.x - downPoint.x, p.y - downPoint.y) > 5
        guard dragged || clicks >= 2 || shift else { return }
        if let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           Prefs.excludedBundleIDs.contains(bid) { return }

        let start = downPoint
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            let ctx = await SelectionReader.read(
                allowClipboard: Prefs.clipboardFallback && (dragged || clicks >= 2),
                near: [start, p])
            guard !Task.isCancelled, let ctx else { return }
            self?.onSelection?(ctx)
        }
    }
}
