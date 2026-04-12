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
        let generationStartedAt = Date()
        
        // 1. 调用 LLM 生成歌词和建议风格
        onProgress("Interpreting your prompt with Apple-style clarity...")
        let lyricsStartedAt = Date()
        let lyricsResponse = try await generateLyrics(
            userInput: userInput,
            selectedImage: selectedImage,
            parameters: parameters
        )
        print("⏱️ [Light] Lyrics phase finished in \(Self.formattedSeconds(Date().timeIntervalSince(lyricsStartedAt)))")
        
        // 2. 构建最终的生成请求
        onProgress("Preparing the composition...")
        let sunoRequest = buildSunoRequest(
            lyricsResponse: lyricsResponse,
            parameters: parameters
        )
        
        // 3. 提交任务给 Suno 并获取 taskId
        onProgress("Submitting the generation task...")
        print("🚀 [Suno] 发送请求的回调地址: \(APIConfiguration.sunoCallbackURL)")
        let submissionStartedAt = Date()
        let taskId = try await baseManager.startMusicTask(request: sunoRequest)
        print("⏱️ [Light] Suno submission finished in \(Self.formattedSeconds(Date().timeIntervalSince(submissionStartedAt)))")
        
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
        
        // 5. 等待服务器完成：Realtime 与 Suno 直接轮询并发竞速
        onProgress("Creating in the background...")

        return try await withThrowingTaskGroup(of: GeneratedMusic?.self) { group in
            group.addTask {
                do {
                    let musicStream = MusicDatabaseService.shared.subscribeToTaskUpdate(taskId: taskId)
                    for try await completedMusic in musicStream {
                        return completedMusic
                    }
                } catch {
                    print("⚠️ [Light·Realtime] Stream closed, falling back to direct status polling: \(error.localizedDescription)")
                }
                return nil
            }
            
            group.addTask {
                let music = try await self.baseManager.waitForCompletion(taskId: taskId)
                await MusicDatabaseService.shared.syncCompletedMusic(music)
                return music
            }
            
            while let result = try await group.next() {
                if let music = result {
                    group.cancelAll()
                    onProgress("Music creation complete.")
                    print("⏱️ [Light] Total generation completed in \(Self.formattedSeconds(Date().timeIntervalSince(generationStartedAt)))")
                    return music
                }
            }
            
            throw MusicServiceError.timeout
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
    ) async throws -> LLMMusicResponse {
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
        lyricsResponse: LLMMusicResponse,
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

    private static func formattedSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.2fs", seconds)
    }
}
