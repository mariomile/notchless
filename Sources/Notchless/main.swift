import AppKit
import SwiftUI

/// Borderless panel that sits over the notch. It can take Esc without activating the app.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    /// AppKit keeps windows out of the menu bar; this one has to sit over it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // A fresh name gives the icon a fresh slot: macOS keeps the slot of a name it already knows,
    // and the old one sat on the left, where a full bar hides first.
    private static let autosaveName = "NotchlessButton"

    private var statusItem: NSStatusItem!
    private let model = NotchModel()
    private lazy var panel = makePanel()
    private var monitors: [Any] = []
    private var screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    private let scanQueue = DispatchQueue(label: "notchless.scan", qos: .userInitiated)
    private lazy var hotkey = Hotkey { [weak self] in self?.toggle() }
    private let hoverZone = HoverZone()
    private var divider: Divider!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var pointerWatch: Timer?
    /// True from open() until close(); `model.isOpen` follows one tick later.
    private var shown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // macOS tucks away the leftmost items first when the bar is full, so Notchless has to sit on the
        // right, next to the system items. The value is the distance from the right edge; Cmd-drag still moves it.
        let key = "NSStatusItem Preferred Position \(Self.autosaveName)"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(5, forKey: key)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = Self.autosaveName
        let symbol = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notchless")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))!
        divider = Divider(item: statusItem, symbol: symbol)
        divider.isEnabled = model.dividerEnabled
        if let button = statusItem.button {
            button.setAccessibilityLabel("Notchless")
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        model.onSelect = { [weak self] extra in
            self?.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { extra.open() }
        }
        model.onDismiss = { [weak self] in self?.close() }
        model.onSetHidden = { [weak self] extra, hidden in self?.setHidden(extra, hidden) }
        model.onOpenSettings = { [weak self] in self?.openSettings() }
        model.onSettingsChanged = { [weak self] in self?.applySettings() }
        model.onRefresh = { [weak self] in self?.scan() }
        model.onShowOnboarding = { [weak self] in self?.showOnboarding() }
        hoverZone.onHover = { [weak self] in
            log.info("hover on notch, open \(self?.model.isOpen ?? false)")
            guard let self, !self.shown else { return }
            self.open(byHover: true)
            self.watchPointerUntilItLeaves()
        }
        applySettings()
        DispatchQueue.main.async { self.divider.refit() }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.close()
            self?.applySettings()
            self?.divider.refit()
        }

        if UserDefaults.standard.bool(forKey: "onboardingDone") {
            if !MenuExtras.isTrusted { MenuExtras.requestTrust() }
        } else {
            showOnboarding()
        }
    }

    @objc private func statusClicked() {
        log.info("status item clicked, event \(NSApp.currentEvent?.type.rawValue ?? 0), shown \(self.shown), moving \(self.model.movingID ?? "-", privacy: .public)")
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(withTitle: "Setup Guide…", action: #selector(showOnboarding), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Notchless", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        toggle()
    }

    private func toggle() { shown ? close() : open() }

    @objc private func refresh() { scan() }

    private func applySettings() {
        if divider.isEnabled != model.dividerEnabled { divider.isEnabled = model.dividerEnabled }
        hotkey.register(model.shortcut)
        hoverZone.update(enabled: model.hoverToOpen,
                         screen: NSScreen.screens.first { MenuExtras.notchRange(on: $0) != nil })
    }

    // MARK: - Settings and moving items

    @objc private func openSettings() {
        close()
        scan()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Notchless Settings"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Onboarding

    @objc private func showOnboarding() {
        close()
        settingsWindow?.close()
        model.trusted = MenuExtras.isTrusted
        scan()
        if onboardingWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: OnboardingView(model: model) { [weak self] choices in
                self?.finishOnboarding(choices)
            })
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    /// Applies the item choices one move at a time, re-reading the menu bar after each, then shows the result.
    private func finishOnboarding(_ choices: [String: Bool]) {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        onboardingWindow?.close()
        let wanted = { (extra: MenuExtra) in extra.canMove && choices[extra.id].map { $0 != extra.isHidden } == true }
        let total = model.extras.filter(wanted).count
        guard total > 0 else { open(); return }

        // Hiding something that fits today needs the Notchless icon to widen up to the notch.
        if model.extras.contains(where: { wanted($0) && !$0.isHidden }) { model.dividerEnabled = true }
        model.movingID = "onboarding"
        let screen = screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            let divider = self.divider!
            self.scanQueue.async {
                var failed: [String: String] = [:]
                // Turning the divider on tucks away everything left of the icon, so more than `total`
                // items may need a move; the loop stops when nothing differs from the choices.
                for _ in 0..<(self.model.extras.count * 2) {
                    let frame = DispatchQueue.main.sync { self.model.dividerEnabled ? divider.frame : nil }
                    guard let next = MenuExtras.scan(screen: screen, divider: frame)
                        .first(where: { wanted($0) && failed[$0.id] == nil }) else { break }
                    if case .failure(let failure) = MenuBarMover.setHidden(choices[next.id]!, next, divider: divider) {
                        failed[next.id] = "\(next.name): \(failure)"
                        if case .menuBarHidden = failure { break }
                    }
                    usleep(800_000)
                }
                DispatchQueue.main.async {
                    self.model.movingID = nil
                    if failed.isEmpty {
                        self.open()
                    } else {
                        self.model.message = "Some items didn't move. " + failed.values.sorted().joined(separator: " ")
                        self.openSettings()
                    }
                }
            }
        }
    }

    private func setHidden(_ extra: MenuExtra, _ hidden: Bool) {
        guard model.movingID == nil else { return }
        close()
        model.movingID = extra.id
        model.message = nil
        // Let the notch finish closing so the drag isn't drawn over it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let divider = self?.divider else { return }
            self?.scanQueue.async {
                let result = MenuBarMover.setHidden(hidden, extra, divider: divider)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.model.movingID = nil
                    if case .failure(let failure) = result {
                        self.model.message = "\(extra.name): \(failure)"
                        if self.settingsWindow?.isVisible != true { self.openSettings() }
                    }
                    self.scan()
                }
            }
        }
    }

    // MARK: - Open / close

    private func open(byHover: Bool = false) {
        guard model.movingID == nil else { log.error("open refused: moving \(self.model.movingID ?? "-")"); return }
        // The screen the person is looking at. The button's own window can report another display,
        // e.g. while the icon itself is tucked away, and the notch would open there.
        let mouse = NSEvent.mouseLocation
        screen = NSScreen.screens.first { MenuExtras.notchRange(on: $0) != nil }
            ?? NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(mouse) }
            ?? NSScreen.main ?? screen
        model.notch = notchSize(of: screen)
        model.trusted = MenuExtras.isTrusted
        model.hoveredID = nil
        model.query = ""
        model.selectedID = nil
        layoutPanel()
        log.info("open byHover \(byHover) on \(self.screen.localizedName, privacy: .public) panel \(self.panel.frame.debugDescription, privacy: .public)")
        // Opened by hovering, the notch must not steal the keyboard from whatever you're typing in.
        if byHover { panel.orderFrontRegardless() } else { panel.makeKeyAndOrderFront(nil) }
        shown = true
        // One tick later, so the notch animates open from its closed shape.
        DispatchQueue.main.async { if self.shown { self.model.isOpen = true } }
        scan()
        installMonitors()
    }

    /// Opened by hovering, the notch closes on its own once the pointer has been outside it for a moment.
    /// Polls only while that notch is open; a click-opened notch stays until you click away.
    private func watchPointerUntilItLeaves() {
        pointerWatch?.invalidate()
        var outsideSince: Date?
        pointerWatch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.shown else { self?.pointerWatch?.invalidate(); return }
            let size = self.model.openSize
            let notch = NSRect(x: self.panel.frame.midX - size.width / 2, y: self.screen.frame.maxY - size.height,
                               width: size.width, height: size.height).insetBy(dx: -8, dy: -8)
            if notch.contains(NSEvent.mouseLocation) {
                outsideSince = nil
            } else if let since = outsideSince {
                if Date().timeIntervalSince(since) >= 2.5 { self.close() }
            } else {
                outsideSince = Date()
            }
        }
    }

    private func close() {
        pointerWatch?.invalidate()
        pointerWatch = nil
        guard shown else { return }
        log.info("close")
        shown = false
        model.isOpen = false
        model.hoveredID = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.shown else { return }
            self.panel.orderOut(nil)
        }
    }

    private func scan() {
        guard MenuExtras.isTrusted else { model.trusted = false; return }
        let screen = screen
        if model.movingID == nil { divider.expand() }
        let dividerFrame = model.dividerEnabled ? divider.frame : nil
        scanQueue.async { [weak self] in
            let extras = MenuExtras.scan(screen: screen, divider: dividerFrame)
            DispatchQueue.main.async {
                self?.model.extras = extras
                self?.model.scanned = true
            }
        }
    }

    private func installMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = [
            // A click anywhere else closes the notch. The status bar delivers a click on our own icon to
            // this monitor too, and letting it close here would make the icon's mouse-up reopen at once.
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return }
                if let button = self.statusItem.button, let window = button.window,
                   window.frame.contains(NSEvent.mouseLocation) { return }
                self.close()
            },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKey(event) ?? event
            },
        ].compactMap { $0 }
    }

    /// Typing searches, arrows move between tiles, Return opens, Esc clears the search and then closes.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard shown else { return event }
        log.info("key \(event.keyCode) query '\(self.model.query, privacy: .public)'")
        switch event.keyCode {
        case 53:
            if model.query.isEmpty { close() } else { model.type("") }
        case 36, 76:
            if let extra = model.ordered.first(where: { $0.id == model.selectedID }) { model.onSelect(extra) }
        case 51:
            model.type(String(model.query.dropLast()))
        case 123: model.moveSelection(-1)
        case 124: model.moveSelection(1)
        case 125: model.moveSelection(model.columns)
        case 126: model.moveSelection(-model.columns)
        default:
            guard event.modifierFlags.intersection([.command, .control]).isEmpty,
                  let text = event.characters, !text.isEmpty,
                  text.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).union(.whitespaces).contains($0) })
            else { return event }
            model.type(model.query + text)
        }
        return nil
    }

    // MARK: - Geometry

    private func notchSize(of screen: NSScreen) -> CGSize {
        let barHeight = screen.frame.maxY - screen.visibleFrame.maxY
        if let range = MenuExtras.notchRange(on: screen) {
            return CGSize(width: range.upperBound - range.lowerBound, height: max(screen.safeAreaInsets.top, barHeight))
        }
        return CGSize(width: 180, height: max(barHeight, 24))
    }

    /// A fixed canvas, pinned to the top center of the notch, roomy enough for any open size plus its shadow.
    /// It never resizes while open, so the notch animates smoothly as items arrive.
    private func layoutPanel() {
        let width: CGFloat = 1000, height: CGFloat = 720
        let centerX: CGFloat
        if let range = MenuExtras.notchRange(on: screen) {
            centerX = screen.frame.minX + (range.lowerBound + range.upperBound) / 2
        } else {
            centerX = screen.frame.midX
        }
        panel.setFrame(NSRect(x: centerX - width / 2, y: screen.frame.maxY - height, width: width, height: height), display: true)
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: NotchRoot(model: model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

let app = NSApplication.shared

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
