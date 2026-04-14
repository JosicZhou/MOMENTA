//
//  MusicDatabaseService.swift
//  MOMENTA
//
//  业务服务层：专门负责音乐生成相关的数据库操作和实时监听
//

import Foundation
import Supabase

class MusicDatabaseService {
    static let shared = MusicDatabaseService()
    private let client = SupabaseConfig.client
    
    private init() {}
    
    /// 创建初始音乐生成记录（在任务提交后立即调用）
    /// - Parameter source: "mine" | "memory" | "cocreate"，缺省 "mine"
    func createInitialRecord(
        taskId: String,
        prompt: String,
        style: String,
        userId: UUID,
        source: String = "mine",
        continueAtSec: Double? = nil,
        parentAudioId: String? = nil,
        cocreateSessionId: UUID? = nil
    ) async throws {
        var record: [String: AnyJSON] = [
            "task_id": .string(taskId),
            "user_id": .string(userId.uuidString.lowercased()),
            "prompt": .string(prompt),
            "style": .string(style),
            "status": .string(GeneratedMusic.GenerationStatus.pending.rawValue),
            "created_at": .string(ISO8601DateFormatter().string(from: Date())),
            "source": .string(source)
        ]

        if let continueAtSec {
            record["continue_at_sec"] = .double(continueAtSec)
        }
        if let parentAudioId, !parentAudioId.isEmpty {
            record["parent_audio_id"] = .string(parentAudioId)
        }
        if let cocreateSessionId {
            record["cocreate_session_id"] = .string(cocreateSessionId.uuidString.lowercased())
        }
        
        try await client
            .from("music_generations")
            .insert(record)
            .execute()
    }

    func updateContinueAt(taskId: String, continueAtSec: Double) async throws {
        try await client
            .from("music_generations")
            .update(["continue_at_sec": continueAtSec] as [String: Double])
            .eq("task_id", value: taskId)
            .execute()
    }

    func syncCompletedMusic(_ music: GeneratedMusic) async {
        guard music.status == .completed else { return }

        var record: [String: AnyJSON] = [
            "status": .string(GeneratedMusic.GenerationStatus.completed.rawValue),
            "title": .string(music.title),
            "style": .string(music.style)
        ]

        if let audioURL = music.audioURL?.absoluteString {
            record["audio_url"] = .string(audioURL)
        }
        if let imageURL = music.imageURL?.absoluteString {
            record["image_url"] = .string(imageURL)
        }
        if let duration = music.duration {
            record["duration"] = .double(duration)
        }

        do {
            try await client
                .from("music_generations")
                .update(record)
                .eq("task_id", value: music.id)
                .neq("status", value: GeneratedMusic.GenerationStatus.completed.rawValue)
                .execute()
        } catch {
            print("⚠️ [MusicDB] Failed to sync completed music: \(error.localizedDescription)")
        }
    }
    
    /// 监听特定任务的状态更新
    /// 使用 Supabase Realtime 监听数据库变化
    func subscribeToTaskUpdate(taskId: String) -> AsyncThrowingStream<GeneratedMusic, Error> {
        return AsyncThrowingStream { continuation in
            print("📡 [Realtime] 开始监听任务更新: \(taskId)")
            
            // 1. 创建通用频道
            let channel = client.channel("music_updates_\(taskId)")
            
            // 2. 监听数据库更新动作
            channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: "music_generations"
            ) { action in
                let record = action.record
                print("📡 [Realtime] 收到数据库变化通知")
                
                // 3. 在本地手动过滤 task_id
                guard let taskIdJSON = record["task_id"],
                      case .string(let currentTaskId) = taskIdJSON,
                      currentTaskId == taskId else {
                    return
                }
                
                print("📡 [Realtime] 匹配到目标任务: \(taskId)")
                
                // 4. 解析记录并检查状态
                if let music = self.parseGeneratedMusic(from: record, taskId: taskId) {
                    print("📡 [Realtime] 任务状态: \(music.status)")
                    if music.status == .completed {
                        print("✅ [Realtime] 任务已完成，推送到流")
                        continuation.yield(music)
                        continuation.finish()
                    }
                }
            }
            
            // 5. 执行订阅
            Task {
                await channel.subscribe()
                let status = await channel.status
                print("📡 [Realtime] 已调用订阅方法, channel status: \(status)")
            }
            
            continuation.onTermination = { @Sendable _ in
                print("📡 [Realtime] 停止监听任务: \(taskId)")
                Task {
                    await channel.unsubscribe()
                }
            }
        }
    }
    
    /// 批量按 task_id 查询多条音乐记录（共创完成后 A 端拉取 B 的续写结果）
    func fetchMusicRecords(taskIds: [String]) async throws -> [GeneratedMusic] {
        guard !taskIds.isEmpty else { return [] }
        let response = try await client
            .from("music_generations")
            .select()
            .in("task_id", values: taskIds)
            .execute()
        return decodeMusicList(from: response.data)
    }

    /// 主动从数据库查询特定任务的状态
    func fetchMusicRecord(taskId: String) async throws -> GeneratedMusic? {
        let response = try await client
            .from("music_generations")
            .select()
            .eq("task_id", value: taskId)
            .single()
            .execute()
        
        // 解析数据
        let decoder = JSONDecoder()
        let record = try decoder.decode([String: AnyJSON].self, from: response.data)
        return parseGeneratedMusic(from: record, taskId: taskId)
    }

    /// 从数据库记录解析 GeneratedMusic（record 需包含 task_id）
    /// 供列表接口使用；支持 created_at、source 解析
    func parseGeneratedMusic(from record: [String: AnyJSON]) -> GeneratedMusic? {
        guard let taskIdJSON = record["task_id"], case .string(let taskId) = taskIdJSON else { return nil }
        return parseGeneratedMusic(from: record, taskId: taskId)
    }

    /// 私有辅助方法：从数据库记录解析 GeneratedMusic 对象
    private func parseGeneratedMusic(from record: [String: AnyJSON], taskId: String) -> GeneratedMusic? {
        guard let statusJSON = record["status"],
              case .string(let statusStr) = statusJSON,
              let status = GeneratedMusic.GenerationStatus(rawValue: statusStr) else {
            return nil
        }
        
        let audioUrlString: String?
        if let urlJSON = record["audio_url"], case .string(let url) = urlJSON {
            audioUrlString = url
        } else {
            audioUrlString = nil
        }
        
        let audioURL = audioUrlString != nil ? URL(string: audioUrlString!) : nil
        
        var imageURL: URL? = nil
        if let imgJSON = record["image_url"], case .string(let imgStr) = imgJSON, let url = URL(string: imgStr) {
            imageURL = url
        }
        
        var title = "Untitled"
        if let titleJSON = record["title"], case .string(let t) = titleJSON {
            title = t
        }
        
        var createdAt = Date()
        if let dateJSON = record["created_at"], case .string(let dateStr) = dateJSON,
           let date = ISO8601DateFormatter().date(from: dateStr) {
            createdAt = date
        }
        
        var source: String? = "mine"
        if let srcJSON = record["source"], case .string(let s) = srcJSON {
            source = s
        }
        
        var ownerId: UUID?
        if let uidJSON = record["user_id"], case .string(let uidStr) = uidJSON, let uid = UUID(uuidString: uidStr) {
            ownerId = uid
        }
        
        // 从 webhook payload 中提取 Suno 音频 track ID
        // payload 结构: { code, data: { data: [ { id: "suno-audio-id", ... } ] } }
        var sunoAudioId: String?
        if let payloadJSON = record["payload"] {
            sunoAudioId = extractSunoAudioId(from: payloadJSON)
        }
        
        var continueAtSec: Double?
        if let capJSON = record["continue_at_sec"], case .double(let cap) = capJSON {
            continueAtSec = cap
        }

        var duration: Double?
        if let durationJSON = record["duration"], case .double(let value) = durationJSON {
            duration = value
        }

        return GeneratedMusic(
            id: taskId,
            title: title,
            style: record["style"]?.stringValue ?? "",
            prompt: record["prompt"]?.stringValue ?? "",
            audioURL: audioURL,
            imageURL: imageURL,
            sunoAudioId: sunoAudioId,
            status: status,
            createdAt: createdAt,
            source: source,
            ownerId: ownerId,
            duration: duration,
            continueAtSec: continueAtSec
        )
    }
    
    /// 从 webhook 回调的 payload JSON 中提取 Suno 音频 track ID
    /// 路径: payload.data.data[0].id
    private func extractSunoAudioId(from payloadJSON: AnyJSON) -> String? {
        guard case .object(let root) = payloadJSON,
              let dataObj = root["data"], case .object(let dataDict) = dataObj,
              let innerData = dataDict["data"], case .array(let items) = innerData,
              let firstItem = items.first, case .object(let itemDict) = firstItem,
              let idVal = itemDict["id"], case .string(let audioId) = idVal else {
            return nil
        }
        return audioId
    }

    // MARK: - Profile 歌单：按用户拉取

    /// 当前用户「自己生成」的歌曲（Light/Memory，source = mine / memory 或空）
    func fetchMineSongs(userId: UUID) async throws -> [GeneratedMusic] {
        let response = try await client
            .from("music_generations")
            .select()
            .eq("user_id", value: userId.uuidString.lowercased())
            .or("source.is.null,source.eq.mine,source.eq.memory")
            .order("created_at", ascending: false)
            .execute()
        return decodeMusicList(from: response.data)
    }

    /// 当前用户在 Memories 中生成的歌曲
    func fetchMemorySongs(userId: UUID) async throws -> [GeneratedMusic] {
        let response = try await client
            .from("music_generations")
            .select()
            .eq("user_id", value: userId.uuidString.lowercased())
            .eq("source", value: "memory")
            .order("created_at", ascending: false)
            .execute()
        return decodeMusicList(from: response.data)
    }

    /// 当前用户「共创」的歌曲
    func fetchCocreateSongs(userId: UUID) async throws -> [GeneratedMusic] {
        let response = try await client
            .from("music_generations")
            .select()
            .eq("user_id", value: userId.uuidString.lowercased())
            .eq("source", value: "cocreate")
            .order("created_at", ascending: false)
            .execute()
        return decodeMusicList(from: response.data)
    }

    /// 别人分享给我的歌曲（通过 RPC）
    func fetchSharedSongs(userId: UUID) async throws -> [GeneratedMusic] {
        let response = try await client
            .rpc("get_shared_songs_for_user", params: ["p_to_user_id": userId.uuidString.lowercased()])
            .execute()
        return decodeMusicList(from: response.data)
    }

    /// 删除歌曲（仅限本人拥有的：mine/cocreate）
    func deleteMusic(taskId: String, userId: UUID) async throws {
        try await client
            .from("music_generations")
            .delete()
            .eq("task_id", value: taskId)
            .eq("user_id", value: userId.uuidString.lowercased())
            .execute()
    }

    func decodeMusicList(from data: Data) -> [GeneratedMusic] {
        let decoder = JSONDecoder()
        guard let array = try? decoder.decode([[String: AnyJSON]].self, from: data) else { return [] }
        return array.compactMap { parseGeneratedMusic(from: $0) }
    }
}

final class CocreateService {
    static let shared = CocreateService()
    private let client = SupabaseConfig.client

    private init() {}

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

    func updateSessionForExtend(
        sessionId: UUID,
        extendTaskId: String,
        profileB: CocreateProfileSnapshot
    ) async throws {
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

    func declineSession(sessionId: UUID) async throws {
        try await client
            .from("cocreate_sessions")
            .update(["status": CocreateSession.Status.expired.rawValue] as [String: String])
            .eq("id", value: sessionId.uuidString.lowercased())
            .execute()
    }

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

    private func snapshotToAnyJSON(_ snapshot: CocreateProfileSnapshot) throws -> AnyJSON {
        let data = try JSONEncoder().encode(snapshot)
        return try JSONDecoder().decode(AnyJSON.self, from: data)
    }

    private struct FlexSnapshot: Decodable {
        let value: CocreateProfileSnapshot?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let snapshot = try? container.decode(CocreateProfileSnapshot.self) {
                value = snapshot
                return
            }

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

enum CocreateServiceError: LocalizedError {
    case notAuthenticated
    case sessionNotFound
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .sessionNotFound:
            return "Cocreate session not found"
        case .invalidState(let message):
            return "Invalid session state: \(message)"
        }
    }
}
