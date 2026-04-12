import AppIntents
import SwiftUI
import WidgetKit

struct SongWidgetSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Song"
    static var description = IntentDescription("Select a MOMENTA song for this widget.")

    @Parameter(title: "Song")
    var song: SongEntity?
}

struct SongWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SystemSongSnapshot
    let isPlaceholder: Bool
}

struct SongWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SongWidgetEntry {
        SongWidgetEntry(date: .now, snapshot: .placeholder, isPlaceholder: true)
    }

    func snapshot(for configuration: SongWidgetSelectionIntent, in context: Context) async -> SongWidgetEntry {
        SongWidgetEntry(
            date: .now,
            snapshot: resolvedSnapshot(for: configuration.song),
            isPlaceholder: configuration.song == nil
        )
    }

    func timeline(for configuration: SongWidgetSelectionIntent, in context: Context) async -> Timeline<SongWidgetEntry> {
        let entry = SongWidgetEntry(
            date: .now,
            snapshot: resolvedSnapshot(for: configuration.song),
            isPlaceholder: configuration.song == nil
        )
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 30)))
    }

    private func resolvedSnapshot(for entity: SongEntity?) -> SystemSongSnapshot {
        let store = SystemSongSnapshotStore()
        if let entity, let snapshot = store.snapshot(taskId: entity.id) {
            return snapshot
        }
        if let featured = store.featuredSnapshot() {
            return featured
        }
        return store.load().first ?? .placeholder
    }
}

struct SongWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "MomentaSongWidget",
            intent: SongWidgetSelectionIntent.self,
            provider: SongWidgetProvider()
        ) { entry in
            SongWidgetView(entry: entry)
        }
        .configurationDisplayName("Song")
        .description("Pin one of your songs or a shared song to Home Screen or Lock Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct SongWidgetView: View {
    let entry: SongWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallBody
            case .systemMedium:
                mediumBody
            case .accessoryRectangular:
                lockScreenBody
            default:
                mediumBody
            }
        }
        .widgetURL(entry.snapshot.deepLinkURL)
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetArtwork(size: 120, cornerRadius: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(entry.snapshot.widgetSubtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumBody: some View {
        HStack(spacing: 14) {
            widgetArtwork(size: 104, cornerRadius: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.snapshot.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(entry.snapshot.widgetSubtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Label(entry.snapshot.kind.title, systemImage: entry.snapshot.kind.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var lockScreenBody: some View {
        HStack(spacing: 10) {
            widgetArtwork(size: 42, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(entry.snapshot.kind.title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func widgetArtwork(size: CGFloat, cornerRadius: CGFloat) -> some View {
        if let imageURL = entry.snapshot.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    fallbackArtwork(cornerRadius: cornerRadius)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    fallbackArtwork(cornerRadius: cornerRadius)
                @unknown default:
                    fallbackArtwork(cornerRadius: cornerRadius)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            fallbackArtwork(cornerRadius: cornerRadius)
                .frame(width: size, height: size)
        }
    }

    private func fallbackArtwork(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(uiColor: .systemGray4),
                        Color(uiColor: .systemGray5)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
            }
    }
}
