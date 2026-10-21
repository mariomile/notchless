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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // New status items land on the far left, which on a crowded bar means behind the notch.
        // Seed a position next to the system items on first launch; Cmd-drag still moves it.
        let key = "NSStatusItem Preferred Position \(Self.autosaveName)"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(320, forKey: key)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = Self.autosaveName
        let symbol = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notchless")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))!
        divider = Divider(item: statusItem, symbol: symbol)
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
        hoverZone.onHover = { [weak self] in
            guard let self, !self.model.isOpen else { return }
            self.open()
        }
        applySettings()
        DispatchQueue.main.async { self.divider.expand() }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.close()
            self?.applySettings()
            self?.divider.expand()
        }

        if !MenuExtras.isTrusted { MenuExtras.requestTrust() }
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
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
                    self.divider.expand()
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
