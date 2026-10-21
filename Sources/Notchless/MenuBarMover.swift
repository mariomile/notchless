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
        let screen = onMain { NSScreen.screens.first { MenuExtras.notchRange(on: $0) != nil } ?? NSScreen.screens[0] }
        // Already where it should be? Then don't touch the bar.
        let expanded = onMain { divider.frame }
        if let current = MenuExtras.scan(screen: screen, divider: expanded).first(where: { $0.id == extra.id }),
           current.isHidden == hidden { return .success(()) }

        onMain { divider.collapse() }
        defer { DispatchQueue.main.async { divider.refit() } }
        usleep(450_000)

        let (d, visible) = onMain { (divider.frame, divider.isVisible) }
        guard d != .zero, visible, isMenuBarOnScreen(at: CGPoint(x: d.midX, y: d.midY)) else { return .failure(.menuBarHidden) }

        let frame = MenuExtras.frame(of: extra.element)
        let chevron = MenuExtras.overflowButton()
        // With the divider collapsed, an item that's still tucked away simply doesn't fit.
        if !hidden, !isOnBar(frame, near: d, chevron: chevron) { return .failure(.noRoom) }

        // macOS only accepts a drop on another app's item, and inserts on the side of that item the
        // pointer is on. So aim at the outer half of the divider's neighbour: the item just left of it
        // to hide, the one just right of it (Control Centre, usually) to show.
        let others = MenuExtras.scan(screen: screen).filter { $0.id != extra.id && isOnBar($0.frame, near: nil, chevron: chevron) }
        let destination: CGPoint
        if hidden, let left = others.filter({ $0.frame.maxX <= d.minX + 2 }).max(by: { $0.frame.maxX < $1.frame.maxX }) {
            destination = CGPoint(x: left.frame.maxX - min(6, left.frame.width / 4), y: d.midY)
        } else if !hidden, let right = others.filter({ $0.frame.minX >= d.maxX - 2 }).min(by: { $0.frame.minX < $1.frame.minX }) {
            destination = CGPoint(x: right.frame.minX + min(6, right.frame.width / 4), y: d.midY)
        } else {
            destination = CGPoint(x: hidden ? d.minX - 4 : d.maxX + 4, y: d.midY)
        }

        let savedCursor = CGEvent(source: nil)?.location
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

    /// Drawn on the menu bar, not stacked out of sight under the chevron. With `divider`, also left of it.
    private static func isOnBar(_ frame: CGRect, near divider: CGRect?, chevron: CGRect?) -> Bool {
        guard frame.width > 0, chevron.map({ frame.minX > $0.maxX - 2 }) ?? true else { return false }
        guard let divider else { return true }
        return abs(frame.midY - divider.midY) < 20 && frame.maxX <= divider.minX + 2
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
