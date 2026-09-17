import SwiftUI
import PRRadarCore

struct RowView: View {
    let item: ReviewItem
    let now: Date
    let onOpen: () -> Void

    @State private var hovering = false

    private var staleness: Staleness { Staleness.of(item.pingedAt, now: now) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(staleness.tint)
                .frame(width: 3)
                .clipShape(Capsule())

            avatar

            VStack(alignment: .leading, spacing: 3) {
                // Underlined while the row is hovered, so it reads as the
                // link it is. Driven by the row rather than by a hover on the
                // text itself: the whole row opens the PR, and a hover tracked
                // on the Text proved unreliable where the row's is not.
                Text(TitleText.attributed(item.title, underlined: hovering))
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    Text("#\(item.number)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(item.repoShortName)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    if item.isDraft {
                        Text("draft")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.18), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(item.authorLogin)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(TimeAgo.short(since: item.pingedAt, now: now))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(staleness.tint)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(staleness.tint.opacity(0.14), in: Capsule())
                .help("Review requested \(TimeAgo.long(since: item.pingedAt, now: now))")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Color.primary.opacity(0.07) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .draggable(item.url) {
            Text(item.title).font(.system(size: 12)).padding(6)
        }
        .contextMenu {
            Button("Open in Browser") { onOpen() }
            Button("Copy Link") { Clipboard.copy(item.url.absoluteString) }
            Button("Copy Title") { Clipboard.copy(item.title) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), pull request \(item.number) "
                            + "in \(item.repoShortName) by \(item.authorLogin), "
                            + "requested \(TimeAgo.long(since: item.pingedAt, now: now))")
        .accessibilityAddTraits(.isButton)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: RowHeightsKey.self,
                                       value: ["reviews:\(item.id)": geometry.size.height])
            }
        )
    }

    private var avatar: some View {
        AsyncImage(url: item.authorAvatarURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Circle().fill(Color.secondary.opacity(0.25))
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
    }
}
