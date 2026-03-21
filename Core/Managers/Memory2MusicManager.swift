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
        var ctx = context

        // 1. 健康数据 → 情绪推理（若 ViewModel 未提前算好则在此补算）
        if ctx.healthHints == nil, let hr = ctx.heartRate {
            onProgress("正在分析生理情绪状态...")
            let hrvForModel = ctx.hrv ?? 50.0
            ctx.healthHints = try? emotionML.predict(heartRate: hr, hrv: hrvForModel)
        }

        // 2. 构建 prompt（歌词 vs 纯音乐）
        onProgress("正在通过 AI 构思音乐...")
        let promptText: String
        if ctx.instrumentalOnly {
            promptText = MemoryInstrumentalPromptBuilder.build(from: ctx)
        } else {
            promptText = MemoryLyricsPromptBuilder.build(from: ctx)
        }

        // 3. 调用 LLM
        let request = LyricsGenerationRequest(
            photo: ctx.photo,
            photoPresent: ctx.hasPhoto,
            storyShare: ctx.story ?? "",
            instrumentalOnly: ctx.instrumentalOnly,
            language: ctx.language,
            rawPrompt: promptText
        )

        let llmResponse = try await llmService.generateLyrics(request: request)

        // 4. 合并 style（LLM 输出 + 健康 + 环境）
        let mergedStyle = mergeStyle(
            llmStyle: llmResponse.style,
            healthHints: ctx.healthHints,
            context: ctx
        )

        // 5. 构建 Suno 请求
        onProgress("正在准备音乐生成...")
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
        onProgress("正在提交生成任务...")
        let taskId = try await baseManager.startMusicTask(request: sunoRequest)

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

        // 8. 等待完成（Realtime + 轮询）
        onProgress("AI 正在后台创作，请稍候...")

        return try await withThrowingTaskGroup(of: GeneratedMusic?.self) { group in
            group.addTask {
                let stream = MusicDatabaseService.shared.subscribeToTaskUpdate(taskId: taskId)
                for try await music in stream { return music }
                return nil
            }

            group.addTask {
                var attempts = 0
                let maxAttempts = 15
                while attempts < maxAttempts {
                    try await Task.sleep(nanoseconds: 20 * 1_000_000_000)
                    print("🔄 [Memory·Polling] 正在主动检查任务状态 (\(attempts + 1)/\(maxAttempts))...")
                    if let music = try await MusicDatabaseService.shared.fetchMusicRecord(taskId: taskId),
                       music.status == .completed {
                        print("✅ [Memory·Polling] 主动查询发现任务已完成！")
                        return music
                    }
                    attempts += 1
                }
                print("⚠️ [Memory·Polling] 达到最大轮询次数 \(maxAttempts)，放弃轮询")
                return nil
            }

            while let result = try await group.next() {
                if let music = result {
                    group.cancelAll()
                    onProgress("音乐创作完成！")
                    return music
                }
            }

            onProgress("正在同步生成状态...")
            return try await baseManager.waitForCompletion(taskId: taskId)
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
}
