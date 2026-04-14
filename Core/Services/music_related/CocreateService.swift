//
//  CocreateService.swift
//  MOMENTA
//
//  共创会话服务层：创建/邀请/查询/更新 cocreate_sessions。
//

import Foundation
import Supabase

class CocreateService {
    static let shared = CocreateService()
    private let client = SupabaseConfig.client

    private init() {}

    // MARK: - Create

    func createSession(
        sourceTaskId: String,
        sunoAudioId: String?,
        continueAtSec: Double,
        model: String,
        profileA: CocreateProfileSnapshot
    ) async throws -> UUID {
        guard let userId = try? await client.auth.session.user.id else {
            throw CocreateServiceError.notAuthenticated
        }

        // 将 profile_a 编码为真正的 JSONB object（而非 JSON 字符串），避免双重编码
        let profileAJSON = try snapshotToAnyJSON(profileA)

        let record: [String: AnyJSON] = [
            "creator_id": .string(userId.uuidString.lowercased()),
            "status": .string("half_ready"),
            "source_task_id": .string(sourceTaskId),
            "suno_audio_id": .string(sunoAudioId ?? ""),
            "continue_at_sec": .double(continueAtSec),
            "model": .string(model),
            "profile_a": profileAJSON
        ]

        let response = try await client
            .from("cocreate_sessions")
            .insert(record)
            .select("id")
            .single()
            .execute()

        let decoder = JSONDecoder()
        struct Row: Decodable { let id: UUID }
        let row = try decoder.decode(Row.self, from: response.data)
        return row.id
    }

    // MARK: - Invite

    func inviteFriend(sessionId: UUID, friendId: UUID) async throws {
        try await client
            .from("cocreate_sessions")
            .update([
                "invitee_id": friendId.uuidString.lowercased(),
                "status": "invited"
            ] as [String: String])
            .eq("id", value: sessionId.uuidString.lowercased())
            .execute()
    }

    // MARK: - Query

    func loadMySessions(userId: UUID) async throws -> [CocreateSession] {
        let response = try await client
            .from("cocreate_sessions")
            .select()
            .eq("creator_id", value: userId.uuidString.lowercased())
            .order("created_at", ascending: false)
            .execute()
        return decodeSessions(from: response.data)
    }

    func loadInvitedSessions(userId: UUID) async throws -> [CocreateSession] {
        let response = try await client
            .from("cocreate_sessions")
            .select()
            .eq("invitee_id", value: userId.uuidString.lowercased())
            .eq("status", value: "invited")
            .order("created_at", ascending: false)
            .execute()
        return decodeSessions(from: response.data)
    }

    /// A 端：拉取我发起的、已完成（B 已续写）的共创会话
    func loadMyCompletedSessions(userId: UUID) async throws -> [CocreateSession] {
        let response = try await client
            .from("cocreate_sessions")
            .select()
            .eq("creator_id", value: userId.uuidString.lowercased())
            .eq("status", value: "completed")
            .order("created_at", ascending: false)
            .execute()
        return decodeSessions(from: response.data)
    }

    // MARK: - Update for B's extend

    func updateSessionForExtend(
        sessionId: UUID,
        extendTaskId: String,
        profileB: CocreateProfileSnapshot
    ) async throws {
        // profile_b 同样编码为真正的 JSONB object
        let profileBJSON = try snapshotToAnyJSON(profileB)

        let updates: [String: AnyJSON] = [
            "extend_task_id": .string(extendTaskId),
            "status": .string("extending"),
            "profile_b": profileBJSON
        ]
        try await client
            .from("cocreate_sessions")
            .update(updates)
            .eq("id", value: sessionId.uuidString.lowercased())
            .execute()
    }

    func markCompleted(sessionId: UUID) async throws {
        try await client
            .from("cocreate_sessions")
            .update(["status": "completed"] as [String: String])
            .eq("id", value: sessionId.uuidString.lowercased())
            .execute()
    }

    // MARK: - Fetch single session

    func fetchSession(id: UUID) async throws -> CocreateSession? {
        let response = try await client
            .from("cocreate_sessions")
            .select()
            .eq("id", value: id.uuidString.lowercased())
            .single()
            .execute()
        let list = decodeSessions(from: response.data)
        return list.first
    }

    // MARK: - Private helpers

    /// CocreateProfileSnapshot → AnyJSON（发送给 Supabase 时存为真正的 JSONB object）
    private func snapshotToAnyJSON(_ snapshot: CocreateProfileSnapshot) throws -> AnyJSON {
        let data = try JSONEncoder().encode(snapshot)
        return try JSONDecoder().decode(AnyJSON.self, from: data)
    }

    // MARK: - Raw decoding
    //
    // profile_a / profile_b 是 JSONB 列。
    // 历史数据因双重编码被存为 JSONB 字符串（"{\\"bpm\\":96,...}"）；
    // 新数据修复后存为 JSONB object（{"bpm":96,...}）。
    // FlexSnapshot 兼容两种格式。

    /// 兼容 JSONB object 和 JSONB string 两种历史格式的解码包装
    private struct FlexSnapshot: Decodable {
        let value: CocreateProfileSnapshot?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            // 优先尝试直接解码为 object（新数据，正确格式）
            if let snapshot = try? container.decode(CocreateProfileSnapshot.self) {
                value = snapshot
                return
            }

            // 回退：解码为 string，再将该 string 解析为 JSON（旧数据，双重编码）
            if let str = try? container.decode(String.self),
               let data = str.data(using: .utf8),
               let snapshot = try? JSONDecoder().decode(CocreateProfileSnapshot.self, from: data) {
                value = snapshot
                return
            }

            value = nil
        }
    }

    private struct RawSession: Decodable {
        let id: UUID
        let creatorId: UUID
        let inviteeId: UUID?
        let status: String
        let sourceTaskId: String
        let sunoAudioId: String?
        let continueAtSec: Double
        let model: String
        let profileA: FlexSnapshot?
        let extendTaskId: String?
        let profileB: FlexSnapshot?
        let createdAt: String?
        let expiresAt: String?
    }

    private func decodeSessions(from data: Data) -> [CocreateSession] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        do {
            let rows = try decoder.decode([RawSession].self, from: data)
            return rows.map(mapRawSession)
        } catch {
            print("⚠️ [CocreateService] decodeSessions array error: \(error)")
            do {
                let single = try decoder.decode(RawSession.self, from: data)
                return [mapRawSession(single)]
            } catch {
                print("⚠️ [CocreateService] decodeSessions single error: \(error)")
                if let raw = String(data: data, encoding: .utf8) {
                    print("⚠️ [CocreateService] raw response: \(raw.prefix(500))")
                }
                return []
            }
        }
    }

    private func mapRawSession(_ raw: RawSession) -> CocreateSession {
        let profileA: CocreateProfileSnapshot = raw.profileA?.value ?? CocreateProfileSnapshot()
        let profileB: CocreateProfileSnapshot? = raw.profileB?.value

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = raw.createdAt.flatMap { isoFormatter.date(from: $0) }
            ?? raw.createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            ?? Date()
        let expiresAt = raw.expiresAt.flatMap { isoFormatter.date(from: $0) }
            ?? raw.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }

        return CocreateSession(
            id: raw.id,
            creatorId: raw.creatorId,
            inviteeId: raw.inviteeId,
            status: CocreateSession.Status(rawValue: raw.status) ?? .halfReady,
            sourceTaskId: raw.sourceTaskId,
            sunoAudioId: raw.sunoAudioId,
            continueAtSec: raw.continueAtSec,
            model: raw.model,
            profileA: profileA,
            extendTaskId: raw.extendTaskId,
            profileB: profileB,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }
}

// MARK: - Errors

enum CocreateServiceError: LocalizedError {
    case notAuthenticated
    case sessionNotFound
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "User not authenticated"
        case .sessionNotFound: return "Cocreate session not found"
        case .invalidState(let msg): return "Invalid session state: \(msg)"
        }
    }
}
