import AppKit

/// An invisible strip over the notch that opens Notchless when the pointer rests on it.
/// A tracking area costs nothing while the pointer is elsewhere, unlike a global mouse monitor.
final class HoverZone {
    private var window: NSPanel?
    var onHover: () -> Void = {}

    func update(enabled: Bool, screen: NSScreen?) {
        window?.orderOut(nil)
        window = nil
        guard enabled, let screen, let range = MenuExtras.notchRange(on: screen) else { return }

        let rect = NSRect(x: screen.frame.minX + range.lowerBound, y: screen.frame.maxY - screen.safeAreaInsets.top,
                          width: range.upperBound - range.lowerBound, height: screen.safeAreaInsets.top)
        let panel = StripPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = HoverView(frame: NSRect(origin: .zero, size: rect.size))
        view.onHover = { [weak self] in self?.onHover() }
        panel.contentView = view
        panel.orderFrontRegardless()
        window = panel
    }
}

/// Stays over the menu bar, where AppKit would otherwise push it down.
private final class StripPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class HoverView: NSView {
    var onHover: () -> Void = {}
    private var pending: DispatchWorkItem?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    // A short dwell, so sweeping the pointer across the top of the screen doesn't trigger it.
    override func mouseEntered(with event: NSEvent) {
        let work = DispatchWorkItem { [weak self] in self?.onHover() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    override func mouseExited(with event: NSEvent) { pending?.cancel() }

    // The strip is transparent; a color with near-zero alpha makes it receive the tracking events.
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.001).setFill()
        dirtyRect.fill()
    }
}
