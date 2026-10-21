import AppKit
import Carbon.HIToolbox

/// The global shortcuts Notchless offers. Carbon hotkeys need no extra permission.
enum Shortcut: String, CaseIterable, Identifiable {
    case none, optionCommandN, controlOptionSpace, controlOptionCommandM

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .optionCommandN: "⌥⌘N"
        case .controlOptionSpace: "⌃⌥Space"
        case .controlOptionCommandM: "⌃⌥⌘M"
        }
    }

    fileprivate var keyAndModifiers: (UInt32, UInt32)? {
        switch self {
        case .none: nil
        case .optionCommandN: (UInt32(kVK_ANSI_N), UInt32(optionKey | cmdKey))
        case .controlOptionSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .controlOptionCommandM: (UInt32(kVK_ANSI_M), UInt32(controlKey | optionKey | cmdKey))
        }
    }
}

final class Hotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            Unmanaged<Hotkey>.fromOpaque(context!).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: Shortcut) {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        guard let (key, modifiers) = shortcut.keyAndModifiers else { return }
        RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: OSType(0x4E544C53), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }
}
