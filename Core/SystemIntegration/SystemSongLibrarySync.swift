import Foundation

actor SystemSongLibrarySync {
    static let shared = SystemSongLibrarySync()

    private let musicDatabase = MusicDatabaseService.shared
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

            let snapshots =
                (try await mineSongs).map { SystemSongSnapshot.from($0, kind: .mine) } +
                (try await memorySongs).map { SystemSongSnapshot.from($0, kind: .memory) } +
                (try await cocreateSongs).map { SystemSongSnapshot.from($0, kind: .cocreate) } +
                (try await sharedSongs).map { SystemSongSnapshot.from($0, kind: .shared) }

            snapshotStore.save(snapshots)
        } catch {
            print("⚠️ [SystemSongLibrarySync] Failed to refresh song snapshots: \(error.localizedDescription)")
        }
    }
}
