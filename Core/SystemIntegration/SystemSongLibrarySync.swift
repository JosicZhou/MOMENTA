import Foundation

actor SystemSongLibrarySync {
    static let shared = SystemSongLibrarySync()

    private let musicDatabase = MusicDatabaseService.shared
    private let profileService = ProfileService.shared
    private let snapshotStore = SystemSongSnapshotStore()

    func refresh() async {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else {
            snapshotStore.clear()
            return
        }

        do {
            async let mineSongs = musicDatabase.fetchMineSongs(userId: userId)
            async let memorySongs = musicDatabase.fetchMemorySongs(userId: userId)
            async let cocreateSongs = musicDatabase.fetchCocreateSongs(userId: userId)
            async let sharedSongs = musicDatabase.fetchSharedSongs(userId: userId)
            async let sharedSenderNames = profileService.fetchSharedSenderNames(toUserId: userId)
            async let latestFavoriteMusicId = profileService.fetchLatestFavoriteMusicId(userId: userId)

            let resolvedSharedSenderNames = try await sharedSenderNames
            let resolvedLatestFavoriteMusicId = try await latestFavoriteMusicId

            let snapshots =
                (try await mineSongs).map { SystemSongSnapshot.from($0, kind: .mine) } +
                (try await memorySongs).map { SystemSongSnapshot.from($0, kind: .memory) } +
                (try await cocreateSongs).map { SystemSongSnapshot.from($0, kind: .cocreate) } +
                (try await sharedSongs).map {
                    SystemSongSnapshot.from(
                        $0,
                        kind: .shared,
                        subtitle: resolvedSharedSenderNames[$0.id] ?? "Friend"
                    )
                }

            snapshotStore.save(snapshots)
            snapshotStore.setLatestFavoriteSongID(resolvedLatestFavoriteMusicId)
        } catch {
            print("⚠️ [SystemSongLibrarySync] Failed to refresh song snapshots: \(error.localizedDescription)")
        }
    }
}
