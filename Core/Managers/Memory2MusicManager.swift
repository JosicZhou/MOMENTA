//
//  Memory2MusicManager.swift
//  MOMENTA
//
//  Memory 音乐生成协调器。
//  串联：HealthKit → EmotionML → PromptBuilder → LLM → mergeStyle → Suno → Supabase。
//

import Foundation
import UIKit
import Combine

@MainActor
class Memory2MusicManager: ObservableObject {

    private let baseManager: MusicBaseManager
    private let llmService: LLMServiceProtocol
    private let healthKit: HealthKitService
    private let emotionML: EmotionMLService

    init(
        baseManager: MusicBaseManager,
        llmService: LLMServiceProtocol,
        healthKit: HealthKitService = HealthKitService(),
        emotionML: EmotionMLService = EmotionMLService()
    ) {
        self.baseManager = baseManager
        self.llmService = llmService
        self.healthKit = healthKit
        self.emotionML = emotionML
    }

    static func createDefault() -> Memory2MusicManager {
        let base = MusicBaseManager.createDefault()
        let llm = OpenAILyricsService(
            apiKey: APIConfiguration.openAIAPIKey,
            baseURL: APIConfiguration.openAIBaseURL
        )
        return Memory2MusicManager(baseManager: base, llmService: llm)
    }

    // MARK: - 主流程

    func generate(
        context: MemoryMusicContext,
        onProgress: (String) -> Void
    ) async throws -> GeneratedMusic {
        let generationStartedAt = Date()
        var ctx = context

        // 1. 健康数据 → 情绪推理（若 ViewModel 未提前算好则在此补算）
        if ctx.healthHints == nil, let hr = ctx.heartRate {
            onProgress("Reading emotional context from your session...")
            let emotionStartedAt = Date()
            let hrvForModel = ctx.hrv ?? 50.0
            ctx.healthHints = try? emotionML.predict(heartRate: hr, hrv: hrvForModel)
            print("⏱️ [Memory] Emotion inference finished in \(Self.formattedSeconds(Date().timeIntervalSince(emotionStartedAt)))")
        }

        // 2. 构建 prompt（歌词 vs 纯音乐）
        onProgress("Shaping the memory into music...")
        let promptStartedAt = Date()
        let promptText: String
        if ctx.instrumentalOnly {
            promptText = MemoryInstrumentalPromptBuilder.build(from: ctx)
        } else {
            promptText = MemoryLyricsPromptBuilder.build(from: ctx)
        }
        print("⏱️ [Memory] Prompt assembly finished in \(Self.formattedSeconds(Date().timeIntervalSince(promptStartedAt))) | prompt=\(promptText.count) chars")

        // 3. 调用 LLM
        let request = LyricsGenerationRequest(
            photo: ctx.photo,
            photoPresent: ctx.hasPhoto,
            storyShare: ctx.story ?? "",
            instrumentalOnly: ctx.instrumentalOnly,
            language: ctx.language,
            rawPrompt: promptText
        )

        let lyricsStartedAt = Date()
        let llmResponse = try await llmService.generateLyrics(request: request)
        print("⏱️ [Memory] Lyrics phase finished in \(Self.formattedSeconds(Date().timeIntervalSince(lyricsStartedAt)))")

        // 4. 合并 style（LLM 输出 + 健康 + 环境）
        let mergedStyle = mergeStyle(
            llmStyle: llmResponse.style,
            healthHints: ctx.healthHints,
            context: ctx
        )

        // 5. 构建 Suno 请求
        onProgress("Preparing the composition...")
        let sunoRequest = MusicGenerationRequest(
            prompt: llmResponse.prompt ?? "",
            style: mergedStyle,
            title: llmResponse.title,
            customMode: true,
            instrumental: ctx.instrumentalOnly,
            model: .v5,
            callBackUrl: APIConfiguration.sunoCallbackURL,
            negativeTags: nil,
            vocalGender: extractVocalGender(from: mergedStyle),
            styleWeight: nil,
            weirdnessConstraint: nil,
            audioWeight: nil
        )

        // 6. 提交 Suno 任务
        onProgress("Submitting the generation task...")
        let submissionStartedAt = Date()
        let taskId = try await baseManager.startMusicTask(request: sunoRequest)
        print("⏱️ [Memory] Suno submission finished in \(Self.formattedSeconds(Date().timeIntervalSince(submissionStartedAt)))")

        // 7. Supabase 初始记录
        guard let userId = await SupabaseService.shared.getCurrentUserId() else {
            throw MusicServiceError.apiError(code: 401, message: "用户未登录")
        }

        try await MusicDatabaseService.shared.createInitialRecord(
            taskId: taskId,
            prompt: sunoRequest.prompt,
            style: sunoRequest.style ?? "",
            userId: userId,
            source: "memory"
        )

        // 8. 等待完成：Realtime 与 Suno 直接轮询并发竞速
        onProgress("Creating in the background...")

        return try await withThrowingTaskGroup(of: GeneratedMusic?.self) { group in
            group.addTask {
                do {
                    let stream = MusicDatabaseService.shared.subscribeToTaskUpdate(taskId: taskId)
                    for try await music in stream { return music }
                } catch {
                    print("⚠️ [Memory·Realtime] Stream closed, falling back to direct status polling: \(error.localizedDescription)")
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
                    print("⏱️ [Memory] Total generation completed in \(Self.formattedSeconds(Date().timeIntervalSince(generationStartedAt)))")
                    return music
                }
            }

            throw MusicServiceError.timeout
        }
    }

    // MARK: - Style 合并

    /// 将 LLM 输出的 style 与健康/环境片段合并。
    /// 健康片段优先（已在 prompt 中引导 LLM 使用），此处做保底补充。
    private func mergeStyle(
        llmStyle: String,
        healthHints: HealthMusicHints?,
        context: MemoryMusicContext
    ) -> String {
        var style = llmStyle

        // BPM 是 style 最高优先级，保底兜底：若 LLM 未在输出中包含则强制前插
        if let bpm = context.suggestedBPM {
            let bpmTag = "\(bpm) BPM"
            if !style.uppercased().contains("BPM") {
                style = "\(bpmTag), \(style)"
            } else if !style.contains(bpmTag) {
                // LLM 产出了其他 BPM 值，替换为正确心率值
                let pattern = "\\d+ BPM"
                if let range = style.range(of: pattern, options: .regularExpression) {
                    style.replaceSubrange(range, with: bpmTag)
                }
            }
        }

        if let hints = healthHints {
            let fragment = hints.styleFragment
            if !style.lowercased().contains(fragment.lowercased()) {
                style = "\(style), \(fragment)"
            }
        }

        return style
    }

    // MARK: - Helpers

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
