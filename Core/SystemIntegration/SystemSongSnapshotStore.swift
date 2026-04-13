import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum SystemIntegrationConfig {
    static let appGroupIdentifier = "group.com.momenta.ai.music.shared"
    static let songSnapshotKey = "momenta.system.song-snapshots"
    static let featuredSongIDKey = "momenta.system.featured-song-id"
    static let latestFavoriteSongIDKey = "momenta.system.latest-favorite-song-id"
    static let currentPlaybackSongIDKey = "momenta.system.current-playback-song-id"
    static let currentPlaybackIsPlayingKey = "momenta.system.current-playback-is-playing"
}

struct SystemSongSnapshotStore {
    private let defaults = UserDefaults(suiteName: SystemIntegrationConfig.appGroupIdentifier)

    func load() -> [SystemSongSnapshot] {
        guard let defaults,
              let data = defaults.data(forKey: SystemIntegrationConfig.songSnapshotKey),
              let songs = try? JSONDecoder().decode([SystemSongSnapshot].self, from: data) else {
            return []
        }
        return songs.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ songs: [SystemSongSnapshot]) {
        guard let defaults else { return }
        let uniqueSongs = uniqued(songs)
        guard let data = try? JSONEncoder().encode(uniqueSongs) else { return }
        defaults.set(data, forKey: SystemIntegrationConfig.songSnapshotKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: SystemIntegrationConfig.songSnapshotKey)
        defaults.removeObject(forKey: SystemIntegrationConfig.featuredSongIDKey)
        defaults.removeObject(forKey: SystemIntegrationConfig.latestFavoriteSongIDKey)
        defaults.removeObject(forKey: SystemIntegrationConfig.currentPlaybackSongIDKey)
        defaults.removeObject(forKey: SystemIntegrationConfig.currentPlaybackIsPlayingKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    func snapshot(taskId: String) -> SystemSongSnapshot? {
        load().first { $0.id == taskId }
    }

    func featuredSongID() -> String? {
        defaults?.string(forKey: SystemIntegrationConfig.featuredSongIDKey)
    }

    func featuredSnapshot() -> SystemSongSnapshot? {
        guard let featuredSongID = featuredSongID() else { return nil }
        return snapshot(taskId: featuredSongID)
    }

    func latestSharedSnapshot() -> SystemSongSnapshot? {
        load().first { $0.kind == .shared }
    }

    func latestFavoriteSongID() -> String? {
        defaults?.string(forKey: SystemIntegrationConfig.latestFavoriteSongIDKey)
    }

    func latestFavoriteSnapshot() -> SystemSongSnapshot? {
        guard let latestFavoriteSongID = latestFavoriteSongID() else { return nil }
        return snapshot(taskId: latestFavoriteSongID)
    }

    func currentPlaybackSongID() -> String? {
        defaults?.string(forKey: SystemIntegrationConfig.currentPlaybackSongIDKey)
    }

    func currentPlaybackIsPlaying() -> Bool {
        defaults?.bool(forKey: SystemIntegrationConfig.currentPlaybackIsPlayingKey) ?? false
    }

    func updateCurrentPlayback(songID: String?, isPlaying: Bool) {
        guard let defaults else { return }
        if let songID, !songID.isEmpty {
            defaults.set(songID, forKey: SystemIntegrationConfig.currentPlaybackSongIDKey)
        } else {
            defaults.removeObject(forKey: SystemIntegrationConfig.currentPlaybackSongIDKey)
        }
        defaults.set(isPlaying, forKey: SystemIntegrationConfig.currentPlaybackIsPlayingKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    func setLatestFavoriteSongID(_ id: String?) {
        guard let defaults else { return }
        if let id, !id.isEmpty {
            defaults.set(id, forKey: SystemIntegrationConfig.latestFavoriteSongIDKey)
        } else {
            defaults.removeObject(forKey: SystemIntegrationConfig.latestFavoriteSongIDKey)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    func pin(_ snapshot: SystemSongSnapshot) {
        var songs = load().filter { $0.id != snapshot.id }
        songs.append(snapshot)
        save(songs)
        defaults?.set(snapshot.id, forKey: SystemIntegrationConfig.featuredSongIDKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func uniqued(_ songs: [SystemSongSnapshot]) -> [SystemSongSnapshot] {
        var seen = Set<String>()
        return songs
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seen.insert($0.id).inserted }
    }
}
