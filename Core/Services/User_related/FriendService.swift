//
//  FriendService.swift
//  MOMENTA
//
//  好友系统服务层：profile 管理、好友码查人、好友请求 CRUD。
//  依赖 Supabase 表：profiles、friendships。
//

import Foundation
import Supabase

// MARK: - Send Request Result

enum SendRequestResult {
    case sent
    case alreadyFriends
    case alreadyPending
    case cannotAddSelf
}

// MARK: - Service

class FriendService {
    static let shared = FriendService()
    private let client = SupabaseConfig.client

    private init() {}

    // MARK: - Profile

    func ensureProfile(userId: UUID, displayName: String?) async throws {
        try await client
            .rpc("upsert_profile", params: [
                "p_user_id": userId.uuidString.lowercased(),
                "p_display_name": displayName ?? "User"
            ])
            .execute()
    }

    func getMyAvatarUrl() async throws -> String? {
        guard let userId = try? await client.auth.session.user.id else { return nil }
        let response = try await client
            .from("profiles")
            .select("avatar_url")
            .eq("id", value: userId.uuidString.lowercased())
            .single()
            .execute()
        let decoder = JSONDecoder()
        let row = try decoder.decode([String: String?].self, from: response.data)
        return row["avatar_url"] ?? nil
    }

    func getMyFriendCode() async throws -> String {
        guard let userId = try? await client.auth.session.user.id else {
            throw FriendServiceError.notAuthenticated
        }
        let response = try await client
            .from("profiles")
            .select("friend_code")
            .eq("id", value: userId.uuidString.lowercased())
            .single()
            .execute()

        let decoder = JSONDecoder()
        let row = try decoder.decode([String: String].self, from: response.data)
        guard let code = row["friend_code"] else {
            throw FriendServiceError.profileNotFound
        }
        return code
    }

    // MARK: - Avatar

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

    // MARK: - Search

    func searchByFriendCode(_ code: String) async throws -> FriendProfile? {
        let response = try await client
            .rpc("find_user_by_friend_code", params: ["p_code": code])
            .execute()

        let decoder = JSONDecoder()
        let results = try decoder.decode([FriendProfile].self, from: response.data)
        return results.first
    }

    // MARK: - Friend Requests

    /// 发送好友申请，返回操作结果（handled server-side）
    func sendFriendRequest(to friendId: UUID, note: String?) async throws -> SendRequestResult {
        guard let userId = try? await client.auth.session.user.id else {
            throw FriendServiceError.notAuthenticated
        }

        let params: [String: AnyJSON] = [
            "p_from_user_id": .string(userId.uuidString.lowercased()),
            "p_to_user_id":   .string(friendId.uuidString.lowercased()),
            "p_note":         note.map { .string($0) } ?? .null
        ]

        let response = try await client
            .rpc("send_friend_request", params: params)
            .execute()

        let decoder = JSONDecoder()
        // RPC 返回一个 TEXT，Supabase 包在 JSON 字符串里
        let statusCode = (try? decoder.decode(String.self, from: response.data)) ?? "sent"

        switch statusCode {
        case "already_friends":  return .alreadyFriends
        case "already_pending":  return .alreadyPending
        case "cannot_add_self":  return .cannotAddSelf
        default:                 return .sent
        }
    }

    func acceptRequest(_ friendshipId: UUID) async throws {
        try await client
            .from("friendships")
            .update(["status": "accepted"] as [String: String])
            .eq("id", value: friendshipId.uuidString.lowercased())
            .execute()
    }

    /// 拒绝申请 = 直接删除记录（静默，发送方不感知）
    func declineRequest(_ friendshipId: UUID) async throws {
        try await client
            .from("friendships")
            .delete()
            .eq("id", value: friendshipId.uuidString.lowercased())
            .execute()
    }

    /// 撤回我发出的申请
    func cancelSentRequest(_ friendshipId: UUID) async throws {
        try await client
            .from("friendships")
            .delete()
            .eq("id", value: friendshipId.uuidString.lowercased())
            .execute()
    }

    // MARK: - Load

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

        let decoder = JSONDecoder()
        struct Row: Decodable {
            let id: UUID
            let user_id: String
            let friend_id: String
        }
        let rows = try decoder.decode([Row].self, from: response.data)

        let friendIds = rows.map { row -> String in
            row.user_id == uid ? row.friend_id : row.user_id
        }

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
        let profiles = try decoder.decode([ProfileRow].self, from: profileResponse.data)
        return profiles.map { p in
            FriendProfile(
                id: p.id,
                displayName: p.display_name,
                avatarUrl: p.avatar_url,
                friendCode: p.friend_code
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

        let decoder = JSONDecoder()
        var requests = try decoder.decode([FriendRequest].self, from: response.data)

        let senderIds = requests.map { $0.userId.uuidString.lowercased() }
        if !senderIds.isEmpty {
            let profileResponse = try await client
                .from("profiles")
                .select("id, display_name, avatar_url")
                .in("id", values: senderIds)
                .execute()

            struct ProfileRow: Decodable { let id: UUID; let display_name: String?; let avatar_url: String? }
            let profiles = try decoder.decode([ProfileRow].self, from: profileResponse.data)
            let nameMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.display_name ?? "User") })
            let avatarMap = Dictionary(uniqueKeysWithValues: profiles.compactMap { p -> (UUID, String)? in
                guard let url = p.avatar_url, !url.isEmpty else { return nil }
                return (p.id, url)
            })

            for i in requests.indices {
                requests[i].senderName = nameMap[requests[i].userId]
                requests[i].senderAvatarUrl = avatarMap[requests[i].userId]
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

        let decoder = JSONDecoder()
        return try decoder.decode([SentRequest].self, from: response.data)
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

// MARK: - Errors

enum FriendServiceError: LocalizedError {
    case notAuthenticated
    case profileNotFound
    case cannotAddSelf

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "User not authenticated"
        case .profileNotFound: return "Profile not found"
        case .cannotAddSelf: return "Cannot add yourself as a friend"
        }
    }
}
