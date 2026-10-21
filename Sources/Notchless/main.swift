import AppKit
import SwiftUI

/// Borderless panel that sits over the notch. It can take Esc without activating the app.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let autosaveName = "NotchlessToggle"

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
            guard let self, !self.model.isOpen else { return }
            self.open()
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

    private func toggle() { model.isOpen ? close() : open() }

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
                for _ in 0..<(total * 2) {
                    let frame = DispatchQueue.main.sync { divider.frame }
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

    private func open() {
        guard model.movingID == nil else { return }
        screen = statusItem.button?.window?.screen ?? NSScreen.main ?? screen
        model.notch = notchSize(of: screen)
        model.trusted = MenuExtras.isTrusted
        model.hoveredID = nil
        layoutPanel()
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.model.isOpen = true }
        scan()
        installMonitors()
    }

    private func close() {
        guard model.isOpen else { return }
        model.isOpen = false
        model.hoveredID = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.model.isOpen else { return }
            self.panel.orderOut(nil)
        }
    }

    private func scan() {
        guard MenuExtras.isTrusted else { model.trusted = false; return }
        let screen = screen
        if model.movingID == nil { divider.expand() }
        let dividerFrame = divider.frame
        scanQueue.async { [weak self] in
            let extras = MenuExtras.scan(screen: screen, divider: dividerFrame)
            DispatchQueue.main.async { self?.model.extras = extras }
        }
    }

    private func installMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.close(); return nil }
                return event
            },
        ].compactMap { $0 }
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
