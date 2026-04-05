//
//  CocreateExtendManager.swift
//  MOMENTA
//
//  B 端共创续写编排器。
//  流程：MemoryMusicContext -> LLM -> mergeParams(A,B) -> Suno extend -> 落库 -> 等待完成。
//

import Foundation

@MainActor
class CocreateExtendManager: ObservableObject {

    private let llmService: LLMServiceProtocol
    private let sunoService: SunoDirectService
    private let emotionML: EmotionMLService

    init(
        llmService: LLMServiceProtocol? = nil,
        sunoService: SunoDirectService = SunoDirectService(),
        emotionML: EmotionMLService = EmotionMLService()
    ) {
        self.llmService = llmService ?? OpenAILyricsService(
            apiKey: APIConfiguration.openAIAPIKey,
            baseURL: APIConfiguration.openAIBaseURL
        )
        self.sunoService = sunoService
        self.emotionML = emotionML
    }

    static func createDefault() -> CocreateExtendManager {
        CocreateExtendManager()
    }

    // MARK: - BPM 小节对齐

    static func computeContinueAt(
        totalDuration: Double,
        bpm: Int = 120,
        targetRatio: Double = 0.5
    ) -> Double {
        let barDuration = 4.0 * 60.0 / Double(bpm)
        let rawCut = totalDuration * targetRatio
        let bars = (rawCut / barDuration).rounded()
        let snapped = bars * barDuration
        return min(max(snapped, barDuration), totalDuration - barDuration)
    }

    // MARK: - B 端续写主流程

    func extend(
        session: CocreateSession,
        context: MemoryMusicContext,
        onProgress: (String) -> Void
    ) async throws -> GeneratedMusic {
        var ctx = context

        // 1. 健康数据推理
        if ctx.healthHints == nil, let hr = ctx.heartRate {
            onProgress("Analyzing your emotional state...")
            let hrvForModel = ctx.hrv ?? 50.0
            ctx.healthHints = try? emotionML.predict(heartRate: hr, hrv: hrvForModel)
        }

        // 2. 构建 B 的 prompt
        onProgress("AI is composing the continuation...")
        let promptText: String
        let isInstrumental = session.profileA.instrumental ?? ctx.instrumentalOnly
        if isInstrumental {
            promptText = MemoryInstrumentalPromptBuilder.build(from: ctx)
        } else {
            promptText = MemoryLyricsPromptBuilder.build(from: ctx)
        }

        // 3. LLM 生成
        let llmRequest = LyricsGenerationRequest(
            photo: ctx.photo,
            photoPresent: ctx.hasPhoto,
            storyShare: ctx.story ?? "",
            instrumentalOnly: isInstrumental,
            language: ctx.language,
            rawPrompt: promptText
        )
        let llmResponse = try await llmService.generateLyrics(request: llmRequest)

        // 4. 合并参数
        let profileB = CocreateProfileSnapshot(
            language: ctx.language,
            instrumental: isInstrumental,
            style: llmResponse.style,
            title: llmResponse.title,
            prompt: llmResponse.prompt,
            bpm: ctx.suggestedBPM,
            vocalGender: nil,
            locationName: ctx.locationName,
            weather: ctx.weather,
            healthQuadrant: ctx.healthHints?.quadrant.rawValue
        )

        let merged = session.profileA.merging(with: profileB)
        let finalStyle = buildExtendStyle(merged: merged, profileA: session.profileA, profileB: profileB)

        // 5. 构建 extend 请求
        onProgress("Preparing to extend the song...")
        guard let audioId = session.sunoAudioId, !audioId.isEmpty else {
            throw CocreateServiceError.invalidState("Missing source audio ID")
        }

        let model = MusicGenerationRequest.SunoModel(rawValue: session.model) ?? .v5

        let extendRequest = MusicExtendRequest(
            defaultParamFlag: true,
            audioId: audioId,
            model: model,
            callBackUrl: APIConfiguration.sunoCallbackURL,
            prompt: llmResponse.prompt ?? "",
            style: finalStyle,
            title: merged.title ?? llmResponse.title,
            continueAt: session.continueAtSec,
            negativeTags: nil,
            vocalGender: extractVocalGender(from: finalStyle),
            styleWeight: nil,
            weirdnessConstraint: nil,
            audioWeight: nil
        )

        // 6. 提交 extend 任务
        onProgress("Submitting extend task...")
        let taskId = try await sunoService.extendMusic(request: extendRequest)

        // 7. Supabase 记录
        guard let userId = await SupabaseService.shared.getCurrentUserId() else {
            throw MusicServiceError.apiError(code: 401, message: "User not authenticated")
        }

        try await MusicDatabaseService.shared.createInitialRecord(
            taskId: taskId,
            prompt: extendRequest.prompt ?? "",
            style: extendRequest.style ?? "",
            userId: userId,
            source: "cocreate",
            parentAudioId: audioId,
            cocreateSessionId: session.id
        )

        // 8. 更新 session
        try await CocreateService.shared.updateSessionForExtend(
            sessionId: session.id,
            extendTaskId: taskId,
            profileB: profileB
        )

        // 9. 等待完成（三路并发竞速，谁先完成谁赢）
        onProgress("AI is creating music, please wait...")

        return try await withThrowingTaskGroup(of: GeneratedMusic?.self) { group in

            // Task A：Supabase Realtime（webhook 回写后触发，速度最快但依赖 webhook）
            group.addTask {
                do {
                    let stream = MusicDatabaseService.shared.subscribeToTaskUpdate(taskId: taskId)
                    for try await music in stream { return music }
                } catch {
                    print("⚠️ [CocreateExtend·Realtime] 连接中断: \(error.localizedDescription)")
                }
                return nil
            }

            // Task B：直接轮询 Suno API（不依赖 webhook，始终可靠）
            group.addTask {
                let music = try await self.sunoService.waitForCompletion(taskId: taskId)
                await MusicDatabaseService.shared.syncCompletedMusic(music)
                return music
            }

            // Task C：轮询数据库（webhook 已写入时的备用路径，间隔 15s，最多 20 次）
            group.addTask {
                var attempts = 0
                while attempts < 20 {
                    try await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                    if let music = try await MusicDatabaseService.shared.fetchMusicRecord(taskId: taskId),
                       music.status == .completed {
                        return music
                    }
                    attempts += 1
                }
                return nil
            }

            while let result = try await group.next() {
                if let music = result {
                    group.cancelAll()
                    try? await CocreateService.shared.markCompleted(sessionId: session.id)
                    onProgress("Song complete!")
                    return music
                }
            }

            // 三路都未返回（极少见），抛超时
            throw MusicServiceError.timeout
        }
    }

    // MARK: - Style 合并

    private func buildExtendStyle(
        merged: CocreateProfileSnapshot,
        profileA: CocreateProfileSnapshot,
        profileB: CocreateProfileSnapshot
    ) -> String {
        var style = merged.style ?? ""

        if let bpmA = profileA.bpm, let bpmB = profileB.bpm, abs(bpmA - bpmB) > 30 {
            if !style.uppercased().contains("BPM") {
                style = "\(bpmA) BPM transitioning to \(bpmB) BPM, \(style)"
            }
        } else if let bpm = merged.bpm {
            if !style.uppercased().contains("BPM") {
                style = "\(bpm) BPM, \(style)"
            }
        }

        return style
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
