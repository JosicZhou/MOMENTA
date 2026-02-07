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
    /// - Parameter source: "mine" | "cocreate"，缺省 "mine"
    func createInitialRecord(taskId: String, prompt: String, style: String, userId: UUID, source: String = "mine") async throws {
        let record: [String: AnyJSON] = [
            "task_id": .string(taskId),
            "user_id": .string(userId.uuidString.lowercased()),
            "prompt": .string(prompt),
            "style": .string(style),
            "status": .string(GeneratedMusic.GenerationStatus.pending.rawValue),
            "created_at": .string(ISO8601DateFormatter().string(from: Date())),
            "source": .string(source)
        ]
        
        try await client
            .from("music_generations")
            .insert(record)
            .execute()
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
                print("📡 [Realtime] 已调用订阅方法")
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
        
        return GeneratedMusic(
            id: taskId,
            title: title,
            style: record["style"]?.stringValue ?? "",
            prompt: record["prompt"]?.stringValue ?? "",
            audioURL: audioURL,
            status: status,
            createdAt: createdAt,
            source: source,
            ownerId: ownerId
        )
    }

    // MARK: - Profile 歌单：按用户拉取

    /// 当前用户「自己生成」的歌曲（Light/Memory，source = mine 或空）
    func fetchMineSongs(userId: UUID) async throws -> [GeneratedMusic] {
        let response = try await client
            .from("music_generations")
            .select()
            .eq("user_id", value: userId.uuidString.lowercased())
            .or("source.is.null,source.eq.mine")
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
