#if canImport(AppIntents)
import AppIntents
import Foundation

struct SongEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Song")
    }

    static var defaultQuery = SongEntityQuery()

    let id: String
    let title: String
    let subtitle: String
    let imageURLString: String?
    let kindRawValue: String

    init(snapshot: SystemSongSnapshot) {
        self.id = snapshot.id
        self.title = snapshot.title
        self.subtitle = snapshot.widgetSubtitle
        self.imageURLString = snapshot.imageURLString
        self.kindRawValue = snapshot.kind.rawValue
    }

    var snapshot: SystemSongSnapshot? {
        SystemSongSnapshotStore().snapshot(taskId: id)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: LocalizedStringResource(stringLiteral: subtitle)
        )
    }

    var openURL: URL {
        snapshot?.deepLinkURL ?? URL(string: "momenta://song/\(id)")!
    }

    var autoplayURL: URL {
        snapshot?.autoplayDeepLinkURL ?? URL(string: "momenta://song/\(id)?autoplay=1")!
    }
}

struct SongEntityQuery: EntityQuery {
    func entities(for identifiers: [SongEntity.ID]) async throws -> [SongEntity] {
        let snapshots = SystemSongSnapshotStore().load()
        let map = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, SongEntity(snapshot: $0)) })
        return identifiers.compactMap { map[$0] }
    }

    func suggestedEntities() async throws -> [SongEntity] {
        SystemSongSnapshotStore().load().prefix(12).map(SongEntity.init(snapshot:))
    }
}

#if !APP_EXTENSION
struct OpenSongIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Song"
    static var description = IntentDescription("Open a MOMENTA song in the app.")
    static var openAppWhenRun = true

    @Parameter(title: "Song")
    var song: SongEntity

    init() {}

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(song.openURL))
    }
}

struct SetWidgetSongIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Widget Song"
    static var description = IntentDescription("Choose which MOMENTA song appears as the default song in widgets.")

    @Parameter(title: "Song")
    var song: SongEntity

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = song.snapshot else {
            return .result(dialog: "That song is no longer available for widgets.")
        }
        SystemSongSnapshotStore().pin(snapshot)
        return .result(dialog: IntentDialog("Set \(snapshot.title) for MOMENTA widgets."))
    }
}

struct PlaySongIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Song"
    static var description = IntentDescription("Open MOMENTA and start playing a song.")
    static var openAppWhenRun = true

    @Parameter(title: "Song")
    var song: SongEntity

    init() {}

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(song.autoplayURL))
    }
}

#endif
#endif
