import Foundation
import Carbon.HIToolbox

/// A keyboard chord, as a key code and modifier mask.
///
/// Here rather than beside the registration it feeds, because the two halves
/// are different kinds of thing: reading `opt+shift+r` out of a defaults
/// string and spelling it back as `⌥⇧R` is logic with answers worth pinning
/// down, where `RegisterEventHotKey` is a call to the window server that
/// either works or does not.
public struct HotKeyChord: Equatable, Sendable {
    public let keyCode: UInt32
    /// Carbon modifier mask — `cmdKey`, `optionKey`, `shiftKey`, `controlKey`.
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌥⇧R. Chosen to be reachable one-handed and unlikely to be taken: the
    /// single-modifier combinations belong to whatever you are working in,
    /// and this shortcut fires *while* you are working in it.
    public static let `default` = HotKeyChord(keyCode: UInt32(kVK_ANSI_R),
                                              modifiers: UInt32(optionKey | shiftKey))

    /// Reads `opt+shift+r`, so a clash can be settled without a rebuild.
    ///
    /// nil for anything it cannot read, which the caller turns into the
    /// default. Refusing a chord with no modifier is the one rule worth
    /// stating: a bare letter registered system-wide would swallow that key
    /// in every app on the machine.
    public static func parse(_ raw: String?) -> HotKeyChord? {
        guard let raw, !raw.isEmpty else { return nil }
        var modifiers: UInt32 = 0
        var key: UInt32?
        for part in raw.lowercased().split(separator: "+") {
            switch part.trimmingCharacters(in: .whitespaces) {
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case "opt", "option", "alt": modifiers |= UInt32(optionKey)
            case "shift": modifiers |= UInt32(shiftKey)
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            case let letter where letter.count == 1:
                guard let code = code(for: Character(letter)) else { return nil }
                key = code
            default: return nil
            }
        }
        guard let key, modifiers != 0 else { return nil }
        return HotKeyChord(keyCode: key, modifiers: modifiers)
    }

    /// Letters and digits only. A shortcut you type into a defaults string is
    /// one somebody can get wrong, and the narrow map is what makes a typo
    /// fail loudly rather than quietly register something else.
    public static func code(for character: Character) -> UInt32? {
        let keys: [Character: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        ]
        return keys[character].map(UInt32.init)
    }

    /// `⌥⇧R`, in the order macOS writes modifiers.
    public var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + (Self.name(for: keyCode) ?? "?")
    }

    public static func name(for code: UInt32) -> String? {
        for character in "abcdefghijklmnopqrstuvwxyz0123456789"
        where Self.code(for: character) == code {
            return String(character).uppercased()
        }
        return nil
    }
}
