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

    func fetchMusicRecords(taskIds: [String]) async throws -> [GeneratedMusic] {
        guard !taskIds.isEmpty else { return [] }
        let response = try await client
            .from("music_generations")
            .select()
            .in("task_id", values: taskIds)
            .execute()
        return decodeMusicList(from: response.data)
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
        profileA: CocreateProfileSnapshot,
        sourceTitle: String? = nil,
        sourceImageURL: URL? = nil
    ) async throws -> UUID {
        guard let userId = try? await client.auth.session.user.id else {
            throw CocreateServiceError.notAuthenticated
        }

        var record: [String: AnyJSON] = [
            "creator_id": .string(userId.uuidString.lowercased()),
            "status": .string(CocreateSession.Status.halfReady.rawValue),
            "source_task_id": .string(sourceTaskId),
            "suno_audio_id": .string(sunoAudioId ?? ""),
            "continue_at_sec": .double(continueAtSec),
            "model": .string(model),
            "profile_a": try snapshotToAnyJSON(profileA)
        ]

        if let sourceTitle, !sourceTitle.isEmpty {
            record["source_title"] = .string(sourceTitle)
        }
        if let sourceImageURL {
            record["source_image_url"] = .string(sourceImageURL.absoluteString)
        }

        let response = try await client
            .from("cocreate_sessions")
            .insert(record)
            .select("id")
            .single()
            .execute()

        struct Row: Decodable { let id: UUID }
        return try JSONDecoder().decode(Row.self, from: response.data).id
    }

    func inviteFriend(sessionId: UUID, friendId: UUID) async throws {
        try await client
            .from("cocreate_sessions")
            .update([
                "invitee_id": friendId.uuidString.lowercased(),
                "status": CocreateSession.Status.invited.rawValue
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
        return try await enrichSessions(decodeSessions(from: response.data))
    }

    func loadInvitedSessions(userId: UUID) async throws -> [CocreateSession] {
        let response = try await client
            .from("cocreate_sessions")
            .select()
            .eq("invitee_id", value: userId.uuidString.lowercased())
            .eq("status", value: CocreateSession.Status.invited.rawValue)
            .order("created_at", ascending: false)
            .execute()
        return try await enrichSessions(decodeSessions(from: response.data))
    }

    func loadMyCompletedSessions(userId: UUID) async throws -> [CocreateSession] {
        let response = try await client
            .from("cocreate_sessions")
            .select()
            .eq("creator_id", value: userId.uuidString.lowercased())
            .eq("status", value: CocreateSession.Status.completed.rawValue)
            .order("created_at", ascending: false)
            .execute()
        return try await enrichSessions(decodeSessions(from: response.data))
    }

    func updateSessionForExtend(
        sessionId: UUID,
        extendTaskId: String,
        profileB: CocreateProfileSnapshot
    ) async throws {
        let updates: [String: AnyJSON] = [
            "extend_task_id": .string(extendTaskId),
            "status": .string(CocreateSession.Status.extending.rawValue),
            "profile_b": try snapshotToAnyJSON(profileB)
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
            .update(["status": CocreateSession.Status.completed.rawValue] as [String: String])
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
        return try await enrichSessions(decodeSessions(from: response.data)).first
    }

    private func snapshotToAnyJSON(_ snapshot: CocreateProfileSnapshot) throws -> AnyJSON {
        let data = try JSONEncoder().encode(snapshot)
        return try JSONDecoder().decode(AnyJSON.self, from: data)
    }

    private struct FlexSnapshot: Decodable {
        let value: CocreateProfileSnapshot?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let direct = try? container.decode(CocreateProfileSnapshot.self) {
                value = direct
                return
            }
            if let raw = try? container.decode(String.self),
               let data = raw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(CocreateProfileSnapshot.self, from: data) {
                value = decoded
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
        let sourceTitle: String?
        let sourceImageUrl: String?
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

        if let rows = try? decoder.decode([RawSession].self, from: data) {
            return rows.map(mapRawSession)
        }
        if let row = try? decoder.decode(RawSession.self, from: data) {
            return [mapRawSession(row)]
        }
        return []
    }

    private func mapRawSession(_ raw: RawSession) -> CocreateSession {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = raw.createdAt.flatMap { formatter.date(from: $0) }
            ?? raw.createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            ?? Date()
        let expiresAt = raw.expiresAt.flatMap { formatter.date(from: $0) }
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
            profileA: raw.profileA?.value ?? CocreateProfileSnapshot(),
            extendTaskId: raw.extendTaskId,
            profileB: raw.profileB?.value,
            createdAt: createdAt,
            expiresAt: expiresAt,
            creatorDisplayName: nil,
            sourceTitle: raw.sourceTitle,
            sourceImageURL: raw.sourceImageUrl.flatMap(URL.init(string:)),
            inviteeDisplayName: nil
        )
    }

    private func enrichSessions(_ sessions: [CocreateSession]) async throws -> [CocreateSession] {
        guard !sessions.isEmpty else { return [] }

        var enriched = sessions
        let profileIds = Array(Set(
            sessions.flatMap { session in
                [session.creatorId] + (session.inviteeId.map { [$0] } ?? [])
            }
        ))

        if !profileIds.isEmpty {
            let response = try await client
                .from("profiles")
                .select("id, display_name")
                .in("id", values: profileIds.map { $0.uuidString.lowercased() })
                .execute()

            struct ProfileRow: Decodable {
                let id: UUID
                let display_name: String?
            }

            let rows = (try? JSONDecoder().decode([ProfileRow].self, from: response.data)) ?? []
            let nameMap = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.display_name) })

            for index in enriched.indices {
                enriched[index].creatorDisplayName = nameMap[enriched[index].creatorId] ?? enriched[index].creatorDisplayName
                if let inviteeId = enriched[index].inviteeId {
                    enriched[index].inviteeDisplayName = nameMap[inviteeId] ?? enriched[index].inviteeDisplayName
                }
            }
        }

        let missingTaskIds = Array(Set(
            enriched
                .filter { $0.sourceTitle == nil || $0.sourceImageURL == nil }
                .map(\.sourceTaskId)
        ))

        if !missingTaskIds.isEmpty {
            let response = try await client
                .from("music_generations")
                .select("task_id, title, image_url")
                .in("task_id", values: missingTaskIds)
                .execute()

            struct MusicRow: Decodable {
                let task_id: String
                let title: String?
                let image_url: String?
            }

            let rows = (try? JSONDecoder().decode([MusicRow].self, from: response.data)) ?? []
            let musicMap = Dictionary(uniqueKeysWithValues: rows.map { ($0.task_id, $0) })

            for index in enriched.indices {
                guard let music = musicMap[enriched[index].sourceTaskId] else { continue }
                if enriched[index].sourceTitle == nil || enriched[index].sourceTitle?.isEmpty == true {
                    enriched[index].sourceTitle = music.title
                }
                if enriched[index].sourceImageURL == nil {
                    enriched[index].sourceImageURL = music.image_url.flatMap(URL.init(string:))
                }
            }
        }

        return enriched
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
            return message
        }
    }
}
