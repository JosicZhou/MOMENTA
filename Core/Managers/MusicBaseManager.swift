//
//  MusicBaseManager.swift
//  Butterfly
//
//  核心底层总管：负责最基础的生成逻辑（从请求参数到生成音乐文件）
//

import Foundation
import Combine

@MainActor
class MusicBaseManager: ObservableObject {
    private let musicService: MusicServiceProtocol
    
    init(musicService: MusicServiceProtocol) {
        self.musicService = musicService
    }
    
    /// 提供一个默认的创建方法
    static func createDefault() -> MusicBaseManager {
        return MusicBaseManager(musicService: SunoDirectService())
    }
    
    /// 仅提交任务并返回 taskId
    func startMusicTask(request: MusicGenerationRequest) async throws -> String {
        return try await musicService.generateMusic(request: request)
    }
    
    /// 等待已有任务完成 (轮询方式)
    func waitForCompletion(taskId: String) async throws -> GeneratedMusic {
        return try await musicService.waitForCompletion(taskId: taskId)
    }
    
    /// 最基本的生成方法：传入构建好的请求，输出音乐对象
    func generateMusic(request: MusicGenerationRequest) async throws -> GeneratedMusic {
        print("🚀 [MusicBaseManager] 开始生成任务...")
        
        // 1. 发起任务
        let taskId = try await startMusicTask(request: request)
        print("✅ [MusicBaseManager] 任务已创建: \(taskId)")
        
        // 2. 轮询等待完成
        let music = try await waitForCompletion(taskId: taskId)
        print("✅ [MusicBaseManager] 音乐生成成功: \(music.title)")
        
        return music
    }
}
