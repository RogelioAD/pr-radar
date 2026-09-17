import SwiftUI

/// A pull request's link, offered as both a URL and plain text.
///
/// Dragging a bare `URL` exports only `public.url`. A browser takes that, but a
/// terminal has nothing to do with it — it wants text to insert at the cursor,
/// so the drop is refused and the drag looks broken. Exporting both lets each
/// receiver take what it understands, URL first so a browser still gets a real
/// link rather than a string it has to re-parse.
struct PRLink: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.url)
        ProxyRepresentation(exporting: \.url.absoluteString)
    }
}
