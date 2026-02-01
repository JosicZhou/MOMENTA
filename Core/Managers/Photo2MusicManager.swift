//
//  Photo2MusicManager.swift
//  Butterfly
//
//  输入：图片+描述；输出：音乐
//

import Foundation
import UIKit
import Combine

@MainActor
class Photo2MusicManager: ObservableObject {
    private let baseManager: MusicBaseManager
    private let llmService: LLMServiceProtocol
    
    init(baseManager: MusicBaseManager, llmService: LLMServiceProtocol) {
        self.baseManager = baseManager
        self.llmService = llmService
    }
    
    /// 提供一个方便的默认创建方法
    static func createDefault() -> Photo2MusicManager {
        let base = MusicBaseManager.createDefault()
        let llm = OpenAILyricsService(
            apiKey: APIConfiguration.openAIAPIKey,
            baseURL: APIConfiguration.openAIBaseURL
        )
        return Photo2MusicManager(baseManager: base, llmService: llm)
    }
    
    /// 智能生成流程：图片/描述 -> LLM解析 -> MusicBaseManager生成 -> Supabase 持久化
    func generate(
        userInput: String,
        selectedImage: UIImage?,
        parameters: MusicParameters,
        onProgress: (String) -> Void
    ) async throws -> GeneratedMusic {
        
        // 1. 调用 LLM 生成歌词和建议风格
        onProgress("正在通过 AI 解析灵感...")
        let lyricsResponse = try await generateLyrics(
            userInput: userInput,
            selectedImage: selectedImage,
            parameters: parameters
        )
        
        // 2. 构建最终的生成请求
        onProgress("正在准备音乐生成...")
        let sunoRequest = buildSunoRequest(
            lyricsResponse: lyricsResponse,
            parameters: parameters
        )
        
        // 3. 提交任务给 Suno 并获取 taskId
        onProgress("正在提交生成任务...")
        print("🚀 [Suno] 发送请求的回调地址: \(APIConfiguration.sunoCallbackURL)")
        let taskId = try await baseManager.startMusicTask(request: sunoRequest)
        
        // 4. 在 Supabase 创建初始记录
        guard let userId = await SupabaseService.shared.getCurrentUserId() else {
            throw MusicServiceError.apiError(code: 401, message: "用户未登录")
        }
        
        try await MusicDatabaseService.shared.createInitialRecord(
            taskId: taskId,
            prompt: sunoRequest.prompt,
            style: sunoRequest.style ?? "",
            userId: userId
        )
        
        // 5. 等待服务器完成 (Realtime + 轮询 双重保障)
        onProgress("AI 正在后台创作，请稍候...")
        
        return try await withThrowingTaskGroup(of: GeneratedMusic?.self) { group in
            // 方式 A: Realtime 监听
            group.addTask {
                let musicStream = MusicDatabaseService.shared.subscribeToTaskUpdate(taskId: taskId)
                for try await completedMusic in musicStream {
                    return completedMusic
                }
                return nil
            }
            
            // 方式 B: 定时轮询 (每 20 秒查一次)
            group.addTask {
                var attempts = 0
                let maxPollingAttempts = 15 // 最多轮询 5 分钟 (15 * 20s)
                
                while attempts < maxPollingAttempts {
                    // 等待 20 秒再开始第一次轮询，给 Suno 一点时间
                    try await Task.sleep(nanoseconds: 20 * 1_000_000_000)
                    
                    print("🔄 [Polling] 正在主动检查任务状态 (\(attempts + 1)/\(maxPollingAttempts))...")
                    if let music = try await MusicDatabaseService.shared.fetchMusicRecord(taskId: taskId),
                       music.status == .completed {
                        print("✅ [Polling] 主动查询发现任务已完成！")
                        return music
                    }
                    attempts += 1
                }
                return nil
            }
            
            // 只要其中任何一个任务返回了完成的音乐，就结束
            while let result = try await group.next() {
                if let music = result {
                    group.cancelAll() // 停止另一个任务
                    onProgress("音乐创作完成！")
                    return music
                }
            }
            
            // 如果都失败了，使用旧的轮询作为最后兜底
            onProgress("正在同步生成状态...")
            return try await baseManager.waitForCompletion(taskId: taskId)
        }
    }
    
    /// 将生成的音乐保存到 Supabase (此方法在 Webhook 模式下可能不再需要，因为服务器会处理)
    private func saveToSupabase(music: GeneratedMusic) async throws {
        // 1. 检查配置是否已填充
        guard SupabaseConfig.anonKey != "your-anon-key" else {
            print("ℹ️ Supabase 未配置，跳过同步")
            return
        }
        
        // 2. 获取当前用户 (这里需要你实现登录逻辑，目前先尝试获取)
        // 注意：如果你还没做登录，这里可能会报错
        guard let user = try? await SupabaseConfig.client.auth.session.user else {
            print("ℹ️ 用户未登录，跳过云端保存")
            return
        }
        
        guard let audioURL = music.audioURL else { return }
        
        // 3. 下载音频数据
        let data = try await SupabaseService.shared.downloadData(from: audioURL)
        
        // 4. 上传到 Storage
        let fileName = "\(music.id).mp3"
        let publicURL = try await SupabaseService.shared.uploadMusic(
            fileData: data,
            fileName: fileName,
            userId: user.id
        )
        
        // 5. 保存记录到数据库
        try await SupabaseService.shared.saveMusicRecord(
            music: music,
            audioPublicURL: publicURL,
            userId: user.id
        )
    }
    
    // MARK: - 私有辅助方法
    
    private func generateLyrics(
        userInput: String,
        selectedImage: UIImage?,
        parameters: MusicParameters
    ) async throws -> LyricsGenerationResponse {
        var photoBase64: String?
        if let image = selectedImage {
            photoBase64 = ImageUtility.toBase64(image: image)
        }
        
        let request = LyricsGenerationRequest(
            photo: photoBase64,
            photoPresent: selectedImage != nil,
            storyShare: userInput,
            instrumentalOnly: !parameters.hasVocals,
            language: parameters.language
        )
        
        return try await llmService.generateLyrics(request: request)
    }
    
    private func buildSunoRequest(
        lyricsResponse: LyricsGenerationResponse,
        parameters: MusicParameters
    ) -> MusicGenerationRequest {
        let finalStyle: String
        
        if parameters.useAIRecommendation {
            finalStyle = lyricsResponse.style
        } else {
            var styleComponents: [String] = []
            if let userStyle = parameters.style { styleComponents.append(userStyle) }
            if let userInstrument = parameters.instrument { styleComponents.append(userInstrument) }
            if parameters.hasVocals {
                styleComponents.append("male vocals")
            } else {
                styleComponents.append("Instrumental")
            }
            finalStyle = styleComponents.joined(separator: ", ")
        }
        
        return MusicGenerationRequest(
            prompt: lyricsResponse.prompt ?? "",
            style: finalStyle,
            title: lyricsResponse.title,
            customMode: true,
            instrumental: !parameters.hasVocals,
            model: .v5,
            callBackUrl: APIConfiguration.sunoCallbackURL,
            negativeTags: nil,
            vocalGender: extractVocalGender(from: finalStyle),
            styleWeight: nil,
            weirdnessConstraint: nil,
            audioWeight: nil
        )
    }
    
    private func extractVocalGender(from style: String) -> MusicGenerationRequest.VocalGender? {
        let lowercased = style.lowercased()
        if lowercased.contains("male vocal") && !lowercased.contains("female") {
            return .male
        } else if lowercased.contains("female vocal") {
            return .female
        }
        return nil
    }
}
