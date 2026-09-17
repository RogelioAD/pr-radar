import AppKit

/// The pasteboard has to be cleared before it is written, or the new contents
/// are appended to whatever an earlier write left behind and the paste is
/// whichever type the receiver happens to ask for first.
enum Clipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
