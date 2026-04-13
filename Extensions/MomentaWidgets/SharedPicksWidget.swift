import AppIntents
import SwiftUI
import WidgetKit

struct SharedPicksWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Shared Picks"
    static var description = IntentDescription("Automatically show the latest song shared with you.")
}

struct SharedPicksWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SystemSongSnapshot?
    let artworkData: Data?
    let isPlaying: Bool
}

struct SharedPicksWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SharedPicksWidgetEntry {
        SharedPicksWidgetEntry(date: .now, snapshot: .placeholder, artworkData: nil, isPlaying: false)
    }

    func snapshot(for configuration: SharedPicksWidgetIntent, in context: Context) async -> SharedPicksWidgetEntry {
        await makeEntry()
    }

    func timeline(for configuration: SharedPicksWidgetIntent, in context: Context) async -> Timeline<SharedPicksWidgetEntry> {
        let entry = await makeEntry()
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 15)))
    }

    private func makeEntry() async -> SharedPicksWidgetEntry {
        let store = SystemSongSnapshotStore()
        let snapshot = store.latestSharedSnapshot() ?? store.latestFavoriteSnapshot()
        let artworkData = await fetchArtworkData(for: snapshot)
        let isPlaying = snapshot?.id == store.currentPlaybackSongID() && store.currentPlaybackIsPlaying()
        return SharedPicksWidgetEntry(date: .now, snapshot: snapshot, artworkData: artworkData, isPlaying: isPlaying)
    }

    private func fetchArtworkData(for snapshot: SystemSongSnapshot?) async -> Data? {
        guard let url = snapshot?.imageURL else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } catch {
            return nil
        }
    }
}

struct SharedPicksWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "MomentaSharedPicksWidget",
            intent: SharedPicksWidgetIntent.self,
            provider: SharedPicksWidgetProvider()
        ) { entry in
            SharedPicksWidgetView(entry: entry)
        }
        .configurationDisplayName("Shared Picks")
        .description("Keep the latest shared pick or favorite on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct SharedPicksWidgetView: View {
    let entry: SharedPicksWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                SharedPicksSnapshotView(
                    snapshot: snapshot,
                    artworkData: entry.artworkData,
                    family: family,
                    isPlaying: entry.isPlaying
                )
                    .widgetURL(snapshot.deepLinkURL)
            } else {
                SharedPicksEmptyStateView(family: family)
                    .widgetURL(URL(string: "momenta://share/invitations")!)
            }
        }
        .containerBackground(for: .widget) {
            SharedPicksWidgetBackground(artworkData: entry.artworkData)
        }
    }
}

private struct SharedPicksSnapshotView: View {
    let snapshot: SystemSongSnapshot
    let artworkData: Data?
    let family: WidgetFamily
    let isPlaying: Bool

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallBody
            case .systemMedium:
                mediumBody
            default:
                mediumBody
            }
        }
    }

    private var smallBody: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                widgetArtwork(size: 74, cornerRadius: 18)

                Spacer(minLength: 10)

                Text(snapshot.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(roleLine)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Link(destination: snapshot.autoplayDeepLinkURL) {
                    SharedPicksPlayPill(compact: true, isPlaying: isPlaying)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            badgeBubble
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
    }

    private var mediumBody: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 16) {
                widgetArtwork(size: 112, cornerRadius: 24)

                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(roleLine)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                        .padding(.top, 6)

                    Spacer(minLength: 0)

                    Link(destination: snapshot.autoplayDeepLinkURL) {
                        SharedPicksPlayPill(compact: false, isPlaying: isPlaying)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            badgeBubble
                .padding(.top, 10)
                .padding(.trailing, 10)
        }
    }

    @ViewBuilder
    private func widgetArtwork(size: CGFloat, cornerRadius: CGFloat) -> some View {
        if let artworkData, let uiImage = UIImage(data: artworkData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            fallbackArtwork(cornerRadius: cornerRadius)
                .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private func fallbackArtwork(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
            }
    }

    private var badgeBubble: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.1))
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                }

            Image(systemName: badgeSymbolName)
                .font(.system(size: family == .systemSmall ? 10 : 11, weight: .semibold))
                .foregroundStyle(accentColor)
        }
        .frame(width: family == .systemSmall ? 24 : 28, height: family == .systemSmall ? 24 : 28)
    }

    private var isShared: Bool { snapshot.kind == .shared }

    private var roleLine: String {
        if isShared {
            return snapshot.sharedByLine ?? "Shared with you"
        }
        return "From Favorites"
    }

    private var badgeSymbolName: String {
        isShared ? "person.2.fill" : "heart.fill"
    }

    private var accentColor: Color {
        isShared
            ? Color(red: 1.0, green: 0.33, blue: 0.46)
            : Color(red: 1.0, green: 0.42, blue: 0.55)
    }
}

private struct SharedPicksEmptyStateView: View {
    let family: WidgetFamily

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 0) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .frame(width: 74, height: 74)

                        Spacer(minLength: 10)

                        Text("Shared Picks")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("Waiting for a song")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))

                        Spacer(minLength: 8)

                        SharedPicksPlayPill(compact: true, title: "Open")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                            }

                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.33, blue: 0.46))
                    }
                    .frame(width: 24, height: 24)
                    .padding(.top, 8)
                    .padding(.trailing, 8)
                }

            case .systemMedium:
                ZStack(alignment: .topTrailing) {
                    HStack(alignment: .top, spacing: 16) {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        .frame(width: 112, height: 112)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("No shared songs yet")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            Text("The latest song from a friend will appear here automatically.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(3)
                                .padding(.top, 6)

                            Spacer(minLength: 0)

                            SharedPicksPlayPill(compact: false, title: "Open")
                        }
                        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                            }

                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.33, blue: 0.46))
                    }
                    .frame(width: 28, height: 28)
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                }

            default:
                EmptyView()
            }
        }
    }
}

private struct SharedPicksPlayPill: View {
    let compact: Bool
    var title: String = "Play"
    var isPlaying: Bool = false

    var body: some View {
        Label(isPlaying ? "Playing" : title, systemImage: isPlaying ? "speaker.wave.2.fill" : "play.fill")
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 11 : 13)
            .padding(.vertical, compact ? 7 : 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
                    }
            )
    }
}

private struct SharedPicksWidgetBackground: View {
    let artworkData: Data?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.15, blue: 0.17),
                    Color(red: 0.08, green: 0.08, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let artworkData, let uiImage = UIImage(data: artworkData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .saturation(1.12)
                    .blur(radius: 34)
                    .scaleEffect(1.28)
                    .opacity(0.58)
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.44)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
