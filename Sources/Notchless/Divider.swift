import AppKit

/// The Notchless button doubles as the divider: it widens leftwards until it reaches the notch, so
/// every item to its left runs out of room and macOS tucks it away. Items to its right stay visible.
/// One status item means the order can never get mixed up: hidden on the left, visible on the right.
final class Divider {
    private let item: NSStatusItem
    private let symbol: NSImage
    private static let collapsedLength: CGFloat = 28
    private var isExpanded = false
    /// Extra room given back when macOS says the expanded button no longer fits.
    private var slack: CGFloat = 0

    init(item: NSStatusItem, symbol: NSImage) {
        self.item = item
        self.symbol = symbol
        setLength(Self.collapsedLength)

        // The button's window moves whenever items to its right come and go or the menu bar changes
        // display; re-fit then. Once the width is right, expanding again changes nothing, so this settles.
        for name in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
            NotificationCenter.default.addObserver(forName: name, object: item.button?.window, queue: .main) { [weak self] _ in
                guard let self, self.isExpanded else { return }
                self.expand()
            }
        }
    }

    /// The button's frame in global, top-left screen coordinates (the Accessibility API's space).
    var frame: CGRect {
        guard let window = item.button?.window else { return .zero }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let f = window.frame
        return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
    }

    /// False when the menu bar holding the button isn't drawn: a full-screen app, or the active menu bar is on another display.
    var isVisible: Bool { item.button?.window?.occlusionState.contains(.visible) ?? false }

    func collapse() {
        isExpanded = false
        setLength(Self.collapsedLength)
    }

    /// Widens the button so its left edge meets the notch, leaving room for macOS's « chevron.
    /// On a screen without a notch it stops at the middle, clear of the app menus.
    func expand() {
        isExpanded = true
        guard let window = item.button?.window, let screen = window.screen else { return }
        let boundary = MenuExtras.notchRange(on: screen).map { screen.frame.minX + $0.upperBound + 30 }
            ?? screen.frame.minX + screen.frame.width * 0.5
        let length = max(Self.collapsedLength, window.frame.maxX - boundary - slack)
        guard abs(item.length - length) > 1 else { return }
        setLength(length)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.backOffIfOverflowed() }
    }

    /// If macOS tucked the button itself away, it was too wide: give some room back.
    private func backOffIfOverflowed() {
        guard isExpanded, slack < 200, let chevron = MenuExtras.overflowButton() else { return }
        let f = frame
        guard abs(f.midY - chevron.midY) < 20, f.maxX <= chevron.maxX + 2 else { return }
        slack += 40
        expand()
    }

    /// The symbol sits at the right end; the rest of the width is empty space.
    private func setLength(_ length: CGFloat) {
        item.length = length
        let size = NSSize(width: max(length - 8, symbol.size.width), height: max(symbol.size.height, 16))
        let image = NSImage(size: size, flipped: false) { [symbol] rect in
            symbol.draw(in: NSRect(x: rect.maxX - symbol.size.width, y: (rect.height - symbol.size.height) / 2,
                                   width: symbol.size.width, height: symbol.size.height))
            return true
        }
        image.isTemplate = true
        item.button?.image = image
    }
}
