import SwiftUI

/// A PR title, underlined while hovered so it reads as the link it is.
///
/// The underline is carried as a text attribute rather than through
/// `Text.underline(_:)`. That modifier does not re-resolve when the flag it is
/// given is the only thing that changed, so hovering flipped the state and
/// nothing was drawn. Putting any second attribute beside it — a foreground
/// colour, say — made the underline appear, which is what gave the quirk away.
enum TitleText {
    static func attributed(_ text: String, underlined: Bool) -> AttributedString {
        var attributed = AttributedString(text)
        if underlined { attributed.underlineStyle = .single }
        return attributed
    }
}
