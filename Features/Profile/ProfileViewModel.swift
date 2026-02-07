//
//  ProfileViewModel.swift
//  MOMENTA
//
//  Profile 模块的 ViewModel，统一管理所有歌单数据与歌曲操作。
//  职责包括：
//  - 持有并维护所有歌单（5 个默认歌单 + 用户自建歌单）
//  - 提供歌曲操作方法：删除歌曲、从歌单移除、收藏/取消收藏
//  - 管理每个歌单独立的排序状态（Sort by date / A-Z）
//  - 数据变更后自动同步各歌单（如删除一首歌后 All Music 与对应歌单同步更新）
//
//  内含 PlaylistType、PlaylistDisplayInfo，供 Profile 歌单展示与导航使用。
//

import Foundation
import Combine

// MARK: - 歌单类型与展示信息

/// 系统默认歌单类型
enum PlaylistType: String, CaseIterable, Identifiable, Hashable {
    case all = "all"
    case mine = "mine"
    case cocreate = "cocreate"
    case shared = "shared"
    case favorites = "favorites"

    var id: String { rawValue }

    /// 展示名称（与 Profile 歌单网格一致）
    var displayName: String {
        switch self {
        case .all: return "All"
        case .mine: return "Mine"
        case .cocreate: return "Cocreate"
        case .shared: return "Shared"
        case .favorites: return "Favorites"
        }
    }

    /// SF Symbol 图标名
    var iconName: String {
        switch self {
        case .all: return "music.note"
        case .mine: return "person"
        case .cocreate: return "person.2"
        case .shared: return "square.and.arrow.up"
        case .favorites: return "heart"
        }
    }

    /// 系统歌单仅支持 Delete；Favorites（及未来自定义歌单）支持 Delete + Remove
    var supportsRemove: Bool {
        switch self {
        case .all, .mine, .cocreate, .shared: return false
        case .favorites: return true
        }
    }
}

/// 歌单在主页上的展示信息
struct PlaylistDisplayInfo {
    let type: PlaylistType
    let songCount: Int
    var songCountText: String { "\(songCount) song\(songCount == 1 ? "" : "s")" }
}

// MARK: - 排序选项

enum PlaylistSortOption: String, CaseIterable {
    case date = "Date"
    case aToZ = "A-Z"
}

@MainActor
class ProfileViewModel: ObservableObject {
    @Published private(set) var mineSongs: [GeneratedMusic] = []
    @Published private(set) var cocreateSongs: [GeneratedMusic] = []
    @Published private(set) var sharedSongs: [GeneratedMusic] = []
    @Published private(set) var favoriteSongs: [GeneratedMusic] = []
    @Published private(set) var favoriteIds: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var sortOptions: [PlaylistType: PlaylistSortOption] = [:]

    private let musicDb = MusicDatabaseService.shared
    private let profileService = ProfileService.shared

    init() {
        for type in PlaylistType.allCases {
            sortOptions[type] = .date
        }
    }

    // MARK: - 拉取

    func load() async {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let mine = musicDb.fetchMineSongs(userId: userId)
            async let cocreate = musicDb.fetchCocreateSongs(userId: userId)
            async let shared = musicDb.fetchSharedSongs(userId: userId)
            async let favorites = profileService.fetchFavoriteSongs(userId: userId)
            async let ids = profileService.fetchFavoriteMusicIds(userId: userId)
            (mineSongs, cocreateSongs, sharedSongs, favoriteSongs, favoriteIds) = try await (
                mine, cocreate, shared, favorites, ids
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 歌单展示

    /// 某歌单的展示用歌曲列表（已按当前排序）
    func songs(for type: PlaylistType) -> [PlaylistSongItem] {
        let list: [GeneratedMusic]
        switch type {
        case .all: list = allSongs
        case .mine: list = mineSongs
        case .cocreate: list = cocreateSongs
        case .shared: list = sharedSongs
        case .favorites: list = favoriteSongs
        }
        let sorted = applySort(list, for: type)
        return sorted.map { toPlaylistSongItem($0) }
    }

    /// 某歌单的歌曲数量
    func songCount(for type: PlaylistType) -> Int {
        switch type {
        case .all: return allSongs.count
        case .mine: return mineSongs.count
        case .cocreate: return cocreateSongs.count
        case .shared: return sharedSongs.count
        case .favorites: return favoriteSongs.count
        }
    }

    /// 歌单展示信息（名称、数量文案）
    func displayInfo(for type: PlaylistType) -> PlaylistDisplayInfo {
        PlaylistDisplayInfo(type: type, songCount: songCount(for: type))
    }

    /// 是否支持「从歌单移除」（Favorites / 自定义）
    func supportsRemove(for type: PlaylistType) -> Bool { type.supportsRemove }

    // MARK: - 排序

    func setSort(_ type: PlaylistType, _ option: PlaylistSortOption) {
        sortOptions[type] = option
    }

    func currentSort(for type: PlaylistType) -> PlaylistSortOption {
        sortOptions[type] ?? .date
    }

    // MARK: - 操作

    /// 删除歌曲（系统歌单：从库中删除；Favorites：取消收藏并视情况删库）
    func deleteSong(musicId: String, playlistType: PlaylistType) async {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else { return }
        do {
            switch playlistType {
            case .all, .mine, .cocreate:
                try await musicDb.deleteMusic(taskId: musicId, userId: userId)
                try await profileService.removeFavorite(userId: userId, musicId: musicId)
            case .shared:
                try await profileService.removeShared(toUserId: userId, musicId: musicId)
                try await profileService.removeFavorite(userId: userId, musicId: musicId)
            case .favorites:
                try await profileService.removeFavorite(userId: userId, musicId: musicId)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 从当前歌单移除（仅 Favorites：取消收藏）
    func removeFromPlaylist(musicId: String, playlistType: PlaylistType) async {
        guard playlistType.supportsRemove, let userId = await SupabaseService.shared.getCurrentUserId() else { return }
        do {
            try await profileService.removeFavorite(userId: userId, musicId: musicId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 收藏/取消收藏
    func toggleFavorite(musicId: String, ownerId: UUID?) async {
        guard let userId = await SupabaseService.shared.getCurrentUserId() else { return }
        let owner = ownerId ?? userId
        do {
            if favoriteIds.contains(musicId) {
                try await profileService.removeFavorite(userId: userId, musicId: musicId)
            } else {
                try await profileService.addFavorite(userId: userId, musicId: musicId, ownerId: owner)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private var allSongs: [GeneratedMusic] {
        var seen = Set<String>()
        return (mineSongs + cocreateSongs + sharedSongs).filter { seen.insert($0.id).inserted }
    }

    private func applySort(_ list: [GeneratedMusic], for type: PlaylistType) -> [GeneratedMusic] {
        let opt = sortOptions[type] ?? .date
        switch opt {
        case .date: return list.sorted { $0.createdAt > $1.createdAt }
        case .aToZ: return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private func toPlaylistSongItem(_ music: GeneratedMusic) -> PlaylistSongItem {
        PlaylistSongItem(
            id: music.id,
            title: music.title,
            duration: "—",
            artworkImage: nil,
            isLiked: favoriteIds.contains(music.id),
            ownerId: music.ownerId
        )
    }
}
