import Foundation

/// ↑↑↓↓←→←→BA.
///
/// Watches key codes as they go past and says when the whole thing has been
/// typed. It observes rather than consumes: the arrows still move the
/// selection while they are being counted, because a sequence that swallowed
/// the keys it was watching would break the list for anybody who happened to
/// press up twice.
public struct Konami: Equatable, Sendable {

    /// Virtual key codes, which is the one place in the drawer that reads
    /// codes rather than characters. The sequence is a *shape* on the keyboard
    /// — up up down down, left right left right — and on a layout where `b`
    /// and `a` have moved, the shape is still what people will type.
    public static let sequence: [UInt16] = [
        126, 126,            // ↑ ↑
        125, 125,            // ↓ ↓
        123, 124, 123, 124,  // ← → ← →
        11, 0,               // B A
    ]

    private var matched = 0

    public init() {}

    /// How far in we are, for anyone who wants to know. Mostly here so the
    /// progress can be asserted rather than inferred from the payoff.
    public var progress: Int { matched }

    /// Feeds one key press in. Returns true on the press that completes it.
    ///
    /// A wrong key resets to zero — except when it is the *first* key of the
    /// sequence, which starts a fresh attempt rather than throwing it away.
    /// Without that, ↑↑↑↓↓… never matches, and three ups is what you get when
    /// somebody is holding the key down.
    public mutating func accept(keyCode: UInt16) -> Bool {
        if keyCode == Self.sequence[matched] {
            matched += 1
        } else if keyCode == Self.sequence[0] {
            matched = 1
        } else {
            matched = 0
            return false
        }
        guard matched == Self.sequence.count else { return false }
        matched = 0
        return true
    }

    public mutating func reset() { matched = 0 }
}
