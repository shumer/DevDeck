import AppKit
import Carbon.HIToolbox
import DevDeckCore

/// One system-wide key combination, with both edges reported.
///
/// Carbon rather than `NSEvent.addGlobalMonitorForEvents`, which is the modern-looking way and
/// the wrong one here: a global key monitor is keylogging as far as macOS is concerned and needs
/// Input Monitoring, granted in System Settings, for a deck whose whole appeal is that it needs
/// nothing. `RegisterEventHotKey` asks for no permission, is still the API every launcher on this
/// machine uses, and is the only one that reports the key going **up** as well as down, which is
/// what lets the deck be summoned by holding rather than by toggling.
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void
    private let onRelease: () -> Void

    init?(
        combo: HotKeyCombo,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) {
        self.onPress = onPress
        self.onRelease = onRelease

        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()

        let installed = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, context in
                guard let context, let event else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                let kind = GetEventKind(event)
                // Back to the main queue: this is a Carbon dispatcher callback, and everything
                // it ends up touching is windows.
                DispatchQueue.main.async {
                    if kind == UInt32(kEventHotKeyPressed) {
                        hotKey.onPress()
                    } else {
                        hotKey.onRelease()
                    }
                }
                return noErr
            },
            types.count,
            &types,
            context,
            &handler
        )
        guard installed == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x44_44_4B_59), id: 1) // 'DDKY'
        let registered = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers.rawValue,
            id,
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        guard registered == noErr, reference != nil else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
