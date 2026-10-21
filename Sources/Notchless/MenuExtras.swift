import AppKit
import ApplicationServices

/// One item living in the right side of the menu bar, read through the Accessibility API.
struct MenuExtra: Identifiable {
    let id: String
    let name: String
    let detail: String
    let icon: NSImage?
    let symbol: String?
    let tint: NSColor
    let frame: CGRect
    let isHidden: Bool
    /// Clock and Control Centre are pinned by macOS and cannot be moved.
    let canMove: Bool
    let element: AXUIElement

    func open() {
        let element = element
        DispatchQueue.global(qos: .userInitiated).async {
            AXUIElementSetMessagingTimeout(element, 0.5)
            if AXUIElementPerformAction(element, kAXPressAction as CFString) == .actionUnsupported {
                AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
            }
        }
    }
}

enum MenuExtras {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Reads every menu extra of every running app. Runs off the main thread.
    static func scan(screen: NSScreen, divider: CGRect? = nil) -> [MenuExtra] {
        let me = ProcessInfo.processInfo.processIdentifier
        var found: [MenuExtra] = []
        var hiddenButtonMaxX: CGFloat?

        for app in NSWorkspace.shared.runningApplications
        where app.processIdentifier != me && app.bundleIdentifier != Bundle.main.bundleIdentifier {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.1)
            guard let bar: AXUIElement = attribute(appElement, "AXExtrasMenuBar") else { continue }

            let isSystem = app.bundleIdentifier == "com.apple.MenuBarAgent"
            for (index, item) in menuBarItems(in: bar, systemButton: &hiddenButtonMaxX).enumerated() {
                let title: String = attribute(item, kAXTitleAttribute) ?? ""
                let description: String = attribute(item, kAXDescriptionAttribute) ?? ""
                let identifier: String = attribute(item, kAXIdentifierAttribute) ?? ""
                let appName = displayName(for: app)
                let detail = [title, description].map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? appName

                let icon = isSystem ? nil : bundleIcon(for: app)
                found.append(MenuExtra(
                    id: "\(app.processIdentifier)-\(index)-\(identifier)",
                    name: isSystem ? (description.isEmpty ? "System" : description) : appName,
                    detail: detail,
                    icon: icon,
                    symbol: isSystem ? symbol(for: identifier) : nil,
                    tint: icon.map(averageColor) ?? NSColor(white: 0.75, alpha: 1),
                    frame: frame(of: item),
                    isHidden: false,
                    canMove: !(isSystem && (identifier.hasSuffix(".clock") || identifier.hasSuffix(".controlcenter"))),
                    element: item
                ))
            }
        }

        // An item is hidden when it sits behind the notch, when macOS stacked it under its own
        // "Show Hidden Menu Bar Items" overflow button, or when it's left of the Notchless divider.
        let notch = notchRange(on: screen)
        return found
            .map { extra in
                let behindNotch = notch.map { extra.frame.minX < $0.upperBound && extra.frame.maxX > $0.lowerBound } ?? false
                let collapsed = hiddenButtonMaxX.map { extra.frame.maxX <= $0 + 2 } ?? false
                let offscreen = extra.frame.maxX <= 0 || extra.frame.width == 0
                let leftOfDivider = divider.map { $0 != .zero && extra.frame.maxX <= $0.minX + 2 && abs(extra.frame.midY - $0.midY) < 20 } ?? false
                return MenuExtra(id: extra.id, name: extra.name, detail: extra.detail, icon: extra.icon,
                                 symbol: extra.symbol, tint: extra.tint, frame: extra.frame,
                                 isHidden: behindNotch || collapsed || offscreen || leftOfDivider, canMove: extra.canMove,
                                 element: extra.element)
            }
            .sorted { ($0.frame.minX, $0.name) < ($1.frame.minX, $1.name) }
    }

    static func notchRange(on screen: NSScreen) -> ClosedRange<CGFloat>? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        return (left.maxX - screen.frame.minX)...(right.minX - screen.frame.minX)
    }

    /// The frame of macOS's own "Show Hidden Menu Bar Items" chevron. Items to its left are hidden.
    static func overflowButton() -> CGRect? {
        guard let agent = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.MenuBarAgent" }) else { return nil }
        let appElement = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.2)
        guard let bar: AXUIElement = attribute(appElement, "AXExtrasMenuBar") else { return nil }
        return (attribute(bar, kAXChildrenAttribute) as [AXUIElement]? ?? [])
            .first { (attribute($0, kAXRoleAttribute) as String?) == "AXButton" }
            .map(frame(of:))
    }

    // MARK: - Accessibility helpers

    private static func menuBarItems(in bar: AXUIElement, systemButton: inout CGFloat?) -> [AXUIElement] {
        var items: [AXUIElement] = []
        for child in attribute(bar, kAXChildrenAttribute) as [AXUIElement]? ?? [] {
            let role: String = attribute(child, kAXRoleAttribute) ?? ""
            switch role {
            case "AXMenuBarItem":
                items.append(child)
            case "AXGroup":
                items += menuBarItems(in: child, systemButton: &systemButton)
            case "AXButton":
                systemButton = frame(of: child).maxX
            default:
                break
            }
        }
        return items
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func frame(of element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero, size = CGSize.zero
        if let value: AXValue = attribute(element, kAXPositionAttribute) { AXValueGetValue(value, .cgPoint, &origin) }
        if let value: AXValue = attribute(element, kAXSizeAttribute) { AXValueGetValue(value, .cgSize, &size) }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Visuals

    private static var iconCache: [String: NSImage] = [:]

    /// The icon of the outermost .app bundle, so helper processes show their parent app's icon.
    private static func bundleIcon(for app: NSRunningApplication) -> NSImage? {
        guard let path = app.bundleURL?.path else { return app.icon }
        let appPath = path.range(of: ".app/").map { String(path[..<$0.lowerBound]) + ".app" } ?? path
        if let cached = iconCache[appPath] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: appPath)
        icon.size = NSSize(width: 128, height: 128)
        iconCache[appPath] = icon
        return icon
    }

    /// Helper processes (e.g. Passwords' menu bar extra) take the name of the app that ships them.
    private static func displayName(for app: NSRunningApplication) -> String {
        guard let path = app.bundleURL?.path, let range = path.range(of: ".app/") else { return app.localizedName ?? "App" }
        return FileManager.default.displayName(atPath: String(path[..<range.lowerBound]) + ".app")
            .replacingOccurrences(of: ".app", with: "")
    }

    private static func symbol(for identifier: String) -> String {
        let map: [(String, String)] = [
            ("focus", "moon.fill"), ("battery", "battery.75percent"), ("controlcenter", "switch.2"),
            ("clock", "clock.fill"), ("wifi", "wifi"), ("bluetooth", "wave.3.right"),
            ("sound", "speaker.wave.2.fill"), ("volume", "speaker.wave.2.fill"), ("airdrop", "airplayaudio"),
            ("screenmirroring", "rectangle.on.rectangle"), ("display", "sun.max.fill"), ("spotlight", "magnifyingglass"),
            ("siri", "waveform"), ("user", "person.crop.circle.fill"), ("textinput", "keyboard.fill"),
            ("nowplaying", "play.fill"), ("vpn", "lock.shield.fill"), ("timemachine", "clock.arrow.circlepath"),
            ("weather", "cloud.sun.fill"), ("accessibility", "accessibility"), ("keyboard", "keyboard.fill"),
        ]
        let lower = identifier.lowercased()
        return map.first { lower.contains($0.0) }?.1 ?? "circle.grid.2x2.fill"
    }

    /// Dominant color of an icon, used to tint the hover glow.
    private static func averageColor(_ image: NSImage) -> NSColor {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .white }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let alpha = max(CGFloat(pixel[3]) / 255, 0.01)
        let color = NSColor(red: CGFloat(pixel[0]) / 255 / alpha, green: CGFloat(pixel[1]) / 255 / alpha,
                            blue: CGFloat(pixel[2]) / 255 / alpha, alpha: 1)
        let hsb = color.usingColorSpace(.deviceRGB) ?? color
        return NSColor(hue: hsb.hueComponent, saturation: min(hsb.saturationComponent * 1.4, 1),
                       brightness: max(hsb.brightnessComponent, 0.75), alpha: 1)
    }
}
