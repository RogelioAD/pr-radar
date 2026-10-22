import AppKit
import Carbon.HIToolbox
import PRRadarCore

/// A system-wide keyboard shortcut that opens the drawer.
///
/// Carbon's `RegisterEventHotKey`, which is the part of Carbon macOS has never
/// replaced and never removed. The modern-looking alternative,
/// `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`, needs
/// **Accessibility** permission — it is a keylogger with a narrow filter, and
/// the system rightly treats it as one. This app refuses Screen Recording for
/// the sake of an icon colour; asking to watch every keystroke on the machine
/// so that a panel can open would be a far worse bargain for a convenience.
///
/// `RegisterEventHotKey` asks the window server to deliver one chord and
/// nothing else, so there is no prompt and nothing to grant.
///
/// The chord itself lives in `HotKeyChord`, in the core, where its parsing can
/// be tested without a window server.
final class HotKey {

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Held statically because the C callback has nowhere to put a context
    /// pointer that would outlive it. One hot key is one app's worth of them.
    private static var onPress: (() -> Void)?

    let chord: HotKeyChord

    init?(chord: HotKeyChord, onPress: @escaping () -> Void) {
        self.chord = chord
        Self.onPress = onPress

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            // The id is checked rather than assumed: another handler in this
            // process would otherwise see our chord and we would see theirs.
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == HotKey.signature else { return noErr }
            DispatchQueue.main.async { HotKey.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)
        guard installed == noErr else { return nil }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let registered = RegisterEventHotKey(chord.keyCode, chord.modifiers, id,
                                             GetApplicationEventTarget(), 0, &reference)
        // A chord another app already holds fails here rather than silently
        // never firing, which is what lets the caller say so in the log.
        guard registered == noErr, reference != nil else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    /// 'PRRD', spelled out because `OSType("PRRD")` is not a thing.
    private static let signature: OSType =
        Array("PRRD".utf8).reduce(OSType(0)) { ($0 << 8) | OSType($1) }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        Self.onPress = nil
    }
}
