import AppKit

/// Moves an item across the Notchless divider by simulating the Cmd-drag a person would do.
/// macOS has no API for this; the timings below are what MenuBarAgent accepts.
enum MenuBarMover {
    enum Failure: Error, CustomStringConvertible {
        case menuBarHidden, noRoom, didNotMove

        var description: String {
            switch self {
            case .menuBarHidden: "the menu bar isn't showing on this display (a full-screen app, or the active menu bar is on another screen). Try again from the desktop."
            case .noRoom: "there's no room for it next to the notch. Hide another item first."
            case .didNotMove: "macOS didn't accept the move. Try again, or Cmd-drag it across the divider."
            }
        }
    }

    /// Blocking: takes about two seconds and moves the pointer. Call off the main thread.
    static func setHidden(_ hidden: Bool, _ extra: MenuExtra, divider: Divider) -> Result<Void, Failure> {
        onMain { divider.collapse() }
        defer { DispatchQueue.main.async { divider.refit() } }
        usleep(450_000)

        let (d, visible) = onMain { (divider.frame, divider.isVisible) }
        guard d != .zero, visible, isMenuBarOnScreen(at: CGPoint(x: d.midX, y: d.midY)) else { return .failure(.menuBarHidden) }

        let frame = MenuExtras.frame(of: extra.element)
        // With the divider collapsed, an item that's still tucked away simply doesn't fit.
        if !hidden, !isOnBar(frame, near: d) { return .failure(.noRoom) }

        let savedCursor = CGEvent(source: nil)?.location
        // macOS only accepts a drop on another item: the divider's left end inserts before it (hidden),
        // its right end after it (visible). Status items are right-anchored, so the divider doesn't shift
        // while the dragged item is lifted from either side.
        let destination = CGPoint(x: hidden ? d.minX + 6 : d.maxX - 6, y: d.midY)
        commandDrag(from: CGPoint(x: frame.midX, y: frame.midY), to: destination)
        if let savedCursor { CGWarpMouseCursorPosition(savedCursor) }
        usleep(400_000)

        let moved = MenuExtras.frame(of: extra.element)
        let after = onMain { divider.frame }
        let nowHidden = moved.maxX <= after.minX + 2
        return nowHidden == hidden ? .success(()) : .failure(.didNotMove)
    }

    private static func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    /// Drawn on the same menu bar as the divider, not stacked out of sight.
    private static func isOnBar(_ frame: CGRect, near divider: CGRect) -> Bool {
        abs(frame.midY - divider.midY) < 20 && frame.width > 0 && frame.maxX <= divider.minX + 2
            && (MenuExtras.overflowButton().map { frame.minX > $0.maxX - 2 } ?? true)
    }

    /// The menu bar is a layer-24 window; a full-screen app takes it off screen.
    private static func isMenuBarOnScreen(at point: CGPoint) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard window[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.mainMenuWindow)),
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rect.contains(point)
        }
    }

    private static let source = CGEventSource(stateID: .combinedSessionState)

    private static func post(_ type: CGEventType, _ point: CGPoint) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        event?.flags = .maskCommand
        if type != .mouseMoved { event?.setIntegerValueField(.mouseEventClickState, value: 1) }
        event?.post(tap: .cghidEventTap)
    }

    private static func commandDrag(from start: CGPoint, to end: CGPoint) {
        post(.mouseMoved, start); usleep(40_000)
        post(.leftMouseDown, start); usleep(350_000)
        let steps = 40
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            usleep(20_000)
        }
        usleep(300_000)
        post(.leftMouseUp, end)
    }
}
