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

    /// 最近一次加入 Favorites 的歌曲 ID
    func fetchLatestFavoriteMusicId(userId: UUID) async throws -> String? {
        let response = try await client
            .from("user_favorites")
            .select("music_id")
            .eq("user_id", value: userId.uuidString.lowercased())
            .order("created_at", ascending: false)
            .limit(1)
            .execute()

        let decoder = JSONDecoder()
        struct Row: Decodable { let music_id: String }
        let rows = (try? decoder.decode([Row].self, from: response.data)) ?? []
        return rows.first?.music_id
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

    /// 我分享给别人的歌曲 ID 集合
    func fetchSharedMusicIdsSentByUser(userId: UUID) async throws -> Set<String> {
        let response = try await client
            .from("music_shared")
            .select("music_id")
            .eq("from_user_id", value: userId.uuidString.lowercased())
            .execute()

        let decoder = JSONDecoder()
        struct Row: Decodable { let music_id: String }
        let rows = (try? decoder.decode([Row].self, from: response.data)) ?? []
        return Set(rows.map(\.music_id))
    }

    /// 别人分享给我的歌曲，对应发送方名称
    func fetchSharedSenderNames(toUserId: UUID) async throws -> [String: String] {
        let sharedResponse = try await client
            .from("music_shared")
            .select("music_id, from_user_id, created_at")
            .eq("to_user_id", value: toUserId.uuidString.lowercased())
            .order("created_at", ascending: false)
            .execute()

        struct SharedRow: Decodable {
            let music_id: String
            let from_user_id: UUID
        }

        let decoder = JSONDecoder()
        let sharedRows = (try? decoder.decode([SharedRow].self, from: sharedResponse.data)) ?? []
        let senderIds = Array(Set(sharedRows.map { $0.from_user_id.uuidString.lowercased() }))
        guard !senderIds.isEmpty else { return [:] }

        let profilesResponse = try await client
            .from("profiles")
            .select("id, display_name")
            .in("id", values: senderIds)
            .execute()

        struct ProfileRow: Decodable {
            let id: UUID
            let display_name: String?
        }

        let profileRows = (try? decoder.decode([ProfileRow].self, from: profilesResponse.data)) ?? []
        let nameMap = Dictionary(uniqueKeysWithValues: profileRows.map {
            ($0.id.uuidString.lowercased(), ($0.display_name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? $0.display_name! : "Friend")
        })

        var mapping: [String: String] = [:]
        for row in sharedRows {
            if mapping[row.music_id] == nil {
                mapping[row.music_id] = nameMap[row.from_user_id.uuidString.lowercased()] ?? "Friend"
            }
        }
        return mapping
    }
}

struct FriendProfile: Identifiable, Codable, Hashable {
    let id: UUID
    let displayName: String?
    let avatarUrl: String?
    let friendCode: String?

    var resolvedName: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "User" : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case friendCode = "friend_code"
    }
}

struct FriendRequest: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let friendId: UUID
    let status: String
    let note: String?
    let createdAt: String?
    var senderName: String?
    var senderAvatarUrl: String?
    var senderFriendCode: String?

    var createdAtDate: Date {
        FriendDateParser.parse(createdAt) ?? .distantPast
    }

    enum CodingKeys: String, CodingKey {
        case id, status, note
        case userId = "user_id"
        case friendId = "friend_id"
        case createdAt = "created_at"
        case senderName = "sender_name"
        case senderAvatarUrl = "sender_avatar_url"
        case senderFriendCode = "sender_friend_code"
    }
}

struct SentRequest: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let friendId: UUID
    let status: String
    let note: String?
    let createdAt: String?
    let displayName: String?
    let avatarUrl: String?
    let friendCode: String?

    var resolvedName: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "User" : trimmed
    }

    var createdAtDate: Date {
        FriendDateParser.parse(createdAt) ?? .distantPast
    }

    enum CodingKeys: String, CodingKey {
        case id, status, note
        case userId = "user_id"
        case friendId = "friend_id"
        case createdAt = "created_at"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case friendCode = "friend_code"
    }
}

private enum FriendDateParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value)
    }
}

enum SendRequestResult {
    case sent
    case alreadyFriends
    case alreadyPending
    case cannotAddSelf
}

final class FriendService {
    static let shared = FriendService()
    private let client = SupabaseConfig.client
    private let localStore = FriendLocalStore()

    private init() {}

    func ensureProfile(userId: UUID, displayName: String?) async throws {
        try await client
            .rpc("upsert_profile", params: [
                "p_user_id": userId.uuidString.lowercased(),
                "p_display_name": displayName ?? "User"
            ])
            .execute()
    }

    // MARK: - Avatar

    func getMyAvatarUrl() async throws -> String? {
        guard let userId = try? await client.auth.session.user.id else { return nil }
        let response = try await client
            .from("profiles")
            .select("avatar_url")
            .eq("id", value: userId.uuidString.lowercased())
            .single()
            .execute()
        let row = try JSONDecoder().decode([String: String?].self, from: response.data)
        return row["avatar_url"] ?? nil
    }

    func updateAvatarUrl(_ url: String, userId: UUID) async throws {
        try await client
            .from("profiles")
            .update(["avatar_url": url] as [String: String])
            .eq("id", value: userId.uuidString.lowercased())
            .execute()
    }

    func clearAvatarUrl(userId: UUID) async throws {
        try await client
            .from("profiles")
            .update(["avatar_url": ""] as [String: String])
            .eq("id", value: userId.uuidString.lowercased())
            .execute()
    }

    func getMyFriendCode(displayName: String? = nil) async throws -> String {
        guard let userId = try? await client.auth.session.user.id else {
            throw FriendServiceError.notAuthenticated
        }
        let response = try await client
            .from("profiles")
            .select("friend_code")
            .eq("id", value: userId.uuidString.lowercased())
            .single()
            .execute()
        let row = try JSONDecoder().decode([String: String].self, from: response.data)
        if let code = row["friend_code"], !code.isEmpty {
            localStore.setFriendCode(code, displayName: displayName)
            return code
        }
        throw FriendServiceError.profileNotFound
    }

    func searchByFriendCode(_ code: String, displayName: String? = nil) async throws -> FriendProfile? {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedCode.isEmpty else { return nil }
        let myCode = try await getMyFriendCode(displayName: displayName)
        if normalizedCode == myCode.lowercased() {
            throw FriendServiceError.cannotAddSelf
        }

        let response = try await client
            .rpc("find_user_by_friend_code", params: ["p_code": normalizedCode])
            .execute()
        let results = try JSONDecoder().decode([FriendProfile].self, from: response.data)
        return results.first
    }

    func sendFriendRequest(to profile: FriendProfile, note: String?) async throws -> SendRequestResult {
        if let myCode = try? await getMyFriendCode(),
           myCode.lowercased() == profile.friendCode?.lowercased() {
            return .cannotAddSelf
        }

        guard let userId = try? await client.auth.session.user.id else {
            throw FriendServiceError.notAuthenticated
        }

        let params: [String: AnyJSON] = [
            "p_from_user_id": .string(userId.uuidString.lowercased()),
            "p_to_user_id": .string(profile.id.uuidString.lowercased()),
            "p_note": note.map { .string($0) } ?? .null
        ]

        let response = try await client
            .rpc("send_friend_request", params: params)
            .execute()
        let statusCode = (try? JSONDecoder().decode(String.self, from: response.data)) ?? "sent"
        switch statusCode {
        case "already_friends": return .alreadyFriends
        case "already_pending": return .alreadyPending
        case "cannot_add_self": return .cannotAddSelf
        default: return .sent
        }
    }

    func acceptRequest(_ friendshipId: UUID) async throws {
        try await client
            .from("friendships")
            .update(["status": "accepted"] as [String: String])
            .eq("id", value: friendshipId.uuidString.lowercased())
            .execute()
    }

    func declineRequest(_ friendshipId: UUID) async throws {
        try await client
            .from("friendships")
            .delete()
            .eq("id", value: friendshipId.uuidString.lowercased())
            .execute()
    }

    func cancelSentRequest(_ friendshipId: UUID) async throws {
        try await client
            .from("friendships")
            .delete()
            .eq("id", value: friendshipId.uuidString.lowercased())
            .execute()
    }

    func loadFriends() async throws -> [FriendProfile] {
        guard let userId = try? await client.auth.session.user.id else {
            throw FriendServiceError.notAuthenticated
        }
        let uid = userId.uuidString.lowercased()
        let response = try await client
            .from("friendships")
            .select("id, user_id, friend_id, status")
            .eq("status", value: "accepted")
            .or("user_id.eq.\(uid),friend_id.eq.\(uid)")
            .execute()

        struct Row: Decodable {
            let id: UUID
            let user_id: String
            let friend_id: String
        }
        let rows = try JSONDecoder().decode([Row].self, from: response.data)
        let friendIds = rows.map { $0.user_id == uid ? $0.friend_id : $0.user_id }
        guard !friendIds.isEmpty else { return [] }

        let profileResponse = try await client
            .from("profiles")
            .select("id, display_name, avatar_url, friend_code")
            .in("id", values: friendIds)
            .execute()

        struct ProfileRow: Decodable {
            let id: UUID
            let display_name: String?
            let avatar_url: String?
            let friend_code: String?
        }
        return try JSONDecoder().decode([ProfileRow].self, from: profileResponse.data).map {
            FriendProfile(
                id: $0.id,
                displayName: $0.display_name,
                avatarUrl: $0.avatar_url,
                friendCode: $0.friend_code
            )
        }
    }

    func loadPendingRequests() async throws -> [FriendRequest] {
        guard let userId = try? await client.auth.session.user.id else {
            throw FriendServiceError.notAuthenticated
        }
        let uid = userId.uuidString.lowercased()
        let response = try await client
            .from("friendships")
            .select("id, user_id, friend_id, status, note, created_at")
            .eq("friend_id", value: uid)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()

        var requests = try JSONDecoder().decode([FriendRequest].self, from: response.data)
        let senderIds = requests.map { $0.userId.uuidString.lowercased() }
        if !senderIds.isEmpty {
            let profileResponse = try await client
                .from("profiles")
                .select("id, display_name, avatar_url, friend_code")
                .in("id", values: senderIds)
                .execute()

            struct ProfileRow: Decodable {
                let id: UUID
                let display_name: String?
                let avatar_url: String?
                let friend_code: String?
            }
            let profiles = try JSONDecoder().decode([ProfileRow].self, from: profileResponse.data)
            let nameMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.display_name) })
            let avatarMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.avatar_url) })
            let codeMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.friend_code) })

            for index in requests.indices {
                requests[index].senderName = nameMap[requests[index].userId] ?? nil
                requests[index].senderAvatarUrl = avatarMap[requests[index].userId] ?? nil
                requests[index].senderFriendCode = codeMap[requests[index].userId] ?? nil
            }
        }
        return requests
    }

    func loadSentRequests() async throws -> [SentRequest] {
        guard let userId = try? await client.auth.session.user.id else {
            throw FriendServiceError.notAuthenticated
        }
        let response = try await client
            .rpc("get_sent_requests", params: ["p_user_id": userId.uuidString.lowercased()])
            .execute()
        return try JSONDecoder().decode([SentRequest].self, from: response.data)
    }

    func deleteFriend(_ friendId: UUID) async throws {
        guard let userId = try? await client.auth.session.user.id else {
            throw FriendServiceError.notAuthenticated
        }
        let uid = userId.uuidString.lowercased()
        let fid = friendId.uuidString.lowercased()
        try await client
            .from("friendships")
            .delete()
            .or("and(user_id.eq.\(uid),friend_id.eq.\(fid)),and(user_id.eq.\(fid),friend_id.eq.\(uid))")
            .execute()
    }
}

enum FriendServiceError: LocalizedError {
    case notAuthenticated
    case profileNotFound
    case cannotAddSelf

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .profileNotFound:
            return "Profile not found"
        case .cannotAddSelf:
            return "You cannot add yourself."
        }
    }
}

private struct FriendLocalState: Codable {
    var friendCode: String = ""
    var friends: [FriendProfile] = []
    var incoming: [FriendRequest] = []
    var sent: [SentRequest] = []
}

private final class FriendLocalStore {
    private let defaults = UserDefaults.standard
    private let stateKey = "momenta.friend.local-state"

    func load() -> FriendLocalState {
        guard let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(FriendLocalState.self, from: data) else {
            return FriendLocalState()
        }
        return state
    }

    func save(_ state: FriendLocalState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: stateKey)
    }

    func ensureLocalProfile(displayName: String?) {
        _ = friendCode(displayName: displayName)
    }

    func setFriendCode(_ code: String, displayName: String?) {
        var state = load()
        state.friendCode = code
        save(state)
    }

    func friendCode(displayName: String?) -> String {
        var state = load()
        if state.friendCode.isEmpty {
            let prefix = (displayName ?? "MOMENTA")
                .uppercased()
                .replacingOccurrences(of: " ", with: "")
                .prefix(3)
            let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(5)).uppercased()
            state.friendCode = "\(prefix)-\(suffix)"
            save(state)
        }
        return state.friendCode
    }

    func previewProfile(for code: String) -> FriendProfile {
        let state = load()
        if let friend = state.friends.first(where: { $0.friendCode == code }) {
            return friend
        }
        if let sent = state.sent.first(where: { $0.friendCode == code }) {
            return FriendProfile(
                id: sent.friendId,
                displayName: sent.displayName,
                avatarUrl: sent.avatarUrl,
                friendCode: sent.friendCode
            )
        }
        return FriendProfile(
            id: UUID(),
            displayName: "Preview Friend",
            avatarUrl: nil,
            friendCode: code
        )
    }

    func sendRequest(to profile: FriendProfile, note: String?) -> SendRequestResult {
        var state = load()

        if state.friends.contains(where: { $0.friendCode == profile.friendCode }) {
            return .alreadyFriends
        }
        if state.sent.contains(where: { $0.friendCode == profile.friendCode }) {
            return .alreadyPending
        }

        let request = SentRequest(
            id: UUID(),
            userId: UUID(),
            friendId: profile.id,
            status: "pending",
            note: note,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            displayName: profile.displayName,
            avatarUrl: profile.avatarUrl,
            friendCode: profile.friendCode
        )
        state.sent.insert(request, at: 0)
        save(state)
        return .sent
    }

    func acceptRequest(_ friendshipId: UUID) {
        var state = load()
        guard let index = state.incoming.firstIndex(where: { $0.id == friendshipId }) else { return }
        let request = state.incoming.remove(at: index)
        let friend = FriendProfile(
            id: request.userId,
            displayName: request.senderName,
            avatarUrl: request.senderAvatarUrl,
            friendCode: request.senderFriendCode
        )
        if !state.friends.contains(friend) {
            state.friends.insert(friend, at: 0)
        }
        save(state)
    }

    func declineRequest(_ friendshipId: UUID) {
        var state = load()
        state.incoming.removeAll { $0.id == friendshipId }
        save(state)
    }

    func cancelSentRequest(_ friendshipId: UUID) {
        var state = load()
        state.sent.removeAll { $0.id == friendshipId }
        save(state)
    }

    func deleteFriend(_ friendId: UUID) {
        var state = load()
        state.friends.removeAll { $0.id == friendId }
        save(state)
    }
}
