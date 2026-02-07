//
//  ProfileService.swift
//  MOMENTA
//
//  个人主页与歌单相关后端：收藏、分享列表、删除/移除。
//  依赖 MusicDatabaseService 拉取 Mine/Cocreate/Shared 歌曲；
//  收藏与分享表由本类直接读写。
//

import Foundation
import Supabase

class ProfileService {
    static let shared = ProfileService()
    private let client = SupabaseConfig.client
    private let musicDb = MusicDatabaseService.shared

    private init() {}

    // MARK: - 拉取歌单数据

    /// 收藏歌单：通过 RPC 返回完整歌曲列表
    func fetchFavoriteSongs(userId: UUID) async throws -> [GeneratedMusic] {
        let response = try await client
            .rpc("get_favorite_songs_for_user", params: ["p_user_id": userId.uuidString.lowercased()])
            .execute()
        return musicDb.decodeMusicList(from: response.data)
    }

    /// 收藏的 music_id 集合（用于判断某首歌是否已收藏）
    func fetchFavoriteMusicIds(userId: UUID) async throws -> Set<String> {
        let response = try await client
            .from("user_favorites")
            .select("music_id")
            .eq("user_id", value: userId.uuidString.lowercased())
            .execute()
        let decoder = JSONDecoder()
        struct Row: Decodable { let music_id: String }
        let rows = (try? decoder.decode([Row].self, from: response.data)) ?? []
        return Set(rows.map(\.music_id))
    }

    // MARK: - 收藏

    /// 加入收藏（Favorites）。ownerId 为该歌曲在 music_generations 的 user_id。
    func addFavorite(userId: UUID, musicId: String, ownerId: UUID) async throws {
        let record: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString.lowercased()),
            "music_id": .string(musicId),
            "owner_id": .string(ownerId.uuidString.lowercased()),
            "created_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]
        try await client
            .from("user_favorites")
            .insert(record)
            .execute()
    }

    /// 取消收藏（从 Favorites 移除）
    func removeFavorite(userId: UUID, musicId: String) async throws {
        try await client
            .from("user_favorites")
            .delete()
            .eq("user_id", value: userId.uuidString.lowercased())
            .eq("music_id", value: musicId)
            .execute()
    }

    // MARK: - Shared 歌单：移除「分享给我的」某条

    /// 从「Shared」中移除一条（仅删除 music_shared 记录，不删歌曲本身）
    func removeShared(toUserId: UUID, musicId: String) async throws {
        try await client
            .from("music_shared")
            .delete()
            .eq("to_user_id", value: toUserId.uuidString.lowercased())
            .eq("music_id", value: musicId)
            .execute()
    }

    /// 分享一首歌给某用户（供 Share 功能调用）
    func shareMusic(fromUserId: UUID, toUserId: UUID, musicId: String) async throws {
        let record: [String: AnyJSON] = [
            "from_user_id": .string(fromUserId.uuidString.lowercased()),
            "to_user_id": .string(toUserId.uuidString.lowercased()),
            "music_id": .string(musicId),
            "created_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]
        try await client
            .from("music_shared")
            .insert(record)
            .execute()
    }
}
